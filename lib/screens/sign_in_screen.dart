import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repo.dart';
import '../models.dart';
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

enum _Step { email, code, name }

class _SignInScreenState extends State<SignInScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  _Step _step = _Step.email;
  bool _busy = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;
  bool _localRegister = false; // only used without a shared server

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _cooldown <= 1) {
        t.cancel();
        if (mounted) setState(() => _cooldown = 0);
        return;
      }
      setState(() => _cooldown--);
    });
  }

  Future<void> _run(Future<void> Function(AppState state) action) async {
    final state = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(state);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish() {
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  String get _emailText => _email.text.trim();

  Future<void> _sendCode() => _run((state) async {
        if (!_emailText.contains('@') || !_emailText.contains('.')) throw RepoException('Enter your work email.');
        await state.sendCode(_emailText);
        if (!mounted) return;
        setState(() {
          _step = _Step.code;
          _code.clear();
        });
        _startCooldown();
      });

  Future<void> _verify() => _run((state) async {
        final code = _code.text.replaceAll(RegExp(r'\s'), '');
        if (code.length < 6) throw RepoException('Enter the code from the email.');
        await state.verifyCode(_emailText, code);
        if (!mounted) return;
        if (state.needsName) {
          setState(() => _step = _Step.name);
        } else {
          _finish();
        }
      });

  Future<void> _saveName() => _run((state) async {
        if (_name.text.trim().isEmpty) throw RepoException('Enter your name.');
        await state.updateMyName(_name.text);
        _finish();
      });

  /// Without a shared server there is no email: name + email on this computer only.
  Future<void> _localSubmit() => _run((state) async {
        if (!_emailText.contains('@')) throw RepoException('Enter your work email.');
        if (_localRegister) {
          if (_name.text.trim().isEmpty) throw RepoException('Enter your name.');
          await state.register(_name.text, _emailText, '');
        } else {
          await state.signIn(_emailText, '');
        }
        _finish();
      });

  Widget _button(String label, VoidCallback onTap) => FilledButton(
        onPressed: _busy ? null : onTap,
        child: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label),
      );

  List<Widget> _emailStep(FnColors c) => [
        const _Label('Work email'),
        TextField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(hintText: 'name@company.com'),
          onSubmitted: (_) => _sendCode(),
        ),
        const SizedBox(height: 16),
        _button('Email me a sign-in code', _sendCode),
        const SizedBox(height: 16),
        Text(
          'No password needed. We email you a short code; type it here and you are in. '
          'First time? The same code creates your account, and an admin approves it.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: c.muted, height: 1.4),
        ),
      ];

  List<Widget> _codeStep(FnColors c) => [
        Text.rich(
          TextSpan(style: TextStyle(fontSize: 15, color: c.muted, height: 1.4), children: [
            const TextSpan(text: 'We sent a sign-in code to\n'),
            TextSpan(text: _emailText, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
          ]),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text('It can take a minute. Check your junk folder too.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          textAlign: TextAlign.center,
          maxLength: 10,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 8),
          decoration: const InputDecoration(hintText: '••••••', counterText: ''),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 14),
        _button('Sign in', _verify),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, children: [
          TextButton(
            onPressed: _busy || _cooldown > 0 ? null : _sendCode,
            child: Text(_cooldown > 0 ? 'Send a new code (${_cooldown}s)' : 'Send a new code'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _step = _Step.email;
                      _error = null;
                    }),
            child: const Text('Use a different email'),
          ),
        ]),
      ];

  List<Widget> _nameStep(FnColors c) => [
        Text('Welcome! What is your name?', textAlign: TextAlign.center, style: condensed(24)),
        const SizedBox(height: 6),
        Text('This is how the team will see you on notes and replies.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 14),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(hintText: 'First and last name'),
          onSubmitted: (_) => _saveName(),
        ),
        const SizedBox(height: 14),
        _button('Continue', _saveName),
      ];

  List<Widget> _localStep(FnColors c) => [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface2,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'No shared server connected. Notes are saved on this computer only. '
            'The first account created here becomes the admin.',
            style: TextStyle(fontSize: 13, color: c.muted, height: 1.35),
          ),
        ),
        const SizedBox(height: 16),
        if (_localRegister) ...[
          const _Label('Your name'),
          TextField(controller: _name, textCapitalization: TextCapitalization.words),
          const SizedBox(height: 12),
        ],
        const _Label('Work email'),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, onSubmitted: (_) => _localSubmit()),
        const SizedBox(height: 16),
        _button(_localRegister ? 'Create account' : 'Sign in', _localSubmit),
        TextButton(
          onPressed: () => setState(() => _localRegister = !_localRegister),
          child: Text(_localRegister ? 'I already have an account' : 'Create an account'),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final state = context.watch<AppState>();
    final body = !state.usesEmailCodes
        ? _localStep(c)
        : switch (_step) {
            _Step.email => _emailStep(c),
            _Step.code => _codeStep(c),
            _Step.name => _nameStep(c),
          };
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
                    const SizedBox(height: 28),
                    ...body,
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.urgentText, fontWeight: FontWeight.w600)),
                    ],
                  ]),
                ),
              ),
            ),
          ),
          if (Navigator.of(context).canPop())
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                color: c.ink,
                style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
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

/// Opens the sign-in screen.
Future<void> openSignIn(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const SignInScreen()));

/// Call before any action that changes data. Returns true when the user may go ahead.
/// Guests are asked to sign in; people waiting for approval are told so.
Future<bool> requireSignIn(BuildContext context, String action) async {
  final state = context.read<AppState>();
  if (state.canContribute) return true;
  if (state.isPending) {
    showInfo(context, 'Your account is waiting for admin approval. You can look around until then.');
    return false;
  }
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign in to continue'),
      content: Text('Anyone can look around. To $action, sign in with your email. We send you a code, no password needed.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign in')),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;
  await openSignIn(context);
  if (!context.mounted) return false;
  final after = context.read<AppState>();
  if (after.isPending) {
    showInfo(context, 'Thanks! An admin needs to approve your account before you can add things.');
    return false;
  }
  return after.canContribute;
}

/// Header button for guests.
class SignInButton extends StatelessWidget {
  const SignInButton({super.key});
  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: () => openSignIn(context),
        style: FilledButton.styleFrom(minimumSize: const Size(64, 40), shape: const StadiumBorder()),
        icon: const Icon(Icons.login, size: 18),
        label: const Text('Sign in'),
      );
}

/// Shown at the top when signed in but not yet approved.
class PendingBanner extends StatelessWidget {
  const PendingBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isPending) return const SizedBox.shrink();
    final c = FnColors.of(context);
    return Material(
      color: c.statusBg(NoteStatus.suspended),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Icon(Icons.hourglass_top_rounded, size: 18, color: c.statusFg(NoteStatus.suspended)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Your account is waiting for admin approval. You can look around until then.',
                style: TextStyle(color: c.statusFg(NoteStatus.suspended), fontWeight: FontWeight.w600)),
          ),
          TextButton(onPressed: () => state.reload(quiet: true), child: const Text('Check again')),
        ]),
      ),
    );
  }
}
