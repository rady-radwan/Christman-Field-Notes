import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'settings_screen.dart';

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key, this.outlined = false});
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = FnColors.of(context);
    return IconButton(
      tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
      onPressed: () => context.read<AppState>().toggleTheme(Theme.of(context).brightness),
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      color: c.ink,
      style: outlined
          ? IconButton.styleFrom(side: BorderSide(color: c.line2), backgroundColor: c.surface, minimumSize: const Size(44, 44))
          : IconButton.styleFrom(minimumSize: const Size(44, 44)),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final state = context.read<AppState>();
    final server = state.repo.isServer;
    final email = _email.text.trim();
    if (!email.contains('@')) return setState(() => _error = 'Enter your work email.');
    if (_register && _name.text.trim().isEmpty) return setState(() => _error = 'Enter your name.');
    if (server && _password.text.length < 8) return setState(() => _error = 'The password needs at least 8 characters.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await state.register(_name.text, email, _password.text);
      } else {
        await state.signIn(email, _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final state = context.watch<AppState>();
    final server = state.repo.isServer;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Center(child: BrandLogo(full: true, height: 44)),
                    const SizedBox(height: 18),
                    Center(child: Container(width: 48, height: 3, color: c.accent)),
                    const SizedBox(height: 18),
                    Text('Field Notes', textAlign: TextAlign.center, style: condensed(40)),
                    const SizedBox(height: 8),
                    Text('Photos, markups and replies for every issue on site.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.muted)),
                    const SizedBox(height: 32),
                    if (!server) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.surface2,
                          border: Border.all(color: c.line),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'No shared server connected yet. Notes are saved on this computer only. '
                          'The first account created here becomes the admin.',
                          style: TextStyle(fontSize: 13, color: c.muted, height: 1.35),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (_register) ...[
                      const _Label('Your name'),
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(hintText: 'First and last name'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const _Label('Work email'),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(hintText: 'Your work email'),
                      onSubmitted: (_) => server ? null : _submit(),
                    ),
                    if (server) ...[
                      const SizedBox(height: 12),
                      const _Label('Password'),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                        decoration: InputDecoration(hintText: _register ? 'At least 8 characters' : 'Password'),
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: c.urgentText, fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_register ? 'Request access' : 'Sign in'),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(_register ? 'Already have an account? ' : 'New to the project? ',
                            style: TextStyle(color: c.muted)),
                        TextButton(
                          onPressed: () => setState(() {
                            _register = !_register;
                            _error = null;
                          }),
                          child: Text(_register ? 'Sign in' : 'Request access'),
                        ),
                      ]),
                    ),
                    Text('An admin approves every new account.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.muted)),
                  ]),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Row(children: [
              IconButton(
                tooltip: 'Server settings',
                onPressed: () => showServerSettings(context),
                icon: const Icon(Icons.dns_outlined),
                color: c.ink,
                style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
              ),
              const ThemeToggleButton(outlined: true),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      );
}

class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final state = context.watch<AppState>();
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const BrandLogo(height: 22),
              const SizedBox(height: 28),
              Icon(Icons.hourglass_top_rounded, size: 44, color: c.accentText),
              const SizedBox(height: 14),
              Text('Waiting for approval', style: condensed(30)),
              const SizedBox(height: 10),
              Text(
                'Thanks, ${state.me?.name ?? ''}. An admin needs to approve your account and add you to a project. '
                'Check back soon.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => state.reload(quiet: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Check again'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: state.signOut, child: const Text('Sign out')),
            ]),
          ),
        ),
      ),
    );
  }
}
