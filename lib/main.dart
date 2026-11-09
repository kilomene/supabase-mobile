import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/services/auth_service.dart';
import 'package:supabase_mobile/services/secure_token_storage.dart';
import 'package:supabase_mobile/screens/home_shell.dart';
import 'package:supabase_mobile/screens/auth_screen.dart';

/// Entry point. No SupabaseClient is initialised here: the app manages
/// MANY projects, so clients are created per project on demand
/// (see ProjectClientRegistry). No key is hard-coded anywhere.
/// This gate also listens for the OAuth deep-link return
/// (com.novaworks.supabase_mobile://oauth/callback) and completes the
/// login when Supabase sends the user back with ?code=…&state=….
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
  String? _loginError;
  StreamSubscription<Uri>? _linkSub;
  final _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    _checkToken();
    _listenForOAuthReturn();
  }

  Future<void> _checkToken() async {
    final v = await SecureTokenStorage().hasManagementToken();
    if (mounted) setState(() => _connected = v);
  }

  Future<void> _listenForOAuthReturn() async {
    _linkSub = _appLinks.uriLinkStream.listen(_handleLink);
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleLink(initial);
    } catch (_) {
      // No initial link — normal cold start.
    }
  }

  Future<void> _handleLink(Uri uri) async {
    try {
      final handled = await AuthService().handleOAuthCallback(uri);
      if (handled && mounted) setState(() => _connected = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loginError = '$e';
          _connected = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_connected == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.green)),
      );
    }
    return _connected!
        ? const HomeShell()
        : AuthScreen(loginError: _loginError);
  }
}
