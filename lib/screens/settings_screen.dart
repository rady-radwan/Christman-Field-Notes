import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin_screen.dart';
import 'sign_in_screen.dart';

const appVersion = '0.5.0';

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
        content: const Text('Close Field Notes and open it again to switch to the new connection.'),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
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
            ]),
            card([
              const SectionLabel('Account'),
              const SizedBox(height: 10),
              if (state.isGuest)
                Row(children: [
                  Expanded(
                    child: Text('You are looking around as a guest. Sign in to add notes and replies.',
                        style: TextStyle(color: c.muted)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => openSignIn(context),
                    child: const Text('Sign in'),
                  ),
                ])
              else
              Row(children: [
                Avatar(name: state.me?.name ?? '?', size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(state.me?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text('${state.me?.email ?? ''}${state.isAdmin ? ' · Admin' : ''}${state.isPending ? ' · Waiting for approval' : ''}',
                        style: TextStyle(color: c.muted)),
                  ]),
                ),
                OutlinedButton(
                  onPressed: () async {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    await state.signOut();
                  },
                  child: const Text('Sign out'),
                ),
              ]),
              if (state.isAdmin) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminScreen())),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: const Text('Admin: users, projects, categories'),
                ),
              ],
            ]),
            card([
              const SectionLabel('Data'),
              const SizedBox(height: 10),
              Text('Saved to: ${state.repo.modeLabel}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                state.repo.isServer
                    ? 'Everyone on the project sees the same notes.'
                    : 'Only this computer can see these notes until a shared server is connected.',
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
                      if (context.mounted) showInfo(context, 'Sample notes added.');
                    },
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Add sample notes'),
                  ),
              ]),
            ]),
            card([
              const SectionLabel('About'),
              const SizedBox(height: 10),
              const BrandLogo(height: 20),
              const SizedBox(height: 8),
              Text('Christman Field Notes, version $appVersion', style: TextStyle(color: c.muted)),
            ]),
          ]),
        ),
      ),
    );
  }
}
