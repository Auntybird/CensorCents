// =============================================================================
// TIGER WALLET
// A gamified budgeting app where an AI "strict traditional parent" (Llama 3
// via Groq) reacts to every transaction you log.
//
// STACK ("Stingy Developer" edition):
//   - Flutter (Dart)              -> cross-platform UI
//   - Supabase                    -> Auth + Postgres + Realtime
//   - Groq API (Llama 3)          -> AI critique engine
//
// SETUP:
//   1. Run supabase_schema.sql in your Supabase project's SQL editor.
//   2. Copy .env.example -> .env and fill in SUPABASE_URL, SUPABASE_ANON_KEY,
//      GROQ_API_KEY.
//   3. flutter pub get
//   4. flutter run
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/wallet_controller.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load secrets from .env (see .env.example). Never hardcode keys in source.
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const TigerWalletApp());
}

class TigerWalletApp extends StatelessWidget {
  const TigerWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WalletController(),
      child: MaterialApp(
        title: 'CensorCent',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark, // enforce dark mode app-wide, per spec
        home: const _AuthGate(),
      ),
    );
  }
}

/// Listens to Supabase's auth stream and swaps between the Login screen and
/// the Dashboard automatically — no manual navigation calls needed anywhere
/// else in the app.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          return const DashboardScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
