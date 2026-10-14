import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin_screen.dart';
import 'sign_in_screen.dart';
import 'team.dart';

const appVersion = '0.7.0';
const appName = 'Christman Field Observations';

Future<void> showServerSettings(BuildContext context) async {
  final state = context.read<AppState>();
  final url = TextEditingController(text: state.settings.serverUrl);
  final key = TextEditingController(text: state.settings.serverKey);
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Shared server'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Paste the Project URL and the publishable key from your Supabase project '
            '(Project Settings > API Keys). Leave both empty to use the Christman company server.',
            style: TextStyle(color: FnColors.of(ctx).muted, height: 1.35),
          ),
          const SizedBox(height: 14),
          TextField(controller: url, decoration: const InputDecoration(labelText: 'Project URL')),
          const SizedBox(height: 10),
          TextField(controller: key, decoration: const InputDecoration(labelText: 'Publishable key'), maxLines: 2),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );
  if (saved != true) return;
  await state.settings.setServer(url.text, key.text);
  if (context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saved'),
        content: const Text('Close Field Observations and open it again to switch to the new connection.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    Widget card(List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );
    final project = state.project;
    final showTeam = project != null && state.canContribute && state.isMemberOf(project.id);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            card([
              const SectionLabel('Account'),
              const SizedBox(height: 10),
              if (state.isGuest)
                Row(children: [
                  Expanded(
                    child: Text('You are looking around as a guest. Sign in to report observations and join discussions.',
                        style: TextStyle(color: c.muted)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: () => openSignIn(context), child: const Text('Sign in')),
                ])
              else
                Row(children: [
                  Avatar(name: state.me?.name ?? '?', size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(state.me?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(
                        [
                          if ((state.me?.company ?? '').isNotEmpty) state.me!.company,
                          state.me?.email ?? '',
                          if (state.isAdmin) 'Admin',
                          if (state.isPending) 'Waiting for approval',
                        ].join(' · '),
                        style: TextStyle(color: c.muted),
                      ),
                    ]),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showEditProfileDialog(context),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      await state.signOut();
                    },
                    child: const Text('Sign out'),
                  ),
                ]),
              if (!state.isGuest && (state.me?.company ?? '').isEmpty) ...[
                const SizedBox(height: 8),
                Text('Tip: add your company or trade (Edit) so the team and the dashboard show it.',
                    style: TextStyle(fontSize: 13, color: c.accentText)),
              ],
              if (state.isAdmin) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminScreen())),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: Text(
                    state.pendingInvites.isEmpty
                        ? 'Admin: people, projects, categories'
                        : 'Admin: people, projects, categories · ${state.pendingInvites.length} member request(s)',
                  ),
                ),
              ],
            ]),
            if (showTeam) card([ProjectTeamPanel(projectId: project.id)]),
            card([
              const SectionLabel('Appearance'),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Use system setting'), icon: Icon(Icons.settings_suggest_outlined)),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                ],
                selected: {state.themeMode},
                onSelectionChanged: (s) => state.setThemeMode(s.first),
              ),
              const SizedBox(height: 18),
              Text('Font', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink2)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in fontChoices) _FontBox(family: f, selected: state.fontChoice == f, onTap: () => state.setFont(f)),
              ]),
            ]),
            card([
              const SectionLabel('Data'),
              const SizedBox(height: 10),
              Text('Saved to: ${state.repo.modeLabel}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                state.repo.isServer
                    ? 'Everyone on a project sees the same observations.'
                    : 'Only this computer can see these observations until a shared server is connected.',
                style: TextStyle(color: c.muted),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (state.isAdmin || !state.repo.isServer)
                  OutlinedButton.icon(
                    onPressed: () => showServerSettings(context),
                    icon: const Icon(Icons.dns_outlined),
                    label: const Text('Server connection'),
                  ),
                if (state.canAddSamples)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await state.addSampleNotes();
                      if (context.mounted) showInfo(context, 'Sample observations added.');
                    },
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Add sample observations'),
                  ),
              ]),
            ]),
            card([
              const SectionLabel('About'),
              const SizedBox(height: 10),
              const BrandLogo(height: 20),
              const SizedBox(height: 8),
              Text('$appName, version $appVersion', style: TextStyle(color: c.muted)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// A font choice shown in its own font.
class _FontBox extends StatelessWidget {
  const _FontBox({required this.family, required this.selected, required this.onTap});
  final String family;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final f = family.isEmpty ? 'Barlow' : family;
    return Material(
      color: selected ? c.avatarBg : c.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? c.accent : c.line, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 182,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Aa', style: TextStyle(fontFamily: f, fontSize: 22, fontWeight: FontWeight.w700, color: c.ink)),
                const Spacer(),
                if (selected) Icon(Icons.check_circle, size: 18, color: c.accentText),
              ]),
              const SizedBox(height: 2),
              Text(fontLabel(family),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: f, fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
              Text('Fire damper, Level 3',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: f, fontSize: 12, color: c.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}
