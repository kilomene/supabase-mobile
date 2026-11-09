import 'package:flutter/material.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/services/auth_service.dart';
import 'package:supabase_mobile/services/secure_token_storage.dart';
import 'package:supabase_mobile/services/dashboard_links.dart';
import 'package:supabase_mobile/widgets/common.dart';
import 'package:supabase_mobile/screens/home_shell.dart';

/// Login / Create account — built to the APPROVED preview:
/// centred Supabase logo, "Welcome to Supabase", Log in / Create
/// account tabs (green underline on the active tab), big green
/// Continue, "or continue with", GitHub + Google, footer line.
/// Every control is wired to something real:
///  - Continue / GitHub / Google open the REAL Supabase login in the
///    system browser — OAuth (PKCE) when the app's client ID is set,
///    otherwise the dashboard sign-in / sign-up page itself.
///  - There is deliberately NO email / password form in the app.
///    Supabase has no password-login API, so a form here would be
///    fake — and the app must never see a password. The password is
///    typed only on supabase.com itself, in the browser.
///  - PAT connect below stays as the fallback login path.
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

  /// Real sign-in: OAuth when the app's client ID is configured,
  /// otherwise the real dashboard sign-in / sign-up page in the
  /// browser (the user signs in there, then connects with a PAT).
  Future<void> _signInBrowser() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final clientId = await AuthService().getClientId();
      if (clientId.isNotEmpty) {
        await AuthService().startOAuthLogin();
        if (mounted) setState(() => _waitingOAuth = true);
      } else if (_loginTab) {
        await DashboardLinks.signIn();
      } else {
        await DashboardLinks.signUpPage();
      }
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

  Future<void> _saveClientId() async {
    final id = _clientId.text.trim();
    if (id.isNotEmpty) {
      await SecureTokenStorage().saveOAuthClientId(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Client ID saved')));
      }
    }
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : AppTheme.muted)),
            ),
            Container(
                height: 3,
                color: active ? AppTheme.green : Colors.transparent),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomPaint(
                  size: const Size(40, 40), painter: _BoltPainter()),
              const SizedBox(width: 12),
              const Text('supabase',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 28),
          const Text('Welcome to Supabase',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              _tab('Log in', _loginTab, () => setState(() => _loginTab = true)),
              _tab('Create account', !_loginTab,
                  () => setState(() => _loginTab = false)),
            ]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _signInBrowser,
              child: _busy
                  ? const CircularProgressIndicator(color: Colors.black)
                  : const Text('Continue', style: TextStyle(fontSize: 18)),
            ),
          ),
          if (_waitingOAuth) ...[
            const SizedBox(height: 12),
            const Text(
                'Finish signing in in your browser — you will come back here automatically.',
                style: TextStyle(color: AppTheme.green)),
          ],
          const SizedBox(height: 20),
          const Row(children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('or continue with',
                  style: TextStyle(color: AppTheme.muted)),
            ),
            Expanded(child: Divider()),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(SimpleIcons.github, size: 20),
                label: const Text('GitHub'),
                onPressed: _busy ? null : _signInBrowser,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(SimpleIcons.google, size: 20),
                label: const Text('Google'),
                onPressed: _busy ? null : _signInBrowser,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          const Text(
              'Create a free Supabase account to manage projects, database, auth and storage from your phone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted)),
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorView(_error!),
          ],
          const Divider(height: 40),
          const Text('Or connect with a Personal Access Token',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _pat,
            decoration: const InputDecoration(
                labelText: 'Personal Access Token', hintText: 'sbp_fc_…'),
            obscureText: true,
          ),
          const SizedBox(height: 8),
          const Text(
              'Stored only in this device\'s secure storage. Never sent anywhere except api.supabase.com.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          TextButton(
            onPressed: () => DashboardLinks.accessTokens(),
            child: const Text('Open Access Tokens in the dashboard'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _busy ? null : _connectPat,
            child: const Text('Connect'),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            title: const Text('Advanced — OAuth client ID',
                style: TextStyle(fontSize: 14)),
            children: [
              TextField(
                controller: _clientId,
                decoration: const InputDecoration(
                    labelText: 'Client ID',
                    hintText: 'From the Supabase Mobile OAuth app'),
              ),
              const SizedBox(height: 8),
              const Text(
                  'Public value, not a secret. Needed for the in-app sign-in; without it, Continue opens the dashboard sign-in page instead.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _saveClientId,
                child: const Text('Save client ID'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ]),
      ),
    );
  }
}

/// Supabase lightning-bolt mark, drawn in the brand green.
class _BoltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.66, 0)
      ..lineTo(size.width * 0.24, size.height * 0.58)
      ..lineTo(size.width * 0.46, size.height * 0.58)
      ..lineTo(size.width * 0.32, size.height)
      ..lineTo(size.width * 0.76, size.height * 0.40)
      ..lineTo(size.width * 0.54, size.height * 0.40)
      ..close();
    canvas.drawPath(path, Paint()..color = AppTheme.green);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
