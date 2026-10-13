import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin'),
          bottom: TabBar(
            labelColor: c.accentText,
            unselectedLabelColor: c.muted,
            indicatorColor: c.accent,
            labelStyle: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 15),
            tabs: const [Tab(text: 'People'), Tab(text: 'Projects and categories')],
          ),
        ),
        body: const TabBarView(children: [_PeopleTab(), _ProjectsTab()]),
      ),
    );
  }
}

Future<void> _act(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _PeopleTab extends StatelessWidget {
  const _PeopleTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final pending = state.users.where((u) => u.status == MemberStatus.pending).toList();
    final approved = state.users.where((u) => u.status == MemberStatus.approved).toList();
    final removed = state.users.where((u) => u.status == MemberStatus.removed).toList();

    Widget box(Widget child) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SectionLabel('Waiting for approval (${pending.length})'),
          const SizedBox(height: 10),
          if (pending.isEmpty) Text('No requests right now.', style: TextStyle(color: c.muted)),
          for (final u in pending)
            box(Row(children: [
              Avatar(name: u.name),
              const SizedBox(width: 12),
              Expanded(child: _NameEmail(u)),
              TextButton(
                onPressed: () => _act(context, () => state.updateUser(u.copyWith(status: MemberStatus.removed))),
                child: const Text('Decline'),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: () => _act(context, () async {
                  await state.updateUser(u.copyWith(status: MemberStatus.approved));
                  if (state.project != null) await state.setMember(state.project!.id, u.id, true);
                }),
                child: Text(state.project == null ? 'Approve' : 'Approve and add to ${state.project!.name}'),
              ),
            ])),
          const SizedBox(height: 18),
          SectionLabel('Team (${approved.length})'),
          const SizedBox(height: 10),
          for (final u in approved)
            box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Avatar(name: u.name),
                const SizedBox(width: 12),
                Expanded(child: _NameEmail(u)),
                if (u.id != state.me?.id) ...[
                  Text('Admin', style: TextStyle(color: c.muted)),
                  Switch(
                    value: u.isAdmin,
                    onChanged: (v) => _act(context, () => state.updateUser(u.copyWith(isAdmin: v))),
                  ),
                  IconButton(
                    tooltip: 'Remove from the app',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () => _act(context, () async {
                      final ok = await confirm(context, 'Remove ${u.name}?',
                          'They will no longer be able to sign in. Their notes and replies stay.',
                          ok: 'Remove', danger: true);
                      if (ok) await state.updateUser(u.copyWith(status: MemberStatus.removed));
                    }),
                  ),
                ] else
                  Text('You · Admin', style: TextStyle(color: c.muted)),
              ]),
              if (state.projects.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final p in state.projects)
                    FnChip(
                      label: p.name,
                      icon: (state.members[p.id] ?? {}).contains(u.id) ? Icons.check : Icons.add,
                      selected: (state.members[p.id] ?? {}).contains(u.id),
                      onTap: () => _act(
                        context,
                        () => state.setMember(p.id, u.id, !(state.members[p.id] ?? {}).contains(u.id)),
                      ),
                    ),
                ]),
              ],
            ])),
          if (removed.isNotEmpty) ...[
            const SizedBox(height: 18),
            SectionLabel('Removed (${removed.length})'),
            const SizedBox(height: 10),
            for (final u in removed)
              box(Row(children: [
                Avatar(name: u.name),
                const SizedBox(width: 12),
                Expanded(child: _NameEmail(u)),
                OutlinedButton(
                  onPressed: () => _act(context, () => state.updateUser(u.copyWith(status: MemberStatus.approved))),
                  child: const Text('Restore'),
                ),
              ])),
          ],
        ]),
      ),
    );
  }
}

class _NameEmail extends StatelessWidget {
  const _NameEmail(this.u);
  final AppUser u;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(u.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        Text(u.email, style: TextStyle(color: FnColors.of(context).muted, fontSize: 13)),
      ]);
}

class _ProjectsTab extends StatelessWidget {
  const _ProjectsTab();

  Future<String?> _ask(BuildContext context, String title, {String initial = '', String hint = ''}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            const Expanded(child: SectionLabel('Projects')),
            FilledButton.icon(
              onPressed: () async {
                final name = await _ask(context, 'New project', hint: 'e.g. Newcastle Medical Center');
                if (name != null && name.trim().isNotEmpty && context.mounted) {
                  await _act(context, () => state.createProject(name));
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('New project'),
            ),
          ]),
          const SizedBox(height: 12),
          if (state.projects.isEmpty) Text('No projects yet.', style: TextStyle(color: c.muted)),
          for (final p in state.projects)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(p.name, style: condensed(22))),
                  Text('${(state.members[p.id] ?? {}).length} members', style: TextStyle(color: c.muted)),
                  IconButton(
                    tooltip: 'Rename project',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final name = await _ask(context, 'Rename project', initial: p.name);
                      if (name != null && name.trim().isNotEmpty && context.mounted) {
                        await _act(context, () => state.saveProject(p.copyWith(name: name.trim())));
                      }
                    },
                  ),
                ]),
                const SizedBox(height: 8),
                Text('Categories', style: TextStyle(fontWeight: FontWeight.w700, color: c.muted)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final cat in p.categories)
                    InputChip(
                      label: Text(cat),
                      onDeleted: () => _act(context, () async {
                        final ok = await confirm(context, 'Remove "$cat"?',
                            'Existing notes keep this category. New notes can no longer use it.',
                            ok: 'Remove');
                        if (ok) {
                          await state.saveProject(p.copyWith(categories: p.categories.where((x) => x != cat).toList()));
                        }
                      }),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Add category'),
                    onPressed: () async {
                      final name = await _ask(context, 'New category', hint: 'e.g. Fire Protection');
                      final v = name?.trim() ?? '';
                      if (v.isNotEmpty && !p.categories.contains(v) && context.mounted) {
                        await _act(context, () => state.saveProject(p.copyWith(categories: [...p.categories, v])));
                      }
                    },
                  ),
                ]),
              ]),
            ),
        ]),
      ),
    );
  }
}
