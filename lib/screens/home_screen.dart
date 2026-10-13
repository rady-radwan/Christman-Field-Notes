import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import 'admin_screen.dart';
import 'note_detail.dart';
import 'note_form_screen.dart';
import 'settings_screen.dart';
import 'sign_in_screen.dart';
import 'tabs.dart';

/// Wide windows get the three-panel Windows layout; narrow ones the phone layout.
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

void _openNote(BuildContext context, Note n, {required bool wide}) {
  final state = context.read<AppState>();
  if (wide) {
    state.selectNote(n.id);
  } else {
    state.markSeen(n.id);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteDetailScreen(noteId: n.id)));
  }
}

Future<void> _newNote(BuildContext context, {required bool wide}) async {
  if (!await requireSignIn(context, 'add a note')) return;
  if (!context.mounted) return;
  final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const NoteFormScreen()));
  if (id != null && wide && context.mounted) context.read<AppState>().selectNote(id);
}

void _openSettings(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

// ------------------------------------------------------------------ shared header pieces

class ProjectSwitcher extends StatelessWidget {
  const ProjectSwitcher({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final name = state.project?.name ?? 'No project';
    return PopupMenuButton<Object>(
      tooltip: 'Switch project',
      onSelected: (v) {
        if (v is Project) {
          state.selectProject(v);
        } else if (v == 'manage') {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminScreen()));
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
            ]),
          ),
        if (state.isAdmin) ...[
          const PopupMenuDivider(),
          const PopupMenuItem<Object>(value: 'manage', child: Text('Manage projects…')),
        ],
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.pill,
          border: Border.all(color: c.line2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 170 : 320),
            child: Text(compact ? name : 'Project: $name',
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 18),
        ]),
      ),
    );
  }
}

