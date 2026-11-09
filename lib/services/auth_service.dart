import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_mobile/services/secure_token_storage.dart';

/// Cloud-account auth. There is NO public signup/login API for a
/// Supabase Cloud account (report §1.1). Signup/login happen in the
/// SYSTEM BROWSER (never a WebView), then the app connects via:
///  (a) OAuth 2.0 PKCE — the code exchange needs client_secret as Basic
///      auth, which MUST live on your backend/proxy, never in this app.
///      This class builds the authorize URL and PKCE challenge; the
///      exchange itself is intentionally NOT implemented here — see
///      README "OAuth backend" and TODO below.
///  (b) PAT-paste fallback — user creates a scoped token at
///      supabase.com/dashboard/account/tokens and pastes it here.
class AuthService {
  static const authorizeBase =
      'https://api.supabase.com/v1/oauth/authorize';
  final _store = SecureTokenStorage();

  String _codeVerifier() {
    final r = Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _codeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Opens the system browser at the OAuth authorize endpoint.
  /// Returns the PKCE verifier so the caller (via deep link) can hand it
  /// to the backend exchange. The backend URL is configured by the
  /// deployer, not hard-coded here.
  Future<String> startOAuthLogin({
    required String clientId,
    required String redirectUri,
  }) async {
    final verifier = _codeVerifier();
    final uri = Uri.parse(authorizeBase).replace(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'code_challenge': _codeChallenge(verifier),
      'code_challenge_method': 'S256',
      'state': base64Url.encode(
          List<int>.generate(16, (_) => Random.secure().nextInt(256))),
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open the Supabase login page');
    }
    return verifier;
  }

  // TODO(oauth-backend): implement exchangeAuthorizationCode() against
  // YOUR backend (POST /oauth/exchange {code, code_verifier,
  // redirect_uri}) which holds client_secret and returns only the
  // scoped access + refresh tokens. Do NOT add client_secret here.

  /// PAT-paste fallback. Validates the token with GET /v1/profile
  /// (user-scoped tokens only — a project/org-scoped sbp_fc token
  /// returns 403 here; that is expected, see report §1.2).
  Future<void> connectWithPat(String pat) async {
    final token = pat.trim();
    if (token.isEmpty) throw Exception('Paste a Personal Access Token first.');
    await _store.saveManagementToken(token);
  }

  Future<void> signOut() => _store.clearManagementToken();
}
