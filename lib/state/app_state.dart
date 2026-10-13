import 'dart:async';

import 'package:flutter/material.dart';

import '../data/local_repo.dart';
import '../data/repo.dart';
import '../models.dart';
import 'settings.dart';

/// Single source of truth for the UI.
class AppState extends ChangeNotifier {
  AppState(this.repo, this.settings) : themeMode = settings.themeMode;

  final Repo repo;
  final Settings settings;
  StreamSubscription<void>? _sub;
  Timer? _debounce;

  bool booting = true;
  bool busy = false;
  String? connectionError;

  /// Shown when the saved server could not be reached at start-up.
  String? startupWarning;

  AppUser? me;
  List<AppUser> users = [];
  List<Project> projects = [];
  Map<String, Set<String>> members = {};
  Project? project;
  List<Note> notes = [];
  Map<String, DateTime> _seen = {};

  ThemeMode themeMode;

  // ---- Filters (kept while switching tabs) ----
  int tab = 0; // 0 open, 1 by date, 2 by category
  Set<String> openCategories = {};
  bool onlyMine = false;
  String? categoryTab;
  bool showClosed = true;
  String search = '';
  String? selectedNoteId; // desktop layout

  // ---------------------------------------------------------------- lifecycle

  Future<void> init() async {
    _sub = repo.changes.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () => reload(quiet: true));
    });
    try {
      me = await repo.restoreSession();
      if (me != null) _seen = settings.seen(me!.id);
      // Everyone can look around, signed in or not.
      await reload(quiet: true);
    } on RepoException catch (e) {
      connectionError = e.message;
    }
    booting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    repo.dispose();
    super.dispose();
  }

  Future<void> _afterSignIn() async {
    _seen = settings.seen(me!.id);
    await reload();
  }

  /// Not signed in: can read everything, but not add or change anything.
  bool get isGuest => me == null;

  /// Signed in but still waiting for an admin.
  bool get isPending => me != null && !me!.isApproved;

  /// Signed in and approved: may add notes, reply and so on.
  bool get canContribute => me != null && me!.isApproved;

  /// Reloads everything visible to the current user.
  Future<void> reload({bool quiet = false}) async {
    try {
      if (me != null) me = await repo.refreshMe() ?? me;
      users = await repo.users();
      projects = await repo.projects();
      members = await repo.projectMembers();
      project = _pickProject();
      notes = project == null ? [] : await repo.notes(project!.id);
      if (project != null && (categoryTab == null || !project!.categories.contains(categoryTab))) {
        categoryTab = project!.categories.isEmpty ? null : project!.categories.first;
      }
      connectionError = null;
    } on RepoException catch (e) {
      connectionError = e.message;
      if (!quiet) rethrow;
    } finally {
      notifyListeners();
    }
  }

  Project? _pickProject() {
    if (projects.isEmpty) return null;
    final wanted = project?.id ?? settings.lastProjectId;
    return projects.firstWhere((p) => p.id == wanted, orElse: () => projects.first);
  }

  // ---------------------------------------------------------------- accounts

  Future<void> signIn(String email, String password) async {
    me = await repo.signIn(email: email, password: password);
    await _afterSignIn();
    notifyListeners();
  }

  Future<void> register(String name, String email, String password) async {
    me = await repo.register(name: name, email: email, password: password);
    await _afterSignIn();
    notifyListeners();
  }

  bool get usesEmailCodes => repo.usesEmailCodes;

  Future<void> sendCode(String email) => repo.sendCode(email);

  Future<void> verifyCode(String email, String code) async {
    me = await repo.verifyCode(email, code);
    await _afterSignIn();
    notifyListeners();
  }

  /// New accounts start with the part of the email before "@" as their name.
  bool get needsName {
    final m = me;
    if (m == null) return false;
    return m.name.trim().isEmpty || m.name.trim().toLowerCase() == m.email.split('@').first.toLowerCase();
  }

  Future<void> updateMyName(String name) async {
    me = await repo.updateMyName(name);
    notifyListeners();
    await reload(quiet: true);
  }

  Future<void> signOut() async {
    await repo.signOut();
    me = null;
    _seen = {};
    selectedNoteId = null;
    notifyListeners();
    await reload(quiet: true);
  }

  // ---------------------------------------------------------------- settings

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    await settings.setThemeMode(m);
  }

  /// Light <-> dark switch in the header. Starts from what is on screen now.
  Future<void> toggleTheme(Brightness current) =>
      setThemeMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);

  Future<void> selectProject(Project p) async {
    project = p;
    selectedNoteId = null;
    openCategories = {};
    categoryTab = p.categories.isEmpty ? null : p.categories.first;
    await settings.setLastProjectId(p.id);
    notifyListeners();
    await reload();
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  void toggleOpenCategory(String? c) {
    if (c == null) {
      openCategories = {};
    } else if (!openCategories.remove(c)) {
      openCategories = {...openCategories, c};
    } else {
      openCategories = {...openCategories};
    }
    notifyListeners();
  }

  void setOnlyMine(bool v) {
    onlyMine = v;
    notifyListeners();
  }

  void setCategoryTab(String c) {
    categoryTab = c;
    notifyListeners();
  }

  void setShowClosed(bool v) {
    showClosed = v;
    notifyListeners();
  }

  void setSearch(String s) {
    search = s;
    notifyListeners();
  }

  void selectNote(String? id) {
    selectedNoteId = id;
    if (id != null) markSeen(id);
    notifyListeners();
  }

  // ---------------------------------------------------------------- lookups

  AppUser? userById(String id) {
    for (final u in users) {
      if (u.id == id) return u;
    }
    if (me?.id == id) return me;
    return null;
  }

  String nameOf(String id) => userById(id)?.name ?? 'Former member';

  String assignedText(Note n) => n.isGeneral ? 'Everyone' : n.assignedIds.map(nameOf).join(', ');

  Note? noteById(String? id) {
    if (id == null) return null;
    for (final n in notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// Approved users who belong to the current project (for "Assign to").
  List<AppUser> get projectPeople {
    final ids = members[project?.id] ?? {};
    return users.where((u) => u.isApproved && (ids.contains(u.id) || u.isAdmin)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  bool _matchesSearch(Note n) {
    final q = search.trim().toLowerCase();
    if (q.isEmpty) return true;
    return n.name.toLowerCase().contains(q) ||
        n.comment.toLowerCase().contains(q) ||
        n.category.toLowerCase().contains(q) ||
        nameOf(n.issuerId).toLowerCase().contains(q);
  }

  bool isAssignedToMe(Note n) => me != null && n.assignedIds.contains(me!.id);

  static int byPriorityThenDate(Note a, Note b) {
    final p = a.priority.index.compareTo(b.priority.index);
    if (p != 0) return p;
    final d = b.createdAt.compareTo(a.createdAt);
    if (d != 0) return d;
    return b.lastActivity.compareTo(a.lastActivity);
  }

  /// Tab 1: Active and Suspended, filtered, by priority then date then activity.
  List<Note> get openNotes {
    final list = notes.where((n) {
      if (n.status.isClosed) return false;
      if (openCategories.isNotEmpty && !openCategories.contains(n.category)) return false;
      if (onlyMine && !isAssignedToMe(n)) return false;
      return _matchesSearch(n);
    }).toList()
      ..sort(byPriorityThenDate);
    return list;
  }

  /// Tab 2: every note, newest first.
  List<Note> get notesByDate => notes.where(_matchesSearch).toList()
    ..sort((a, b) {
      final d = b.createdAt.compareTo(a.createdAt);
      return d != 0 ? d : a.priority.index.compareTo(b.priority.index);
    });

  /// Tab 3: full history of one category, open notes first.
  List<Note> get categoryNotes => notes
      .where((n) => n.category == categoryTab && (showClosed || !n.status.isClosed) && _matchesSearch(n))
      .toList()
    ..sort((a, b) {
      final c = (a.status.isClosed ? 1 : 0) - (b.status.isClosed ? 1 : 0);
      return c != 0 ? c : byPriorityThenDate(a, b);
    });

  int count(bool Function(Note) test) => notes.where(test).length;

  // ---------------------------------------------------------------- permissions

  bool get isAdmin => me?.isAdmin ?? false;
  bool isIssuer(Note n) => n.issuerId == me?.id;
  bool canChangeStatus(Note n) => isAdmin || isIssuer(n);
  bool canChangePriority(Note n) => isAdmin || isIssuer(n);
  bool canDeactivate(Note n) => isAdmin;
  bool canEdit(Note n) => isAdmin || isIssuer(n);
  bool canDelete(Note n) => isAdmin || (isIssuer(n) && n.replies.isEmpty);
  bool canDeleteReply(Reply r) => isAdmin || r.authorId == me?.id;

  // ---------------------------------------------------------------- notifications (bell)

  /// Notes with activity I have not opened yet that involve me:
  /// assigned to me, issued by me, general notes, or notes I replied to.
  List<Note> get unreadNotes {
    if (me == null) return [];
    final myId = me!.id;
    final list = notes.where((n) {
      final involved =
          n.isGeneral || n.assignedIds.contains(myId) || n.issuerId == myId || n.replies.any((r) => r.authorId == myId);
      if (!involved) return false;
      final lastByOthers = _lastActivityByOthers(n, myId);
      if (lastByOthers == null) return false;
      final seenAt = _seen[n.id];
      return seenAt == null || lastByOthers.isAfter(seenAt);
    }).toList()
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return list;
  }

  DateTime? _lastActivityByOthers(Note n, String myId) {
    DateTime? last = n.issuerId == myId ? null : n.createdAt;
    for (final r in n.replies) {
      if (r.authorId != myId && (last == null || r.createdAt.isAfter(last))) last = r.createdAt;
    }
    return last;
  }

  void markSeen(String noteId) {
    if (me == null) return;
    _seen[noteId] = DateTime.now();
    settings.setSeen(me!.id, _seen);
  }

  void markAllSeen() {
    for (final n in notes) {
      _seen[n.id] = DateTime.now();
    }
    if (me != null) settings.setSeen(me!.id, _seen);
    notifyListeners();
  }

  // ---------------------------------------------------------------- note actions

  Future<T> _run<T>(Future<T> Function() f) async {
    if (!canContribute) {
      throw RepoException(isPending ? 'Your account is waiting for admin approval.' : 'Please sign in first.');
    }
    busy = true;
    notifyListeners();
    try {
      return await f();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<Note> createNote(NoteDraft d) => _run(() async {
        final n = await repo.createNote(project!.id, d);
        notes = [...notes, n];
        markSeen(n.id);
        return n;
      });

  Future<void> _replace(Note n) async {
    notes = [for (final x in notes) x.id == n.id ? n : x];
  }

  Future<void> setStatus(Note n, NoteStatus s) => _run(() async {
        if (s == NoteStatus.deactivated && !canDeactivate(n)) {
          throw RepoException('Only an admin can deactivate a note.');
        }
        await _replace(await repo.updateNote(n.copyWith(status: s)));
      });

  Future<void> setPriority(Note n, Priority p) => _run(() async {
        await _replace(await repo.updateNote(n.copyWith(priority: p)));
      });

  Future<void> saveEdits(Note edited, {List<List<int>> addPhotos = const []}) => _run(() async {
        await _replace(await repo.updateNote(edited.copyWith(editedAt: DateTime.now()), addPhotos: addPhotos));
      });

  Future<void> deleteNote(Note n) => _run(() async {
        await repo.deleteNote(n);
        notes = notes.where((x) => x.id != n.id).toList();
        if (selectedNoteId == n.id) selectedNoteId = null;
      });

  Future<void> addReply(Note n, String text, List<List<int>> photos) => _run(() async {
        final r = await repo.addReply(n, text, photos);
        final current = noteById(n.id) ?? n;
        await _replace(current.copyWith(replies: [...current.replies, r]));
        markSeen(n.id);
      });

  Future<void> deleteReply(Reply r) => _run(() async {
        await repo.deleteReply(r);
        final n = noteById(r.noteId);
        if (n != null) await _replace(n.copyWith(replies: n.replies.where((x) => x.id != r.id).toList()));
      });

  // ---------------------------------------------------------------- admin actions

  Future<void> updateUser(AppUser u) => _run(() async {
        await repo.updateUser(u);
        await reload();
      });

  Future<void> setMember(String projectId, String userId, bool member) => _run(() async {
        await repo.setProjectMember(projectId, userId, member);
        members = await repo.projectMembers();
      });

  Future<void> createProject(String name) => _run(() async {
        final p = await repo.createProject(name);
        await reload();
        await selectProject(projects.firstWhere((x) => x.id == p.id, orElse: () => p));
      });

  Future<void> saveProject(Project p) => _run(() async {
        await repo.updateProject(p);
        await reload();
      });

  bool get canAddSamples => repo is LocalRepo && project != null;

  Future<void> addSampleNotes() => _run(() async {
        final r = repo;
        if (r is LocalRepo && project != null) {
          await r.addSampleNotes(project!.id);
          await reload();
        }
      });
}
