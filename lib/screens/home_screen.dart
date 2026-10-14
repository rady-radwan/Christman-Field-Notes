import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import 'admin_screen.dart';
import 'dashboard.dart';
import 'note_detail.dart';
import 'note_form_screen.dart';
import 'settings_screen.dart';
import 'sign_in_screen.dart';
import 'tabs.dart';
import 'team.dart';

/// Wide windows get the Windows layout (sidebar, list, details); narrow ones the phone layout.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1100;
      if (state.project == null) return _NoProject(wide: wide);
      return wide ? const _DesktopHome() : const _PhoneHome();
    });
  }
}

const _tabTitles = ['Open Observations', 'By Date', 'By Category', 'Dashboard'];

void _openNote(BuildContext context, Note n, {required bool wide}) {
  final state = context.read<AppState>();
  if (wide) {
    if (state.tab == 3) state.setTab(0);
    state.selectNote(n.id);
  } else {
    state.markSeen(n.id);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteDetailScreen(noteId: n.id)));
  }
}

Future<void> _newNote(BuildContext context, {required bool wide}) async {
  if (!await requireSignIn(context, 'report an observation')) return;
  if (!context.mounted) return;
  final state = context.read<AppState>();
  if (state.project != null && !state.isMemberOf(state.project!.id)) {
    showInfo(context, 'You are not on the ${state.project!.name} team. Ask the admin to add you.');
    return;
  }
  final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const NoteFormScreen()));
  if (id != null && wide && context.mounted) {
    if (state.tab == 3) state.setTab(0);
    state.selectNote(id);
  }
}

void _openSettings(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

void _openAdmin(BuildContext context, {int tab = 0}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminScreen(initialTab: tab)));

// ------------------------------------------------------------------ shared header pieces

class ProjectSwitcher extends StatelessWidget {
  const ProjectSwitcher({super.key, this.compact = false, this.onSidebar = false});
  final bool compact;
  final bool onSidebar;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final name = state.project?.name ?? 'No project';
    final ink = onSidebar ? c.sideInk : c.ink;
    return PopupMenuButton<Object>(
      tooltip: 'Switch project',
      onSelected: (v) {
        if (v is Project) {
          state.selectProject(v);
        } else if (v == 'manage') {
          _openAdmin(context, tab: 1);
        } else if (v == 'new') {
          showNewProjectDialog(context);
        }
      },
      itemBuilder: (_) => [
        for (final p in state.projects)
          PopupMenuItem<Object>(
            value: p,
            child: Row(children: [
              Icon(p.id == state.project?.id ? Icons.check : null, size: 18, color: c.accentText),
              const SizedBox(width: 8),
              Text(p.name),
              const SizedBox(width: 8),
              Text(p.code, style: TextStyle(color: c.muted, fontSize: 12)),
            ]),
          ),
        if (state.isAdmin) ...[
          const PopupMenuDivider(),
          const PopupMenuItem<Object>(value: 'new', child: Text('New project…')),
          const PopupMenuItem<Object>(value: 'manage', child: Text('Manage projects…')),
        ],
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: onSidebar ? Colors.white.withValues(alpha: 0.06) : c.pill,
          border: Border.all(color: onSidebar ? c.sideLine : c.line2),
          borderRadius: BorderRadius.circular(onSidebar ? 10 : 20),
        ),
        child: Row(mainAxisSize: onSidebar ? MainAxisSize.max : MainAxisSize.min, children: [
          if (onSidebar) ...[
            Icon(Icons.apartment_rounded, size: 18, color: c.sideMuted),
            const SizedBox(width: 8),
          ],
          Flexible(
            fit: onSidebar ? FlexFit.tight : FlexFit.loose,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compact ? 170 : 320),
              child: Text(name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink)),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.expand_more, size: 18, color: ink),
        ]),
      ),
    );
  }
}

