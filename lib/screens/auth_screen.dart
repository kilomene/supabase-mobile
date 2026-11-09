import 'package:flutter/material.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/services/auth_service.dart';
import 'package:supabase_mobile/services/secure_token_storage.dart';
import 'package:supabase_mobile/services/dashboard_links.dart';
import 'package:supabase_mobile/widgets/common.dart';
import 'package:supabase_mobile/screens/home_shell.dart';

/// Login / Create account (preview 1).
/// REAL login, end to end:
///  - "Sign in with Supabase" — OAuth 2.0 PKCE in the SYSTEM BROWSER
///    (GitHub / Google / email on supabase.com). Supabase sends the user
///    back into the app with a code, the app trades it for a token
///    directly at api.supabase.com/v1/oauth/token. No password is ever
///    typed into or sent by this app. Needs the OAuth app's client ID
///    (public value) — paste it once below; it is stored securely.
///  - "Create account" / "Log in" in the system browser (supabase.com)
///  - "Connect with a Personal Access Token" (paste sbp_fc_… token)
class AuthScreen extends StatefulWidget {
  final String? loginError;
  const AuthScreen({this.loginError, super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _pat = TextEditingController();
  final _clientId = TextEditingController();
  bool _loginTab = true;
  String? _error;
  bool _busy = false;
  bool _waitingOAuth = false;

  @override
  void initState() {
    super.initState();
    if (widget.loginError != null) _error = widget.loginError;
    SecureTokenStorage().readOAuthClientId().then((id) {
      if (mounted && id != null && id.isNotEmpty) {
        _clientId.text = id;
      }
    });
  }

  Future<void> _startOAuth() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = _clientId.text.trim();
      if (id.isNotEmpty) {
        await SecureTokenStorage().saveOAuthClientId(id);
      }
      await AuthService().startOAuthLogin();
      if (mounted) setState(() => _waitingOAuth = true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectPat() async {
    setState(() => _busy = true);
    try {
      await AuthService().connectWithPat(_pat.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeShell()));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 32),
          const Text('supabase',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Welcome to Supabase',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Log in')),
              ButtonSegment(value: false, label: Text('Create account')),
            ],
            selected: {_loginTab},
            onSelectionChanged: (s) => setState(() => _loginTab = s.first),
          ),
          const SizedBox(height: 16),
          const Text('Sign in with Supabase (real login)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Opens the real Supabase login page in your browser (GitHub, Google or email). Supabase sends you back into the app and the app trades the code for a token — your password is never typed here.'),
          const SizedBox(height: 8),
          TextField(
            controller: _clientId,
            decoration: const InputDecoration(
                labelText: 'OAuth client ID (from the Supabase Mobile OAuth app)'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _busy ? null : _startOAuth,
            child: _busy
                ? const CircularProgressIndicator()
                : const Text('Sign in with Supabase'),
          ),
          if (_waitingOAuth) ...[
            const SizedBox(height: 8),
            const Text(
                'Finish signing in in your browser — you will come back here automatically.',
                style: TextStyle(color: AppTheme.green)),
          ],
          const Divider(height: 32),
          const Text(
              'Supabase accounts are created in your browser — there is no signup API. Tap below, create/log in on supabase.com, then paste a Personal Access Token to connect.'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => DashboardLinks.signUp(),
                child: Text(_loginTab ? 'Log in on supabase.com' : 'Create account on supabase.com'),
              ),
            ),
          ]),
          TextButton(
            onPressed: () => DashboardLinks.accessTokens(),
            child: const Text('Open Access Tokens in the dashboard'),
          ),
          const Divider(height: 32),
          const Text('Or connect with a Personal Access Token',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _pat,
            decoration: const InputDecoration(
                labelText: 'Personal Access Token (sbp_fc_…)'),
            obscureText: true,
          ),
          const SizedBox(height: 8),
          const Text(
              'Stored only in this device\'s secure storage. Never sent anywhere except api.supabase.com.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            ErrorView(_error!),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy ? null : _connectPat,
            child: _busy
                ? const CircularProgressIndicator()
                : const Text('Continue'),
          ),
        ]),
      ),
    );
  }
}
