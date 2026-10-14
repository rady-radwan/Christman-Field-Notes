import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../widgets/common.dart';

Future<void> act(BuildContext context, Future<void> Function() f, {String? done}) async {
  try {
    await f();
    if (done != null && context.mounted) showInfo(context, done);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

// ------------------------------------------------------------------ project team table

/// The people on a project, with their company and role.
/// Members can suggest new people; the admin approves, adds or removes them.
class ProjectTeamPanel extends StatelessWidget {
  const ProjectTeamPanel({super.key, required this.projectId, this.showTitle = true});
  final String projectId;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final project = state.projectById(projectId);
    if (project == null) return const SizedBox.shrink();
    final team = state.teamOf(projectId);
    final admins = state.users.where((u) => u.isAdmin && u.isApproved && !team.any((t) => t.id == u.id)).toList();
    final invites = state.invitesFor(projectId);
    final pending = invites.where((i) => i.isPending).toList();
    final canSuggest = state.isMemberOf(projectId);
    final head = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.muted, letterSpacing: 0.6);

    Widget row(AppUser u, {required String role}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
          child: LayoutBuilder(builder: (context, box) {
            final narrow = box.maxWidth < 560;
            final name = Row(children: [
              Avatar(name: u.name, size: 30),
              const SizedBox(width: 10),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u.id == state.me?.id ? '${u.name} (you)' : u.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (narrow)
                    Text(
                      [if (u.company.isNotEmpty) u.company, if (u.email.isNotEmpty) u.email].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                ]),
              ),
            ]);
            final remove = state.isAdmin && role == 'Member'
                ? IconButton(
                    tooltip: 'Remove from this project',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.person_remove_outlined, size: 20, color: c.muted),
                    onPressed: () async {
                      final ok = await confirm(context, 'Remove ${u.name} from ${project.name}?',
                          'They will no longer see this project. Their observations and messages stay.',
                          ok: 'Remove', danger: true);
                      if (ok && context.mounted) await act(context, () => state.setMember(projectId, u.id, false));
                    },
                  )
                : const SizedBox(width: 40);
            final roleText = Text(role, style: TextStyle(color: role == 'Admin' ? c.accentText : c.ink2, fontWeight: FontWeight.w600));
            if (narrow) {
              return Row(children: [Expanded(child: name), roleText, remove]);
            }
            return Row(children: [
              Expanded(flex: 4, child: name),
              Expanded(
                flex: 3,
                child: Text(u.company.isEmpty ? '—' : u.company, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Expanded(
                flex: 4,
                child: Text(u.email.isEmpty ? '—' : u.email,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.muted)),
              ),
              SizedBox(width: 70, child: roleText),
              remove,
            ]);
          }),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showTitle) ...[
        SectionLabel('Project team · ${project.name}'),
        const SizedBox(height: 4),
        Text(
          'Only the people on this list (and admins) can see ${project.name}.',
          style: TextStyle(fontSize: 13, color: c.muted),
        ),
        const SizedBox(height: 10),
      ],
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (canSuggest && !state.isAdmin)
          FilledButton.icon(
            onPressed: () => showSuggestMemberDialog(context, project),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Suggest a member'),
          ),
        if (state.isAdmin) ...[
          FilledButton.icon(
            onPressed: () => showAddMembersDialog(context, project),
            icon: const Icon(Icons.group_add_outlined),
            label: const Text('Add people'),
          ),
          OutlinedButton.icon(
            onPressed: () => showSuggestMemberDialog(context, project),
            icon: const Icon(Icons.mail_outline),
            label: const Text('Invite by email'),
          ),
        ],
      ]),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, box) => box.maxWidth < 560
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(flex: 4, child: Text('NAME', style: head)),
                  Expanded(flex: 3, child: Text('COMPANY / TRADE', style: head)),
                  Expanded(flex: 4, child: Text('EMAIL', style: head)),
                  SizedBox(width: 70, child: Text('ROLE', style: head)),
                  const SizedBox(width: 40),
                ]),
              ),
      ),
      for (final u in admins) row(u, role: 'Admin'),
      for (final u in team) row(u, role: u.isAdmin ? 'Admin' : 'Member'),
      if (team.isEmpty && admins.isEmpty)
        Padding(padding: const EdgeInsets.all(8), child: Text('No one yet.', style: TextStyle(color: c.muted))),
      if (pending.isNotEmpty) ...[
        const SizedBox(height: 18),
        SectionLabel('Waiting for admin approval (${pending.length})'),
        const SizedBox(height: 8),
        for (final i in pending) InviteTile(invite: i, showProject: false),
      ],
    ]);
  }
}