class BellButton extends StatelessWidget {
  const BellButton({super.key, required this.wide, this.iconColor});
  final bool wide;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final unread = state.unreadNotes;
    final overdue = unread.where(state.isOverdueForMe).length;
    return IconButton(
      tooltip: unread.isEmpty
          ? 'Notifications'
          : 'Notifications, ${unread.length} new${overdue > 0 ? ' ($overdue overdue)' : ''}',
      onPressed: () => _showUnread(context),
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      icon: Badge(
        isLabelVisible: unread.isNotEmpty,
        label: Text('${unread.length}'),
        backgroundColor: overdue > 0 ? c.urgentText : c.accent,
        textColor: overdue > 0 ? Colors.white : c.accentInk,
        child: Icon(Icons.notifications_outlined, color: iconColor ?? c.ink),
      ),
    );
  }

  void _showUnread(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final state = ctx.watch<AppState>();
        final c = FnColors.of(ctx);
        final list = state.unreadNotes;
        String why(Note n) {
          if (state.isOverdueForMe(n)) {
            return '${overdueText(n.dueAt!)} · ${n.issuerId == state.me?.id ? 'you reported it' : 'assigned to you'}';
          }
          return n.replies.isEmpty || n.replies.last.authorId == state.me?.id
              ? 'New observation from ${state.nameOf(n.issuerId)} · ${dayText(n.createdAt)}'
              : 'Discussion: ${state.nameOf(n.replies.last.authorId)} · ${dayTimeText(n.replies.last.createdAt)}';
        }

        return AlertDialog(
          title: const Text('New activity'),
          content: SizedBox(
            width: 480,
            child: list.isEmpty
                ? Text('You are all caught up.', style: TextStyle(color: c.muted))
                : ListView(shrinkWrap: true, children: [
                    for (final n in list)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: PriorityBadge(n.priority),
                        title: Text('${n.displayCode} · ${n.name}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          why(n),
                          style: TextStyle(
                            color: state.isOverdueForMe(n) ? c.urgentText : c.muted,
                            fontWeight: state.isOverdueForMe(n) ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _openNote(context, n, wide: wide);
                        },
                      ),
                  ]),
          ),
          actions: [
            if (list.isNotEmpty)
              TextButton(
                onPressed: () {
                  state.markAllSeen();
                  Navigator.pop(ctx);
                },
                child: const Text('Mark all as read'),
              ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        );
      },
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final message = state.connectionError ?? state.startupWarning;
    if (message == null) return const SizedBox.shrink();
    const s = NoteStatus.inProgress;
    return Material(
      color: c.statusBg(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: c.statusFg(s)),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: c.statusFg(s), fontWeight: FontWeight.w600))),
          TextButton(onPressed: () => state.reload(quiet: true), child: const Text('Try again')),
        ]),
      ),
    );
  }
}

