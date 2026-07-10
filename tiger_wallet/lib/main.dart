import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/biometric_service.dart';
import 'services/supabase_service.dart';
import 'services/wallet_controller.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Loads SUPABASE_URL / SUPABASE_ANON_KEY / GROQ_API_KEY / GROQ_MODEL from
  // a .env file at the project root. Add .env to .gitignore — never commit
  // real keys. See .env.example for the expected keys.
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  runApp(const CensorCentsApp());
}

class CensorCentsApp extends StatelessWidget {
  const CensorCentsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WalletController(),
      child: MaterialApp(
        title: 'CensorCents',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const _AuthGate(),
      ),
    );
  }
}

/// Routes between LoginScreen and DashboardScreen based on Supabase auth
/// state, and keeps listening so a sign-in or sign-out anywhere in the app
/// swaps the visible screen automatically — no manual Navigator calls needed.
/// When signed in, [_BiometricLockGate] additionally gates access behind
/// Face ID / fingerprint if the user has turned that on in Settings.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final service = SupabaseService.instance;

    return StreamBuilder<AuthState>(
      stream: service.authStateChanges,
      builder: (context, snapshot) {
        final isSignedIn = service.currentUser != null;
        return isSignedIn ? const _BiometricLockGate(child: DashboardScreen()) : const LoginScreen();
      },
    );
  }
}

/// If app lock is enabled, shows a simple unlock screen requiring biometrics
/// before revealing [child]. If app lock is off (or unsupported), just shows
/// [child] directly — this check happens once per app session, not per
/// screen, so navigating within the app never re-prompts.
class _BiometricLockGate extends StatefulWidget {
  final Widget child;
  const _BiometricLockGate({required this.child});

  @override
  State<_BiometricLockGate> createState() => _BiometricLockGateState();
}

class _BiometricLockGateState extends State<_BiometricLockGate> {
  bool _checked = false;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _checkLock();
  }

  Future<void> _checkLock() async {
    final enabled = await BiometricService.instance.isEnabled;
    if (!enabled) {
      setState(() {
        _checked = true;
        _unlocked = true;
      });
      return;
    }
    setState(() => _checked = true);
    _attemptUnlock();
  }

  Future<void> _attemptUnlock() async {
    final success = await BiometricService.instance.authenticate();
    if (!mounted) return;
    setState(() => _unlocked = success);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.savingsGreen)),
      );
    }
    if (_unlocked) return widget.child;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 56, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              const Text(
                'CensorCents is locked',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _attemptUnlock,
                child: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}