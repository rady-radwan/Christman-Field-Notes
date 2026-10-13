import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import 'repo.dart';

const _uuid = Uuid();

/// Stores everything in one JSON file plus a photos folder on this computer.
/// Used until the shared server is set up.
class LocalRepo extends Repo {
  LocalRepo._(this._dir);

  final Directory _dir;
  final _changes = StreamController<void>.broadcast();

  List<AppUser> _users = [];
  List<Project> _projects = [];
  Map<String, Set<String>> _members = {};
  List<Note> _notes = [];
  String? _currentUserId;

  static Future<LocalRepo> open() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'FieldNotes'));
    await Directory(p.join(dir.path, 'photos')).create(recursive: true);
    final repo = LocalRepo._(dir);
    await repo._load();
    return repo;
  }

  File get _file => File(p.join(_dir.path, 'data.json'));
  String get _photosDir => p.join(_dir.path, 'photos');

  Future<void> _load() async {
    if (!await _file.exists()) return;
    try {
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      _users = ((j['users'] as List?) ?? []).map((e) => AppUser.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      _projects =
          ((j['projects'] as List?) ?? []).map((e) => Project.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      _members = ((j['members'] as Map?) ?? {}).map(
        (k, v) => MapEntry(k.toString(), ((v as List?) ?? []).map((e) => e.toString()).toSet()),
      );
      _notes = ((j['notes'] as List?) ?? []).map((e) => Note.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      _currentUserId = j['current_user_id'] as String?;
    } catch (_) {
      // Keep a copy of an unreadable file instead of losing it.
      await _file.copy(p.join(_dir.path, 'data-unreadable-${DateTime.now().millisecondsSinceEpoch}.json'));
    }
  }

  Future<void> _save() async {
    final data = {
      'version': 1,
      'users': _users.map((u) => u.toJson()).toList(),
      'projects': _projects.map((pr) => pr.toJson()).toList(),
      'members': _members.map((k, v) => MapEntry(k, v.toList())),
      'notes': _notes.map((n) => n.toJson()).toList(),
      'current_user_id': _currentUserId,
    };
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(data), flush: true);
    if (await _file.exists()) await _file.delete();
    await tmp.rename(_file.path);
    _changes.add(null);
  }

  AppUser? get _me {
    for (final u in _users) {
      if (u.id == _currentUserId) return u;
    }
    return null;
  }

  AppUser _requireMe() {
    final me = _me;
    if (me == null) throw RepoException('Please sign in again.');
    return me;
  }

  Future<String> _savePhoto(List<int> bytes) async {
    final name = '${_uuid.v4()}.jpg';
    await File(p.join(_photosDir, name)).writeAsBytes(bytes, flush: true);
    return 'file:$name';
  }

  @override
  bool get isServer => false;

  @override
  String get modeLabel => 'This computer only';

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<AppUser?> restoreSession() async => _me;

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    final e = email.trim().toLowerCase();
    AppUser? u;
    for (final x in _users) {
      if (x.email.toLowerCase() == e) u = x;
    }
    if (u == null) throw RepoException('No account with that email on this computer. Use "Request access" first.');
    if (u.status == MemberStatus.removed) throw RepoException('This account was removed by an admin.');
    _currentUserId = u.id;
    await _save();
    return u;
  }

  @override
  Future<AppUser> register({required String name, required String email, required String password}) async {
    final e = email.trim().toLowerCase();
    if (_users.any((x) => x.email.toLowerCase() == e)) {
      throw RepoException('That email already has an account. Sign in instead.');
    }
    final first = _users.isEmpty;
    final u = AppUser(
      id: _uuid.v4(),
      name: name.trim(),
      email: e,
      // The very first account becomes the admin; later ones wait for approval.
      isAdmin: first,
      status: first ? MemberStatus.approved : MemberStatus.pending,
    );
    _users.add(u);
    _currentUserId = u.id;
    await _save();
    return u;
  }

  @override
  Future<void> signOut() async {
    _currentUserId = null;
    await _save();
  }

  @override
  Future<AppUser?> refreshMe() async => _me;

  @override
  Future<List<AppUser>> users() async {
    final me = _me;
    if (me != null && me.isAdmin) return List.of(_users);
    return _users.where((u) => u.isApproved).toList();
  }

  @override
  Future<void> updateUser(AppUser user) async {
    if (!_requireMe().isAdmin) throw RepoException('Only an admin can change accounts.');
    final i = _users.indexWhere((u) => u.id == user.id);
    if (i >= 0) _users[i] = user;
    await _save();
  }

  @override
  Future<List<Project>> projects() async {
    final me = _requireMe();
    if (me.isAdmin) return List.of(_projects);
    return _projects.where((pr) => (_members[pr.id] ?? {}).contains(me.id)).toList();
  }

  @override
  Future<Project> createProject(String name) async {
    final me = _requireMe();
    if (!me.isAdmin) throw RepoException('Only an admin can add projects.');
    final pr = Project(id: _uuid.v4(), name: name.trim(), categories: List.of(defaultCategories));
    _projects.add(pr);
    _members[pr.id] = {me.id};
    await _save();
    return pr;
  }

  @override
  Future<void> updateProject(Project project) async {
    if (!_requireMe().isAdmin) throw RepoException('Only an admin can change projects.');
    final i = _projects.indexWhere((x) => x.id == project.id);
    if (i >= 0) _projects[i] = project;
    await _save();
  }

  @override
  Future<Map<String, Set<String>>> projectMembers() async => _members.map((k, v) => MapEntry(k, Set.of(v)));

  @override
  Future<void> setProjectMember(String projectId, String userId, bool member) async {
    if (!_requireMe().isAdmin) throw RepoException('Only an admin can change project members.');
    final set = _members.putIfAbsent(projectId, () => {});
    member ? set.add(userId) : set.remove(userId);
    await _save();
  }

  @override
  Future<List<Note>> notes(String projectId) async => _notes.where((n) => n.projectId == projectId).toList();

  @override
  Future<Note> createNote(String projectId, NoteDraft draft) async {
    final me = _requireMe();
    final photos = <String>[];
    for (final b in draft.newPhotos) {
      photos.add(await _savePhoto(b));
    }
    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      projectId: projectId,
      name: draft.name,
      comment: draft.comment,
      category: draft.category,
      priority: draft.priority,
      status: NoteStatus.active,
      issuerId: me.id,
      assignedIds: draft.assignedIds,
      photos: photos,
      createdAt: now,
      updatedAt: now,
    );
    _notes.add(note);
    await _save();
    return note;
  }

  @override
  Future<Note> updateNote(Note note, {List<List<int>> addPhotos = const []}) async {
    _requireMe();
    final added = <String>[];
    for (final b in addPhotos) {
      added.add(await _savePhoto(b));
    }
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i < 0) throw RepoException('This note no longer exists.');
    final updated = note.copyWith(
      photos: [...note.photos, ...added],
      updatedAt: DateTime.now(),
      replies: _notes[i].replies,
    );
    _notes[i] = updated;
    await _save();
    return updated;
  }

  @override
  Future<void> deleteNote(Note note) async {
    _requireMe();
    _notes.removeWhere((n) => n.id == note.id);
    await _save();
  }

  @override
  Future<Reply> addReply(Note note, String text, List<List<int>> photos) async {
    final me = _requireMe();
    final refs = <String>[];
    for (final b in photos) {
      refs.add(await _savePhoto(b));
    }
    final reply = Reply(
      id: _uuid.v4(),
      noteId: note.id,
      authorId: me.id,
      text: text,
      photos: refs,
      createdAt: DateTime.now(),
    );
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i < 0) throw RepoException('This note no longer exists.');
    _notes[i] = _notes[i].copyWith(replies: [..._notes[i].replies, reply]);
    await _save();
    return reply;
  }

  @override
  Future<void> deleteReply(Reply reply) async {
    final i = _notes.indexWhere((n) => n.id == reply.noteId);
    if (i < 0) return;
    _notes[i] = _notes[i].copyWith(replies: _notes[i].replies.where((r) => r.id != reply.id).toList());
    await _save();
  }

  @override
  Future<ImageProvider> image(String ref) async {
    final name = ref.startsWith('file:') ? ref.substring(5) : ref;
    return FileImage(File(p.join(_photosDir, name)));
  }

  /// Adds a few example notes (no photos) so the screens can be tried out.
  Future<void> addSampleNotes(String projectId) async {
    final me = _requireMe();
    final now = DateTime.now();
    DateTime ago(int days, int hour) {
      final d = now.subtract(Duration(days: days));
      return DateTime(d.year, d.month, d.day, hour, 10);
    }

    Note n(String name, String cat, Priority pr, NoteStatus st, int days, String comment, {bool mine = false}) {
      final created = ago(days, 9 + days % 6);
      return Note(
        id: _uuid.v4(),
        projectId: projectId,
        name: name,
        comment: comment,
        category: cat,
        priority: pr,
        status: st,
        issuerId: me.id,
        assignedIds: mine ? [me.id] : const [],
        photos: const [],
        createdAt: created,
        updatedAt: created,
      );
    }

    _notes.addAll([
      n('Fire damper missing at corridor 3B', 'MEP', Priority.urgent, NoteStatus.active, 0,
          'Fire damper is missing at the rated corridor wall above the ceiling grid. Please install before close-in.'),
      n('Open edge at Level 4 east slab, no guardrail', 'Safety', Priority.urgent, NoteStatus.active, 1,
          'Guardrail removed for the hoist and not put back. Stay clear until restored.'),
      n('Beam B-12 connection missing bolts', 'Steel', Priority.critical, NoteStatus.active, 4,
          'Two bolts missing at the shear tab. Complete and re-inspect before decking.', mine: true),
      n('Duct clashes with sprinkler main, Room 214', 'MEP', Priority.high, NoteStatus.active, 5,
          'Supply duct runs into the sprinkler main. Coordinate a reroute and update the model.'),
      n('Honeycombing on column C-7', 'Structure', Priority.high, NoteStatus.suspended, 6,
          'On hold until the engineer of record reviews the repair method.'),
      n('Debris blocking stair 2 landing', 'Safety', Priority.low, NoteStatus.solved, 7,
          'Housekeeping needed at the stair 2 landing on Level 3.'),
      n('Curtain wall anchor spacing', 'Architecture', Priority.medium, NoteStatus.suspended, 19,
          'Spacing looks wider than the shop drawings. Waiting on the facade consultant.'),
    ]);
    await _save();
  }

  @override
  void dispose() => _changes.close();
}