/// A short note at the top when the current user is not on the open project's team.
class _NotOnTeamBanner extends StatelessWidget {
  const _NotOnTeamBanner();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final p = state.project;
    if (p == null || !state.canContribute || state.isMemberOf(p.id)) return const SizedBox.shrink();
    return Material(
      color: c.surface2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Icon(Icons.visibility_outlined, size: 18, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text('You can view ${p.name}, but you are not on its team. Ask the admin to add you to report observations.',
                style: TextStyle(color: c.muted)),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ phone layout

class _PhoneHome extends StatefulWidget {
  const _PhoneHome();
  @override
  State<_PhoneHome> createState() => _PhoneHomeState();
}

class _PhoneHomeState extends State<_PhoneHome> {
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    void open(Note n) => _openNote(context, n, wide: false);
    final body = switch (state.tab) {
      1 => ByDateView(onOpen: open),
      2 => ByCategoryView(onOpen: open),
      3 => const DashboardView(bottomPadding: 96),
      _ => OpenNotesView(onOpen: open),
    };
    return Scaffold(
      body: Column(children: [
        Container(
          decoration: BoxDecoration(color: c.side, border: Border(bottom: BorderSide(color: c.sideLine))),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              child: IconTheme(
                data: IconThemeData(color: c.sideInk),
                child: Column(children: [
                  Row(children: [
                    const BrandLogo(height: 20, onDark: true),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Search',
                      onPressed: () => setState(() {
                        _searching = !_searching;
                        if (!_searching) state.setSearch('');
                      }),
                      icon: Icon(_searching ? Icons.search_off : Icons.search, color: c.sideInk),
                    ),
                    IconButton(
                      tooltip: 'Switch light or dark mode',
                      onPressed: () => state.toggleTheme(Theme.of(context).brightness),
                      icon: Icon(c.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: c.sideInk),
                    ),
                    if (state.isGuest) ...[
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: () => _openSettings(context),
                        icon: Icon(Icons.settings_outlined, color: c.sideInk),
                      ),
                      const SizedBox(width: 4),
                      const SignInButton(),
                      const SizedBox(width: 4),
                    ] else ...[
                      BellButton(wide: false, iconColor: c.sideInk),
                      IconButton(
                        tooltip: 'Settings and project team',
                        onPressed: () => _openSettings(context),
                        icon: Avatar(name: state.me?.name ?? '?', size: 30),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Flexible(
                      child: Text(
                        'Field Observations',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: condensed(24, color: c.sideInk),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: ProjectSwitcher(compact: true, onSidebar: true),
                    ),
                  ]),
                  if (_searching) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TextField(
                        autofocus: true,
                        onChanged: state.setSearch,
                        decoration: const InputDecoration(
                          hintText: 'Search observations, numbers, locations',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
        const _ConnectionBanner(),
        const PendingBanner(),
        const _NotOnTeamBanner(),
        Expanded(child: Container(color: c.panel, child: body)),
      ]),
      floatingActionButton: state.tab == 3
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _newNote(context, wide: false),
              backgroundColor: c.accent,
              foregroundColor: c.accentInk,
              icon: const Icon(Icons.add),
              label: const Text('New Observation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: state.tab,
        onDestinationSelected: state.setTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.view_agenda_outlined), label: 'Open'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'By Date'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: 'By Category'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'Dashboard'),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Windows (wide) layout

class _DesktopHome extends StatelessWidget {
  const _DesktopHome();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    void open(Note n) => _openNote(context, n, wide: true);
    final selected = state.selectedNoteId;
    final list = switch (state.tab) {
      1 => ByDateView(onOpen: open, selectedId: selected, bottomPadding: 24),
      2 => ByCategoryView(onOpen: open, selectedId: selected, bottomPadding: 24),
      _ => OpenNotesView(onOpen: open, selectedId: selected, bottomPadding: 24),
    };

    final content = state.tab == 3
        ? Container(
            decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: const DashboardView(),
          )
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 4,
              child: Container(
                decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: list,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: Container(
                decoration: BoxDecoration(
                  color: c.bg,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: selected == null || state.noteById(selected) == null
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.touch_app_outlined, size: 40, color: c.muted),
                          const SizedBox(height: 10),
                          Text('Select an observation to see its details, photos and discussion.',
                              style: TextStyle(color: c.muted)),
                        ]),
                      )
                    : NoteDetailView(key: ValueKey(selected), noteId: selected, embedded: true),
              ),
            ),
          ]);

    return Scaffold(
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _Sidebar(),
        Expanded(
          child: Column(children: [
            Container(
              decoration: BoxDecoration(color: c.head, border: Border(bottom: BorderSide(color: c.headLine))),
              padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
              child: Row(children: [
                Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_tabTitles[state.tab], style: condensed(28)),
                  Text(
                    '${state.project?.name ?? ''} · ${state.project?.code ?? ''}',
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ]),
                const SizedBox(width: 24),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: state.tab == 3
                          ? const SizedBox.shrink()
                          : TextField(
                              onChanged: state.setSearch,
                              decoration: InputDecoration(
                                hintText: 'Search title, number, location, person',
                                prefixIcon: const Icon(Icons.search),
                                isDense: true,
                                fillColor: c.surface2,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const ThemeToggleButton(outlined: true),
                const SizedBox(width: 4),
                if (state.isGuest) ...[
                  const SizedBox(width: 8),
                  const SignInButton(),
                ] else
                  const BellButton(wide: true),
              ]),
            ),
            const _ConnectionBanner(),
            const PendingBanner(),
            const _NotOnTeamBanner(),
            Expanded(child: Padding(padding: const EdgeInsets.all(16), child: content)),
          ]),
        ),
      ]),
    );
  }
}

/// Full-height warm dark sidebar with the logo, project, navigation and account.
class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final waitingPeople = state.users.where((u) => u.status == MemberStatus.pending).length;
    final waiting = waitingPeople + state.pendingInvites.length;

    Widget navItem(int i, String label, IconData icon, String count, {Color? countColor}) {
      final on = state.tab == i;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: on ? c.sideSel.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => state.setTab(i),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: on ? c.sideSel : Colors.transparent, width: 3)),
              ),
              child: Row(children: [
                Icon(icon, size: 20, color: on ? c.sideInk : c.sideMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on ? c.sideInk : c.sideMuted,
                      )),
                ),
                if (count.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: countColor ?? Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(count,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: countColor == null ? c.sideMuted : Colors.white)),
                  ),
              ]),
            ),
          ),
        ),
      );
    }

    Widget sideButton(IconData icon, String label, VoidCallback onTap, {String? badge}) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Icon(icon, size: 19, color: c.sideMuted),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: c.sideMuted, fontWeight: FontWeight.w500))),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(color: c.sideSel, borderRadius: BorderRadius.circular(10)),
                  child: Text(badge, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
            ]),
          ),
        );

    final overdue = state.count((n) => n.isOverdue);
    return Container(
      width: 260,
      color: c.side,
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.only(left: 6),
          child: Align(alignment: Alignment.centerLeft, child: BrandLogo(full: true, height: 34, onDark: true)),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Row(children: [
            Container(width: 22, height: 3, color: c.sideSel),
            const SizedBox(width: 8),
            Text('FIELD OBSERVATIONS', style: condensed(17, color: c.sideInk, letterSpacing: 1.6)),
          ]),
        ),
        const SizedBox(height: 18),
        const ProjectSwitcher(onSidebar: true),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => _newNote(context, wide: true),
          style: FilledButton.styleFrom(backgroundColor: c.sideSel, foregroundColor: Colors.white),
          icon: const Icon(Icons.add),
          label: const Text('New Observation'),
        ),
        const SizedBox(height: 18),
        navItem(0, 'Open Observations', Icons.view_agenda_outlined, '${state.count((n) => !n.status.isClosed)}'),
        navItem(1, 'By Date', Icons.calendar_month_outlined, '${state.notes.length}'),
        navItem(2, 'By Category', Icons.grid_view_outlined, '${state.project?.categories.length ?? 0}'),
        navItem(3, 'Dashboard', Icons.insights_outlined, overdue == 0 ? '' : '$overdue overdue',
            countColor: overdue == 0 ? null : c.urgentText),
        const Spacer(),
        Divider(color: c.sideLine, height: 20),
        if (state.isAdmin)
          sideButton(Icons.admin_panel_settings_outlined, 'Admin', () => _openAdmin(context, tab: waitingPeople == 0 && waiting > 0 ? 2 : 0),
              badge: waiting == 0 ? null : '$waiting'),
        sideButton(Icons.groups_outlined, 'Settings and team', () => _openSettings(context)),
        const SizedBox(height: 6),
        if (!state.isGuest)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openSettings(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Avatar(name: state.me?.name ?? '?', size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(state.me?.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.sideInk, fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(
                      state.isAdmin ? 'Admin' : ((state.me?.company ?? '').isEmpty ? 'Member' : state.me!.company),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.sideMuted, fontSize: 12),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ no project yet

class _NoProject extends StatelessWidget {
  const _NoProject({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const BrandLogo(height: 20),
        actions: [
          const ThemeToggleButton(),
          IconButton(tooltip: 'Settings', onPressed: () => _openSettings(context), icon: const Icon(Icons.settings_outlined)),
          if (state.isGuest) const Padding(padding: EdgeInsets.only(right: 12, left: 4), child: SignInButton()),
        ],
      ),
      bottomNavigationBar: const PendingBanner(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(state.isAdmin ? 'Create your first project' : 'No project to show yet',
                  textAlign: TextAlign.center, style: condensed(30)),
              const SizedBox(height: 10),
              Text(
                state.isAdmin
                    ? 'Observations are organized by project. Each project has its own team, categories and numbering.'
                    : state.isGuest
                        ? 'Projects are visible to their team members. Sign in to see the projects you are on. '
                            'The first account on a new server becomes the admin.'
                        : state.isPending
                            ? 'Your account is waiting for admin approval. You will see your projects once you are approved and added to one.'
                            : 'You are not on any project team yet. Ask the admin (or a project member) to add you.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted, height: 1.4),
              ),
              const SizedBox(height: 20),
              if (state.isAdmin)
                FilledButton.icon(
                  onPressed: () => showNewProjectDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New project'),
                )
              else if (state.isGuest)
                FilledButton.icon(
                  onPressed: () => openSignIn(context),
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in or request access'),
                )
              else
                FilledButton.icon(
                  onPressed: () => state.reload(quiet: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check again'),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