class BellButton extends StatelessWidget {
  const BellButton({super.key, required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final unread = state.unreadNotes;
    return IconButton(
      tooltip: unread.isEmpty ? 'Notifications' : 'Notifications, ${unread.length} new',
      onPressed: () => _showUnread(context),
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      icon: Badge(
        isLabelVisible: unread.isNotEmpty,
        label: Text('${unread.length}'),
        backgroundColor: c.accent,
        textColor: c.accentInk,
        child: Icon(Icons.notifications_outlined, color: c.ink),
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
        return AlertDialog(
          title: const Text('New activity'),
          content: SizedBox(
            width: 440,
            child: list.isEmpty
                ? Text('You are all caught up.', style: TextStyle(color: c.muted))
                : ListView(shrinkWrap: true, children: [
                    for (final n in list)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: PriorityBadge(n.priority),
                        title: Text(n.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          n.replies.isEmpty
                              ? 'New note from ${state.nameOf(n.issuerId)} · ${dayText(n.createdAt)}'
                              : 'Reply from ${state.nameOf(n.replies.last.authorId)} · ${dayTimeText(n.replies.last.createdAt)}',
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
    return Material(
      color: c.statusBg(NoteStatus.suspended),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: c.statusFg(NoteStatus.suspended)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(color: c.statusFg(NoteStatus.suspended), fontWeight: FontWeight.w600)),
          ),
          TextButton(onPressed: () => state.reload(quiet: true), child: const Text('Try again')),
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
      _ => OpenNotesView(onOpen: open),
    };
    return Scaffold(
      body: Column(children: [
        Container(
          decoration: BoxDecoration(color: c.head, border: Border(bottom: BorderSide(color: c.headLine))),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              child: Column(children: [
                Row(children: [
                  const BrandLogo(height: 20),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Search',
                    onPressed: () => setState(() {
                      _searching = !_searching;
                      if (!_searching) state.setSearch('');
                    }),
                    icon: Icon(_searching ? Icons.search_off : Icons.search, color: c.ink),
                  ),
                  const ThemeToggleButton(),
                  if (state.isGuest) ...[
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: () => _openSettings(context),
                      icon: Icon(Icons.settings_outlined, color: c.ink),
                    ),
                    const SizedBox(width: 4),
                    const SignInButton(),
                    const SizedBox(width: 4),
                  ] else ...[
                    const BellButton(wide: false),
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: () => _openSettings(context),
                      icon: Avatar(name: state.me?.name ?? '?', size: 30),
                    ),
                  ],
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Text('Field Notes', style: condensed(27)),
                  const Spacer(),
                  const Padding(padding: EdgeInsets.only(right: 8), child: ProjectSwitcher(compact: true)),
                ]),
                if (_searching) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextField(
                      autofocus: true,
                      onChanged: state.setSearch,
                      decoration: const InputDecoration(
                        hintText: 'Search notes',
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
        const _ConnectionBanner(),
        const PendingBanner(),
        Expanded(child: body),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newNote(context, wide: false),
        backgroundColor: c.accent,
        foregroundColor: c.accentInk,
        icon: const Icon(Icons.add),
        label: const Text('New note', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: state.tab,
        onDestinationSelected: state.setTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.view_agenda_outlined), label: 'Open notes'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'By date'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: 'By category'),
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
    final (title, list) = switch (state.tab) {
      1 => ('By date', ByDateView(onOpen: open, selectedId: selected, bottomPadding: 24)),
      2 => ('By category', ByCategoryView(onOpen: open, selectedId: selected, bottomPadding: 24)),
      _ => ('Open notes', OpenNotesView(onOpen: open, selectedId: selected, bottomPadding: 24)),
    };

    Widget navItem(int i, String label, IconData icon, String count) {
      final on = state.tab == i;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: on ? c.selBg : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => state.setTab(i),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                Icon(icon, size: 20, color: on ? c.selFg : c.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: on ? c.selFg : c.ink)),
                ),
                Text(count, style: TextStyle(fontSize: 13, color: on ? c.selFg : c.muted)),
              ]),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(children: [
        Container(
          decoration: BoxDecoration(color: c.head, border: Border(bottom: BorderSide(color: c.headLine))),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Row(children: [
            const BrandLogo(height: 22),
            const SizedBox(width: 14),
            Container(width: 1, height: 26, color: c.line2),
            const SizedBox(width: 14),
            Text('Field Notes', style: condensed(26)),
            const SizedBox(width: 20),
            const ProjectSwitcher(),
            const SizedBox(width: 16),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: TextField(
                    onChanged: state.setSearch,
                    decoration: InputDecoration(
                      hintText: 'Search notes',
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
              IconButton(
                tooltip: 'Settings',
                onPressed: () => _openSettings(context),
                icon: Icon(Icons.settings_outlined, color: c.ink),
              ),
              const SizedBox(width: 8),
              const SignInButton(),
            ] else ...[
            const BellButton(wide: true),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => _openSettings(context),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(children: [
                  Text('${state.me?.name ?? ''}${state.isAdmin ? ' · Admin' : ''}', style: TextStyle(color: c.muted)),
                  const SizedBox(width: 10),
                  Avatar(name: state.me?.name ?? '?', size: 36),
                ]),
              ),
            ),
            ],
          ]),
        ),
        const _ConnectionBanner(),
        const PendingBanner(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 230,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FilledButton.icon(
                    onPressed: () => _newNote(context, wide: true),
                    icon: const Icon(Icons.add),
                    label: const Text('New note'),
                  ),
                  const SizedBox(height: 16),
                  navItem(0, 'Open notes', Icons.view_agenda_outlined,
                      '${state.count((n) => !n.status.isClosed)}'),
                  navItem(1, 'By date', Icons.calendar_month_outlined, '${state.notes.length}'),
                  navItem(2, 'By category', Icons.grid_view_outlined, '${state.project?.categories.length ?? 0}'),
                  const Spacer(),
                  if (state.isAdmin)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminScreen())),
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: Text(
                        state.users.any((u) => u.status == MemberStatus.pending)
                            ? 'Admin (${state.users.where((u) => u.status == MemberStatus.pending).length} waiting)'
                            : 'Admin',
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _openSettings(context),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Settings'),
                  ),
                ]),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 4,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(left: 16), child: Text(title, style: condensed(28))),
                  Expanded(child: list),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: Container(
                  decoration: BoxDecoration(
                    color: c.bg,
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: selected == null || state.noteById(selected) == null
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.touch_app_outlined, size: 40, color: c.muted),
                            const SizedBox(height: 10),
                            Text('Select a note to see its photos and replies.', style: TextStyle(color: c.muted)),
                          ]),
                        )
                      : NoteDetailView(key: ValueKey(selected), noteId: selected, embedded: true),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ no project yet

class _NoProject extends StatefulWidget {
  const _NoProject({required this.wide});
  final bool wide;
  @override
  State<_NoProject> createState() => _NoProjectState();
}

class _NoProjectState extends State<_NoProject> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

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
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(state.isAdmin ? 'Create your first project' : 'No project yet',
                  textAlign: TextAlign.center, style: condensed(30)),
              const SizedBox(height: 10),
              Text(
                state.isAdmin
                    ? 'Notes are organized by project. Each project has its own team and categories.'
                    : state.isGuest
                        ? 'Nothing has been shared yet. Sign in or request access to get started. '
                            'The first account on a new server becomes the admin.'
                        : 'An admin needs to create a project first.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted, height: 1.4),
              ),
              const SizedBox(height: 20),
              if (state.isAdmin) ...[
                TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'e.g. Newcastle Medical Center'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (_name.text.trim().isEmpty) return;
                          setState(() => _busy = true);
                          try {
                            await state.createProject(_name.text);
                          } catch (e) {
                            if (context.mounted) showError(context, e);
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  child: const Text('Create project'),
                ),
              ] else if (state.isGuest)
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
