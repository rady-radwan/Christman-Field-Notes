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
  List<ProjectInvite> _invites = [];
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
      _invites = ((j['invites'] as List?) ?? [])
          .map((e) => ProjectInvite.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _currentUserId = j['current_user_id'] as String?;
      _numberOldNotes();
    } catch (_) {
      // Keep a copy of an unreadable file instead of losing it.
      await _file.copy(p.join(_dir.path, 'data-unreadable-${DateTime.now().millisecondsSinceEpoch}.json'));
    }
  }

  Future<void> _save() async {
    final data = {
      'version': 2,
      'users': _users.map((u) => u.toJson()).toList(),
      'projects': _projects.map((pr) => pr.toJson()).toList(),
      'members': _members.map((k, v) => MapEntry(k, v.toList())),
      'notes': _notes.map((n) => n.toJson()).toList(),
      'invites': _invites.map((i) => i.toJson()).toList(),
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

  Future<String> _savePhoto(List<int> bytes, {String ext = 'jpg'}) async {
    final name = '${_uuid.v4()}.$ext';
    await File(p.join(_photosDir, name)).writeAsBytes(bytes, flush: true);
    return 'file:$name';
  }

  Future<List<String>> _saveAudio(List<NewAudio> clips) async =>
      [for (final a in clips) await _savePhoto(a.bytes, ext: a.extension)];

  Project? _project(String id) {
    for (final pr in _projects) {
      if (pr.id == id) return pr;
    }
    return null;
  }

  /// Next number and code for a new observation in this project and category.
  (int, String) _nextNumber(String projectId, String category) {
    var max = 0;
    for (final n in _notes) {
      if (n.projectId == projectId && n.category == category && (n.number ?? 0) > max) max = n.number!;
    }
    final pr = _project(projectId);
    final num = max + 1;
    final code = '${pr?.code ?? 'PRJ'}-${pr?.categoryCode(category) ?? suggestCategoryAbbr(category)}-'
        '${num.toString().padLeft(3, '0')}';
    return (num, code);
  }

  /// Observations saved by older versions get numbers, oldest first.
  void _numberOldNotes() {
    final old = _notes.where((n) => n.number == null).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final n in old) {
      final (num, code) = _nextNumber(n.projectId, n.category);
      final i = _notes.indexOf(n);
      _notes[i] = Note.fromJson({...n.toJson(), 'number': num, 'code': code});
    }
  }

  bool _isMember(String projectId) {
    final me = _me;
    if (me == null || !me.isApproved) return false;
    return me.isAdmin || (_members[projectId]?.contains(me.id) ?? false);
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
  Future<AppUser> updateMyProfile({required String name, required String company}) async {
    final me = _requireMe();
    final updated = me.copyWith(name: name.trim(), company: company.trim());
    _users = [for (final u in _users) u.id == me.id ? updated : u];
    await _save();
    return updated;
  }

  @override
  Future<List<AppUser>> users() async {
    final me = _me;
    if (me != null && me.isAdmin) return List.of(_users);
    final visible = _users.where((u) => u.isApproved || u.id == me?.id);
    // Guests see names only, not email addresses.
    return me == null
        ? visible
            .map((u) => AppUser(id: u.id, name: u.name, email: '', isAdmin: u.isAdmin, status: u.status, company: u.company))
            .toList()
        : visible.toList();
  }

  @override
  Future<void> updateUser(AppUser user) async {
    if (!_requireMe().isAdmin) throw RepoException('Only an admin can change accounts.');
    final i = _users.indexWhere((u) => u.id == user.id);
    if (i >= 0) _users[i] = user;
    await _save();
  }

  @override
  Future<List<Project>> projects() async =>
      _projects.where((pr) => pr.guestVisible || _isMember(pr.id)).toList(); // members only, unless guests may look

  @override
  Future<Project> createProject(Project draft) async {
    final me = _requireMe();
    if (!me.isAdmin) throw RepoException('Only an admin can add projects.');
    final pr = Project(
      id: _uuid.v4(),
      name: draft.name.trim(),
      categories: draft.categories,
      abbr: draft.abbr.trim().toUpperCase(),
      categoryAbbrs: draft.categoryAbbrs,
      guestVisible: draft.guestVisible,
    );
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
  Future<List<ProjectInvite>> invites() async {
    final me = _me;
    if (me == null) return [];
    return _invites.where((i) => me.isAdmin || i.invitedBy == me.id || _isMember(i.projectId)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> suggestMember(String projectId, {required String email, required String name, required String company}) async {
    final me = _requireMe();
    if (!_isMember(projectId)) throw RepoException('Only members of this project can suggest people.');
    final e = email.trim().toLowerCase();
    if (_invites.any((i) => i.projectId == projectId && i.isPending && i.email == e)) {
      throw RepoException('That person is already waiting for approval on this project.');
    }
    _invites.add(ProjectInvite(
      id: _uuid.v4(),
      projectId: projectId,
      email: e,
      name: name.trim(),
      company: company.trim(),
      invitedBy: me.id,
      status: 'pending',
      createdAt: DateTime.now(),
    ));
    await _save();
  }

  @override
  Future<void> approveInvite(ProjectInvite invite) async {
    if (!_requireMe().isAdmin) throw RepoException('Only an admin can approve invitations.');
    _invites = [for (final i in _invites) i.id == invite.id ? i.copyWith(status: 'approved') : i];
    final idx = _users.indexWhere((u) => u.email.toLowerCase() == invite.email.toLowerCase());
    if (idx >= 0) {
      final u = _users[idx];
      _users[idx] = u.copyWith(
        status: u.status == MemberStatus.removed ? u.status : MemberStatus.approved,
        company: u.company.isEmpty ? invite.company : u.company,
      );
      _members.putIfAbsent(invite.projectId, () => {}).add(u.id);
    }
    await _save();
  }

  @override
  Future<void> declineInvite(ProjectInvite invite) async {
    if (!_requireMe().isAdmin) throw RepoException('Only an admin can decline invitations.');
    _invites = [for (final i in _invites) i.id == invite.id ? i.copyWith(status: 'declined') : i];
    await _save();
  }

  @override
  Future<List<Note>> notes(String projectId) async {
    final pr = _project(projectId);
    if (pr == null || !(pr.guestVisible || _isMember(projectId))) return [];
    return _notes.where((n) => n.projectId == projectId).toList();
  }

  @override
  Future<Note> createNote(String projectId, NoteDraft draft) async {
    final me = _requireMe();
    final photos = <String>[];
    for (final b in draft.newPhotos) {
      photos.add(await _savePhoto(b));
    }
    final now = DateTime.now();
    final (num, code) = _nextNumber(projectId, draft.category);
    final note = Note(
      id: _uuid.v4(),
      projectId: projectId,
      name: draft.name,
      comment: draft.comment,
      category: draft.category,
      priority: draft.priority,
      status: NoteStatus.open,
      issuerId: me.id,
      assignedIds: draft.assignedIds,
      photos: photos,
      obsType: draft.obsType,
      location: draft.location.trim(),
      dueAt: draft.dueAt,
      number: num,
      code: code,
      audio: await _saveAudio(draft.newAudio),
      createdAt: now,
      updatedAt: now,
    );
    _notes.add(note);
    await _save();
    return note;
  }

  @override
  Future<Note> updateNote(Note note, {List<List<int>> addPhotos = const [], List<NewAudio> addAudio = const []}) async {
    _requireMe();
    final added = <String>[];
    for (final b in addPhotos) {
      added.add(await _savePhoto(b));
    }
    final addedAudio = await _saveAudio(addAudio);
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i < 0) throw RepoException('This observation no longer exists.');
    final updated = note.copyWith(
      photos: [...note.photos, ...added],
      audio: [...note.audio, ...addedAudio],
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
  Future<Reply> addReply(Note note, String text, List<List<int>> photos, {List<NewAudio> audio = const []}) async {
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
      audio: await _saveAudio(audio),
      createdAt: DateTime.now(),
    );
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i < 0) throw RepoException('This observation no longer exists.');
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

  String _filePath(String ref) => p.join(_photosDir, ref.startsWith('file:') ? ref.substring(5) : ref);

  @override
  Future<ImageProvider> image(String ref) async => FileImage(File(_filePath(ref)));

  @override
  Future<Uri> audioUri(String ref) async => Uri.file(_filePath(ref));

  /// Adds a few example observations (no photos) so the screens can be tried out.
  Future<void> addSampleNotes(String projectId) async {
    final me = _requireMe();
    final now = DateTime.now();
    DateTime ago(int days, int hour) {
      final d = now.subtract(Duration(days: days));
      return DateTime(d.year, d.month, d.day, hour, 10);
    }

    Note n(String name, String cat, Priority pr, NoteStatus st, int days, String comment,
        {bool mine = false, ObsType type = ObsType.fieldObservation, String location = '', int? dueInDays}) {
      final created = ago(days, 9 + days % 6);
      final (num, code) = _nextNumber(projectId, cat);
      return Note(
        obsType: type,
        location: location,
        dueAt: dueInDays == null ? null : endOfDay(now.add(Duration(days: dueInDays))),
        number: num,
        code: code,
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

    final samples = [
      (
        'Fire damper missing at corridor 3B', 'MEP', Priority.urgent, NoteStatus.open, 0,
        'Fire damper is missing at the rated corridor wall above the ceiling grid. Please install before close-in.',
        ObsType.constructionIssue, 'Level 3, corridor 3B', 2, false,
      ),
      (
        'Open edge at Level 4 east slab, no guardrail', 'Safety', Priority.urgent, NoteStatus.inProgress, 1,
        'Guardrail removed for the hoist and not put back. Stay clear until restored.',
        ObsType.safetyConcern, 'Level 4, east slab edge', -1, false,
      ),
      (
        'Beam B-12 connection missing bolts', 'Steel', Priority.critical, NoteStatus.pendingVerification, 4,
        'Two bolts missing at the shear tab. Complete and re-inspect before decking.',
        ObsType.constructionIssue, 'Grid C/12, Level 2', 1, true,
      ),
      (
        'Duct clashes with sprinkler main, Room 214', 'MEP', Priority.high, NoteStatus.open, 5,
        'Supply duct runs into the sprinkler main. Coordinate a reroute and update the model.',
        ObsType.coordinationRequest, 'Room 214', -3, false,
      ),
      (
        'Honeycombing on column C-7', 'Structure', Priority.high, NoteStatus.onHold, 6,
        'On hold until the engineer of record reviews the repair method.',
        ObsType.fieldObservation, 'Column C-7, Level 1', null, false,
      ),
      (
        'Debris blocking stair 2 landing', 'Safety', Priority.low, NoteStatus.resolved, 7,
        'Housekeeping needed at the stair 2 landing on Level 3.',
        ObsType.followUp, 'Stair 2, Level 3', null, false,
      ),
      (
        'Curtain wall anchor spacing', 'Architecture', Priority.medium, NoteStatus.onHold, 19,
        'Spacing looks wider than the shop drawings. Waiting on the facade consultant.',
        ObsType.coordinationRequest, 'North elevation', 10, false,
      ),
    ];
    for (final x in samples) {
      _notes.add(n(x.$1, x.$2, x.$3, x.$4, x.$5, x.$6, type: x.$7, location: x.$8, dueInDays: x.$9, mine: x.$10));
    }
    await _save();
  }

  @override
  void dispose() => _changes.close();
}
