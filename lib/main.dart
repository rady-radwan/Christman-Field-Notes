import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/local_repo.dart';
import 'data/repo.dart';
import 'data/supabase_repo.dart';
import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';
import 'state/app_state.dart';
import 'state/settings.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  Repo repo;
  String? startupError;
  if (settings.hasServer) {
    try {
      repo = await SupabaseRepo.connect(settings.serverUrl, settings.serverKey);
    } catch (e) {
      // Bad server details should never lock people out: fall back to this computer.
      startupError = 'Could not connect to the shared server. Check Server connection in Settings.';
      repo = await LocalRepo.open();
    }
  } else {
    repo = await LocalRepo.open();
  }
  final state = AppState(repo, settings);
  state.startupWarning = startupError;
  runApp(ChangeNotifierProvider.value(value: state..init(), child: const FieldNotesApp()));
}

class FieldNotesApp extends StatelessWidget {
  const FieldNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppState, ThemeMode>((s) => s.themeMode);
    return MaterialApp(
      title: 'Christman Field Notes',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.booting) {
      return const Scaffold(body: Center(child: BrandLogo(full: true, height: 44)));
    }
    final me = state.me;
    if (me == null) return const SignInScreen();
    if (!me.isApproved) return const PendingScreen();
    return const HomeScreen();
  }
}