/// One member suggestion. Admins get Approve / Decline buttons.
class InviteTile extends StatelessWidget {
  const InviteTile({super.key, required this.invite, this.showProject = true});
  final ProjectInvite invite;
  final bool showProject;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final project = state.projectById(invite.projectId);
    final by = invite.invitedBy == null ? 'someone' : state.nameOf(invite.invitedBy!);
    final hasAccount = state.users.any((u) => u.email.toLowerCase() == invite.email.toLowerCase());
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Avatar(name: invite.name.isEmpty ? invite.email : invite.name, size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              [if (invite.name.isNotEmpty) invite.name, if (invite.company.isNotEmpty) invite.company].join(' · ').ifEmpty(invite.email),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(invite.email, style: TextStyle(fontSize: 13, color: c.muted)),
            Text(
              'Suggested by $by · ${dayText(invite.createdAt)}'
              '${showProject && project != null ? ' · for ${project.name}' : ''}'
              '${hasAccount ? '' : ' · no account yet'}',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ]),
        ),
        if (state.isAdmin && invite.isPending) ...[
          TextButton(
            onPressed: () => act(context, () => state.declineInvite(invite)),
            child: const Text('Decline'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: () => act(
              context,
              () => state.approveInvite(invite),
              done: hasAccount
                  ? '${invite.name.ifEmpty(invite.email)} was added to ${project?.name ?? 'the project'}.'
                  : 'Approved. ${invite.email} joins ${project?.name ?? 'the project'} automatically on first sign-in.',
            ),
            child: const Text('Approve'),
          ),
        ] else
          Text(invite.isPending ? 'Waiting for admin' : (invite.status == 'approved' ? 'Approved' : 'Declined'),
              style: TextStyle(fontSize: 13, color: c.muted)),
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

// ------------------------------------------------------------------ dialogs

/// A project member suggests someone (by email). An admin approves it in the app.
Future<void> showSuggestMemberDialog(BuildContext context, Project project) async {
  final state = context.read<AppState>();
  final email = TextEditingController();
  final name = TextEditingController();
  final company = TextEditingController();
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(state.isAdmin ? 'Invite to ${project.name}' : 'Suggest a member for ${project.name}'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              state.isAdmin
                  ? 'They are added as soon as you approve below. If they have no account yet, they join the project '
                      'automatically the first time they sign in with this email.'
                  : 'The admin is asked to approve. Once approved, they can sign in with this email and see the project.',
              style: TextStyle(color: FnColors.of(ctx).muted, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Work email', hintText: 'name@company.com'),
            ),
            const SizedBox(height: 10),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: 10),
            TextField(
              controller: company,
              decoration: const InputDecoration(labelText: 'Company / trade', hintText: 'e.g. Mechanical Contractor'),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: TextStyle(color: FnColors.of(ctx).urgentText)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!_emailPattern.hasMatch(email.text.trim())) {
                setState(() => error = 'Enter a valid email address.');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: Text(state.isAdmin ? 'Add invitation' : 'Send for approval'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  await act(
    context,
    () => state.suggestMember(project.id, email: email.text, name: name.text, company: company.text),
    done: state.isAdmin ? 'Invitation added. Approve it in the list.' : 'Sent. The admin will be asked to approve.',
  );
}

/// Admin: pick existing people to add to a project.
Future<void> showAddMembersDialog(BuildContext context, Project project) async {
  final state = context.read<AppState>();
  final current = state.members[project.id] ?? {};
  final candidates = state.users.where((u) => u.isApproved && !current.contains(u.id)).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final picked = <String>{};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Add people to ${project.name}'),
        content: SizedBox(
          width: 460,
          child: candidates.isEmpty
              ? Text('Everyone with an account is already on this project. Use "Invite by email" for new people.',
                  style: TextStyle(color: FnColors.of(ctx).muted))
              : ListView(shrinkWrap: true, children: [
                  for (final u in candidates)
                    CheckboxListTile(
                      value: picked.contains(u.id),
                      onChanged: (v) => setState(() => v == true ? picked.add(u.id) : picked.remove(u.id)),
                      secondary: Avatar(name: u.name, size: 32),
                      title: Text(u.name),
                      subtitle: Text([if (u.company.isNotEmpty) u.company, u.email].join(' · ')),
                    ),
                ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          if (candidates.isNotEmpty)
            FilledButton(
              onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: Text(picked.isEmpty ? 'Add' : 'Add ${picked.length}'),
            ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  await act(context, () async {
    for (final id in picked) {
      await state.setMember(project.id, id, true);
    }
  }, done: 'Added to ${project.name}.');
}

/// Edit my name and company.
Future<void> showEditProfileDialog(BuildContext context) async {
  final state = context.read<AppState>();
  final name = TextEditingController(text: state.me?.name ?? '');
  final company = TextEditingController(text: state.me?.company ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('My details'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 10),
          TextField(
            controller: company,
            decoration: const InputDecoration(labelText: 'Company / trade', hintText: 'e.g. The Christman Company'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok != true || !context.mounted || name.text.trim().isEmpty) return;
  await act(context, () => state.updateMyProfile(name: name.text, company: company.text), done: 'Saved.');
}

/// Admin: new project. Asks for the name, the project abbreviation and each category's abbreviation.
Future<void> showNewProjectDialog(BuildContext context) async {
  final state = context.read<AppState>();
  final draft = await showDialog<Project>(context: context, builder: (_) => const _ProjectDialog());
  if (draft == null || !context.mounted) return;
  await act(context, () => state.createProject(draft), done: '${draft.name} created.');
}

/// Admin: edit a project's name, abbreviations and guest access.
Future<void> showEditProjectDialog(BuildContext context, Project project) async {
  final state = context.read<AppState>();
  final edited = await showDialog<Project>(context: context, builder: (_) => _ProjectDialog(existing: project));
  if (edited == null || !context.mounted) return;
  await act(context, () => state.saveProject(edited), done: 'Saved.');
}

class _ProjectDialog extends StatefulWidget {
  const _ProjectDialog({this.existing});
  final Project? existing;
  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _abbr = TextEditingController(text: widget.existing?.code ?? '');
  late bool _abbrTouched = widget.existing != null;
  late bool _guests = widget.existing?.guestVisible ?? false;
  late final List<(TextEditingController, TextEditingController)> _cats = [
    for (final c in widget.existing?.categories ?? defaultCategories)
      (
        TextEditingController(text: c),
        TextEditingController(text: widget.existing?.categoryCode(c) ?? suggestCategoryAbbr(c)),
      ),
  ];
  /// Categories that already exist keep their name (observations refer to it); only the abbreviation changes.
  late final Set<TextEditingController> _fixed = {if (widget.existing != null) for (final c in _cats) c.$1};

  /// Abbreviations typed by hand are not replaced by suggestions.
  late final Set<TextEditingController> _touched = {for (final c in _cats) c.$2};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _abbr.dispose();
    for (final c in _cats) {
      c.$1.dispose();
      c.$2.dispose();
    }
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    final abbr = _abbr.text.trim().toUpperCase();
    if (name.isEmpty) return setState(() => _error = 'Enter the project name.');
    if (!RegExp(r'^[A-Z0-9]{2,8}$').hasMatch(abbr)) {
      return setState(() => _error = 'The project abbreviation must be 2 to 8 letters or numbers, e.g. NCMC.');
    }
    final cats = <String>[];
    final abbrs = <String, String>{};
    for (final c in _cats) {
      final n = c.$1.text.trim();
      if (n.isEmpty) continue;
      if (cats.contains(n)) return setState(() => _error = 'The category "$n" is listed twice.');
      final a = c.$2.text.trim().toUpperCase();
      if (!RegExp(r'^[A-Z0-9]{1,6}$').hasMatch(a)) {
        return setState(() => _error = 'Give "$n" an abbreviation of 1 to 6 letters or numbers, e.g. MEP.');
      }
      cats.add(n);
      abbrs[n] = a;
    }
    if (cats.isEmpty) return setState(() => _error = 'Add at least one category.');
    final old = widget.existing;
    Navigator.pop(
      context,
      old == null
          ? Project(id: '', name: name, categories: cats, abbr: abbr, categoryAbbrs: abbrs, guestVisible: _guests)
          : old.copyWith(name: name, categories: cats, abbr: abbr, categoryAbbrs: abbrs, guestVisible: _guests),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Edit project' : 'New project'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _name,
                  autofocus: !editing,
                  decoration: const InputDecoration(labelText: 'Project name', hintText: 'e.g. New Castle Medical Center'),
                  onChanged: (v) {
                    if (!_abbrTouched) setState(() => _abbr.text = suggestProjectAbbr(v));
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _abbr,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Abbreviation', hintText: 'NCMC'),
                  onChanged: (_) => _abbrTouched = true,
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              'Observation numbers look like ${(_abbr.text.isEmpty ? 'PRJ' : _abbr.text.toUpperCase())}-'
              '${_cats.isEmpty ? 'MEP' : _cats.first.$2.text.toUpperCase()}-001.'
              '${editing ? ' Changing abbreviations does not renumber existing observations.' : ''}',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
            const SizedBox(height: 16),
            Text('Categories and their abbreviations', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink2)),
            const SizedBox(height: 8),
            for (var i = 0; i < _cats.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _cats[i].$1,
                      readOnly: _fixed.contains(_cats[i].$1),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Category',
                        fillColor: _fixed.contains(_cats[i].$1) ? c.surface2 : null,
                      ),
                      onChanged: (v) {
                        if (!_touched.contains(_cats[i].$2)) setState(() => _cats[i].$2.text = suggestCategoryAbbr(v));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _cats[i].$2,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(isDense: true, hintText: 'ABR'),
                      onChanged: (_) => setState(() => _touched.add(_cats[i].$2)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove category (existing observations keep it)',
                    onPressed: () => setState(() => _cats.removeAt(i)),
                    icon: Icon(Icons.close, size: 20, color: c.muted),
                  ),
                ]),
              ),
            TextButton.icon(
              onPressed: () => setState(() => _cats.add((TextEditingController(), TextEditingController()))),
              icon: const Icon(Icons.add),
              label: const Text('Add category'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _guests,
              onChanged: (v) => setState(() => _guests = v),
              title: const Text('Let guests view this project (read-only)'),
              subtitle: const Text('Off: only the project team and admins can see it.'),
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: c.urgentText, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _done, child: Text(editing ? 'Save' : 'Create project')),
      ],
    );
  }
}
