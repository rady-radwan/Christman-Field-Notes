import 'dart:async';

import 'package:flutter/material.dart';

import '../data/local_repo.dart';
import '../data/repo.dart';
import '../models.dart';
import 'settings.dart';

/// Single source of truth for the UI.
class AppState extends ChangeNotifier {
  AppState(this.repo, this.settings)
      : themeMode = settings.themeMode,
        fontChoice = settings.fontChoice;

  final Repo repo;
  final Settings settings;
  StreamSubscription<void>? _sub;
  StreamSubscription<void>? _signInSub;
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
  List<ProjectInvite> invites = [];
  Map<String, DateTime> _seen = {};

  ThemeMode themeMode;

  /// Font family chosen in Settings ('' = the built-in Barlow).
  String fontChoice;

  // ---- Filters (kept while switching tabs) ----
  int tab = 0; // 0 open, 1 by date, 2 by category, 3 dashboard
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
    _signInSub = repo.signedIn.listen((_) => _onSignedInFromLink());
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

  /// The emailed link opened the app and signed the person in.
  Future<void> _onSignedInFromLink() async {
    try {
      final who = await repo.restoreSession();
      if (who == null) return;
      final changed = me?.id != who.id;
      me = who;
      if (changed) await _afterSignIn();
      notifyListeners();
    } on RepoException catch (e) {
      connectionError = e.message;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _signInSub?.cancel();
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
      invites = await repo.invites();
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

  Future<void> verifyLink(String link) async {
    me = await repo.verifyLink(link);
    await _afterSignIn();
    notifyListeners();
  }

  /// New accounts start with the part of the email before "@" as their name.
  bool get needsName {
    final m = me;
    if (m == null) return false;
    return m.name.trim().isEmpty || m.name.trim().toLowerCase() == m.email.split('@').first.toLowerCase();
  }

  Future<void> updateMyName(String name) => updateMyProfile(name: name, company: me?.company ?? '');

  Future<void> updateMyProfile({required String name, required String company}) async {
    me = await repo.updateMyProfile(name: name, company: company);
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

  Future<void> setFont(String family) async {
    fontChoice = family;
    notifyListeners();
    await settings.setFontChoice(family);
  }

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

  String companyOf(String id) => userById(id)?.company ?? '';

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

  /// The project team: people added to the project (admins are listed separately).
  List<AppUser> teamOf(String projectId) {
    final ids = members[projectId] ?? {};
    return users.where((u) => u.status != MemberStatus.removed && ids.contains(u.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  bool isMemberOf(String projectId) =>
      canContribute && (isAdmin || (members[projectId]?.contains(me!.id) ?? false));

  /// Suggestions for the given project, newest first.
  List<ProjectInvite> invitesFor(String projectId, {bool pendingOnly = false}) =>
      invites.where((i) => i.projectId == projectId && (!pendingOnly || i.isPending)).toList();

  /// Suggestions waiting for an admin, across all projects.
  List<ProjectInvite> get pendingInvites => invites.where((i) => i.isPending).toList();

  Project? projectById(String id) {
    for (final p in projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool _matchesSearch(Note n) {
    final q = search.trim().toLowerCase();
    if (q.isEmpty) return true;
    return n.name.toLowerCase().contains(q) ||
        n.comment.toLowerCase().contains(q) ||
        n.code.toLowerCase().contains(q) ||
        n.location.toLowerCase().contains(q) ||
        n.obsType.label.toLowerCase().contains(q) ||
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

  /// Tab 1: everything not Resolved or Voided, filtered, by priority then date then activity.
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

  // ---------------------------------------------------------------- dashboard

  DashboardData get dashboard => DashboardData.of(notes, project, this);

  // ---------------------------------------------------------------- permissions

  bool get isAdmin => me?.isAdmin ?? false;
  bool isIssuer(Note n) => n.issuerId == me?.id;
  /// Only the admin and the person who reported it change the status.
  bool canChangeStatus(Note n) => canContribute && (isAdmin || isIssuer(n));
  bool canChangePriority(Note n) => canContribute && (isAdmin || isIssuer(n));
  bool canEdit(Note n) => isAdmin || isIssuer(n);
  bool canDelete(Note n) => isAdmin || (isIssuer(n) && n.replies.isEmpty);
  bool canDeleteReply(Reply r) => isAdmin || r.authorId == me?.id;

  // ---------------------------------------------------------------- notifications (bell)

  /// Observations with news I have not opened yet that involve me:
  /// assigned to me, reported by me, general ones, or ones I joined the discussion of.
  /// Overdue observations show up for the reporter and the assigned people until opened.
  List<Note> get unreadNotes {
    if (me == null) return [];
    final myId = me!.id;
    final list = notes.where((n) {
      if (isOverdueForMe(n)) return true;
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

  /// Overdue, I reported it or it is assigned to me, and I have not opened it since it became overdue.
  bool isOverdueForMe(Note n) {
    if (me == null || !n.isOverdue) return false;
    final myId = me!.id;
    if (n.issuerId != myId && !n.assignedIds.contains(myId)) return false;
    final seenAt = _seen[n.id];
    return seenAt == null || seenAt.isBefore(n.dueAt!);
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
        if (!canChangeStatus(n)) {
          throw RepoException('Only the admin and the person who reported it can change the status.');
        }
        await _replace(await repo.updateNote(n.copyWith(status: s)));
      });

  Future<void> setPriority(Note n, Priority p) => _run(() async {
        await _replace(await repo.updateNote(n.copyWith(priority: p)));
      });

  Future<void> saveEdits(Note edited, {List<List<int>> addPhotos = const [], List<NewAudio> addAudio = const []}) =>
      _run(() async {
        await _replace(
            await repo.updateNote(edited.copyWith(editedAt: DateTime.now()), addPhotos: addPhotos, addAudio: addAudio));
      });

  Future<void> deleteNote(Note n) => _run(() async {
        await repo.deleteNote(n);
        notes = notes.where((x) => x.id != n.id).toList();
        if (selectedNoteId == n.id) selectedNoteId = null;
      });

  Future<void> addReply(Note n, String text, List<List<int>> photos, {List<NewAudio> audio = const []}) =>
      _run(() async {
        final r = await repo.addReply(n, text, photos, audio: audio);
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

  Future<void> createProject(Project draft) => _run(() async {
        final p = await repo.createProject(draft);
        await reload();
        await selectProject(projects.firstWhere((x) => x.id == p.id, orElse: () => p));
      });

  Future<void> saveProject(Project p) => _run(() async {
        await repo.updateProject(p);
        await reload();
      });

  Future<void> suggestMember(String projectId, {required String email, required String name, required String company}) =>
      _run(() async {
        await repo.suggestMember(projectId, email: email, name: name, company: company);
        invites = await repo.invites();
      });

  Future<void> approveInvite(ProjectInvite i) => _run(() async {
        await repo.approveInvite(i);
        await reload();
      });

  Future<void> declineInvite(ProjectInvite i) => _run(() async {
        await repo.declineInvite(i);
        invites = await repo.invites();
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

/// Numbers for the Dashboard tab.
class DashboardData {
  DashboardData._();

  int total = 0, open = 0, inProgress = 0, pendingVerification = 0, onHold = 0, resolved = 0, voided = 0;
  int overdue = 0, criticalUrgent = 0;

  /// category -> (open, closed). In the project's category order.
  final Map<String, (int, int)> byCategory = {};

  /// observation type -> count of open ones.
  final Map<ObsType, int> openByType = {};

  /// One row per assigned person (or "Everyone" for general observations).
  final List<AssigneeRow> byAssignee = [];

  static DashboardData of(List<Note> notes, Project? project, AppState state) {
    final d = DashboardData._();
    final now = DateTime.now();
    for (final c in project?.categories ?? const <String>[]) {
      d.byCategory[c] = (0, 0);
    }
    final rows = <String, AssigneeRow>{};
    for (final n in notes) {
      if (n.status == NoteStatus.voided) {
        d.voided++;
        continue; // voided observations are left out of the counts
      }
      d.total++;
      switch (n.status) {
        case NoteStatus.open:
          d.open++;
        case NoteStatus.inProgress:
          d.inProgress++;
        case NoteStatus.pendingVerification:
          d.pendingVerification++;
        case NoteStatus.onHold:
          d.onHold++;
        case NoteStatus.resolved:
          d.resolved++;
        case NoteStatus.voided:
          break;
      }
      final closed = n.status.isClosed;
      final late = n.isOverdueAt(now);
      if (late) d.overdue++;
      if (!closed && (n.priority == Priority.urgent || n.priority == Priority.critical)) d.criticalUrgent++;
      final cat = d.byCategory[n.category] ?? (0, 0);
      d.byCategory[n.category] = closed ? (cat.$1, cat.$2 + 1) : (cat.$1 + 1, cat.$2);
      if (!closed) d.openByType[n.obsType] = (d.openByType[n.obsType] ?? 0) + 1;
      final who = n.isGeneral ? const [''] : n.assignedIds;
      for (final id in who) {
        final row = rows.putIfAbsent(
          id,
          () => AssigneeRow(
            userId: id,
            name: id.isEmpty ? 'Everyone (general)' : state.nameOf(id),
            company: id.isEmpty ? '' : state.companyOf(id),
          ),
        );
        if (!closed) row.open++;
        if (late) row.overdue++;
        if (closed) row.resolved++;
      }
    }
    d.byAssignee
      ..addAll(rows.values)
      ..sort((a, b) {
        final o = b.overdue.compareTo(a.overdue);
        if (o != 0) return o;
        final p = b.open.compareTo(a.open);
        return p != 0 ? p : a.name.compareTo(b.name);
      });
    return d;
  }
}

class AssigneeRow {
  AssigneeRow({required this.userId, required this.name, required this.company});
  final String userId;
  final String name;
  final String company;
  int open = 0, overdue = 0, resolved = 0;
}
