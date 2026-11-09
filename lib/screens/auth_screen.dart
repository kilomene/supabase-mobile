import 'package:flutter/material.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/services/auth_service.dart';
import 'package:supabase_mobile/services/dashboard_links.dart';
import 'package:supabase_mobile/widgets/common.dart';
import 'package:supabase_mobile/screens/home_shell.dart';

/// Login / Create account (preview 1).
/// NO public Cloud signup/login API exists, so this screen does NOT
/// collect a Supabase password and POST it anywhere. It offers:
///  - "Create account" / "Log in" in the system browser (supabase.com)
///  - "Connect with a Personal Access Token" (paste sbp_fc_… token)
///  - OAuth (needs the backend exchange — see AuthService / README).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _pat = TextEditingController();
  bool _loginTab = true;
  String? _error;
  bool _busy = false;

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
