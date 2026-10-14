import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'team.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final state = context.watch<AppState>();
    final waitingPeople = state.users.where((u) => u.status == MemberStatus.pending).length;
    final waitingInvites = state.pendingInvites.length;
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin'),
          bottom: TabBar(
            labelColor: c.accentText,
            unselectedLabelColor: c.muted,
            indicatorColor: c.accent,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            tabs: [
              Tab(text: waitingPeople == 0 ? 'People' : 'People ($waitingPeople waiting)'),
              const Tab(text: 'Projects and categories'),
              Tab(text: waitingInvites == 0 ? 'Member requests' : 'Member requests ($waitingInvites)'),
            ],
          ),
        ),
        body: const TabBarView(children: [_PeopleTab(), _ProjectsTab(), _RequestsTab()]),
      ),
    );
  }
}

Widget _box(BuildContext context, Widget child) {
  final c = FnColors.of(context);
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(12)),
    child: child,
  );
}

Future<void> _editPerson(BuildContext context, AppUser u) async {
  final state = context.read<AppState>();
  final name = TextEditingController(text: u.name);
  final company = TextEditingController(text: u.company);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Edit ${u.name}'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 10),
          TextField(
            controller: company,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Company / trade', hintText: 'e.g. Mechanical Contractor'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await act(context, () => state.updateUser(u.copyWith(name: name.text.trim(), company: company.text.trim())));
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SectionLabel('Waiting for approval (${pending.length})'),
          const SizedBox(height: 10),
          if (pending.isEmpty) Text('No requests right now.', style: TextStyle(color: c.muted)),
          for (final u in pending)
            _box(
              context,
              Row(children: [
                Avatar(name: u.name),
                const SizedBox(width: 12),
                Expanded(child: _NameEmail(u)),
                TextButton(
                  onPressed: () => act(context, () => state.updateUser(u.copyWith(status: MemberStatus.removed))),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: () => act(context, () async {
                    await state.updateUser(u.copyWith(status: MemberStatus.approved));
                    if (state.project != null) await state.setMember(state.project!.id, u.id, true);
                  }),
                  child: Text(state.project == null ? 'Approve' : 'Approve and add to ${state.project!.name}'),
                ),
              ]),
            ),
          const SizedBox(height: 18),
          SectionLabel('Everyone (${approved.length})',
              trailing: Text('Tap a project to add or remove the person', style: TextStyle(fontSize: 12, color: c.muted))),
          const SizedBox(height: 10),
          for (final u in approved)
            _box(
              context,
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Avatar(name: u.name),
                  const SizedBox(width: 12),
                  Expanded(child: _NameEmail(u)),
                  IconButton(
                    tooltip: 'Edit name and company',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editPerson(context, u),
                  ),
                  if (u.id != state.me?.id) ...[
                    Text('Admin', style: TextStyle(color: c.muted)),
                    Switch(
                      value: u.isAdmin,
                      onChanged: (v) => act(context, () => state.updateUser(u.copyWith(isAdmin: v))),
                    ),
                    IconButton(
                      tooltip: 'Remove from the app',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () => act(context, () async {
                        final ok = await confirm(context, 'Remove ${u.name}?',
                            'They will no longer be able to sign in. Their observations and messages stay.',
                            ok: 'Remove', danger: true);
                        if (ok) await state.updateUser(u.copyWith(status: MemberStatus.removed));
                      }),
                    ),
                  ] else
                    Text('You · Admin', style: TextStyle(color: c.muted)),
                ]),
                if (state.projects.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final p in state.projects)
                      FnChip(
                        label: p.name,
                        dense: true,
                        icon: (state.members[p.id] ?? {}).contains(u.id) ? Icons.check : Icons.add,
                        selected: (state.members[p.id] ?? {}).contains(u.id),
                        onTap: () => act(
                          context,
                          () => state.setMember(p.id, u.id, !(state.members[p.id] ?? {}).contains(u.id)),
                        ),
                      ),
                  ]),
                  if (u.isAdmin)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Admins can see every project.', style: TextStyle(fontSize: 12, color: c.muted)),
                    ),
                ],
              ]),
            ),
          if (removed.isNotEmpty) ...[
            const SizedBox(height: 18),
            SectionLabel('Removed (${removed.length})'),
            const SizedBox(height: 10),
            for (final u in removed)
              _box(
                context,
                Row(children: [
                  Avatar(name: u.name),
                  const SizedBox(width: 12),
                  Expanded(child: _NameEmail(u)),
                  OutlinedButton(
                    onPressed: () => act(context, () => state.updateUser(u.copyWith(status: MemberStatus.approved))),
                    child: const Text('Restore'),
                  ),
                ]),
              ),
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
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(u.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      Text(
        [if (u.company.isNotEmpty) u.company, u.email].join(' · '),
        style: TextStyle(color: c.muted, fontSize: 13),
      ),
    ]);
  }
}

class _ProjectsTab extends StatelessWidget {
  const _ProjectsTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            const Expanded(child: SectionLabel('Projects')),
            FilledButton.icon(
              onPressed: () => showNewProjectDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('New project'),
            ),
          ]),
          const SizedBox(height: 12),
          if (state.projects.isEmpty) Text('No projects yet.', style: TextStyle(color: c.muted)),
          for (final p in state.projects)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: c.avatarBg, borderRadius: BorderRadius.circular(6)),
                      child: Text(p.code, style: TextStyle(fontWeight: FontWeight.w800, color: c.avatarInk, letterSpacing: 0.6)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(p.name, style: condensed(22))),
                    if (p.guestVisible)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.public, size: 16, color: c.muted),
                          const SizedBox(width: 4),
                          Text('Guests can view', style: TextStyle(fontSize: 12, color: c.muted)),
                        ]),
                      ),
                    Text('${(state.members[p.id] ?? {}).length} members', style: TextStyle(color: c.muted)),
                    IconButton(
                      tooltip: 'Edit name, abbreviations, categories and guest access',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => showEditProjectDialog(context, p),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final cat in p.categories)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(border: Border.all(color: c.line2), borderRadius: BorderRadius.circular(6)),
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: cat, style: const TextStyle(fontWeight: FontWeight.w600)),
                          TextSpan(text: '  ${p.categoryCode(cat)}', style: TextStyle(color: c.accentText, fontWeight: FontWeight.w700)),
                        ])),
                      ),
                  ]),
                ),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    title: Text('Project team', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink2)),
                    children: [ProjectTeamPanel(projectId: p.id, showTitle: false)],
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final pending = state.pendingInvites;
    final decided = state.invites.where((i) => !i.isPending).take(30).toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SectionLabel('Suggested by project members (${pending.length})'),
          const SizedBox(height: 4),
          Text(
            'Approving adds the person to the project. If they have no account yet, they join it automatically '
            'the first time they sign in with that email, without waiting for approval.',
            style: TextStyle(fontSize: 13, color: c.muted),
          ),
          const SizedBox(height: 10),
          if (pending.isEmpty) Text('Nothing waiting.', style: TextStyle(color: c.muted)),
          for (final i in pending) InviteTile(invite: i),
          if (decided.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionLabel('Recently decided'),
            const SizedBox(height: 10),
            for (final i in decided) InviteTile(invite: i),
          ],
        ]),
      ),
    );
  }
}
