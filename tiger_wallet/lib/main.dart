import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
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
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final service = SupabaseService.instance;

    return StreamBuilder<AuthState>(
      stream: service.authStateChanges,
      builder: (context, snapshot) {
        final isSignedIn = service.currentUser != null;
        return isSignedIn ? const DashboardScreen() : const LoginScreen();
      },
    );
  }
}