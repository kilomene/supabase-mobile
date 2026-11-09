import 'package:flutter/material.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/services/secure_token_storage.dart';
import 'package:supabase_mobile/screens/home_shell.dart';
import 'package:supabase_mobile/screens/auth_screen.dart';

/// Entry point. No SupabaseClient is initialised here: the app manages
/// MANY projects, so clients are created per project on demand
/// (see ProjectClientRegistry). No key is hard-coded anywhere.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SupabaseMobileApp());
}

class SupabaseMobileApp extends StatelessWidget {
  const SupabaseMobileApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Supabase Mobile',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const _RootGate(),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();
  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool? _connected;
  @override
  void initState() {
    super.initState();
    SecureTokenStorage().hasManagementToken().then(
      (v) => mounted ? setState(() => _connected = v) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_connected == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.green)),
      );
    }
    return _connected! ? const HomeShell() : const AuthScreen();
  }
}
