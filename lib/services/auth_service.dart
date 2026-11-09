import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_mobile/services/secure_token_storage.dart';

/// Cloud-account auth — REAL OAuth 2.0 login, end to end.
/// Flow (Supabase Platform OAuth docs, verified 2026-11-09):
///  1. App builds the authorize URL (PKCE S256) and opens the SYSTEM
///     BROWSER at https://api.supabase.com/v1/oauth/authorize — the
///     user signs in with GitHub / Google / email on supabase.com.
///     There is NO password API; the app never sees the password.
///  2. Supabase redirects to com.novaworks.supabase_mobile://oauth/callback
///     with ?code=…&state=… — the OS hands the link back to the app
///     (Android intent-filter + iOS URL scheme, see android/ + ios/).
///  3. The app exchanges the code DIRECTLY at POST
///     https://api.supabase.com/v1/oauth/token (form-urlencoded,
///     grant_type=authorization_code, code, redirect_uri, code_verifier,
///     client_id in the body — public-client PKCE, no secret in the app).
///     If Supabase rejects that with invalid_client, the exchange must
///     go through the token-exchange proxy instead (see
///     workspace/supabase-mobile/oauth-proxy/proxy.dart) — the proxy
///     holds client_secret in its own environment, never in this app.
///  4. Access + refresh tokens live ONLY in secure storage.
/// PAT-paste remains as the fallback (dashboard Access Tokens page).
class AuthService {
  static const authorizeBase =
      'https://api.supabase.com/v1/oauth/authorize';
  static const tokenUrl = 'https://api.supabase.com/v1/oauth/token';
  static const revokeUrl = 'https://api.supabase.com/v1/oauth/revoke';

  /// Redirect URI registered on the Supabase OAuth app. Must match
  /// exactly on authorize + token calls and in the OAuth app settings.
  static const redirectUri =
      'com.novaworks.supabase_mobile://oauth/callback';

  /// The OAuth app's client ID (PUBLIC value — safe to ship). Filled in
  /// once the "Supabase Mobile" OAuth app is registered on the
  /// Supabase dashboard; until then the Auth screen lets the user paste
  /// it (stored in secure storage, see SecureTokenStorage).
  static const bundledClientId = '';

  final _store = SecureTokenStorage();
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  String _randomBase64Url(int bytes) {
    final r = Random.secure();
    return base64Url
        .encode(List<int>.generate(bytes, (_) => r.nextInt(256)))
        .replaceAll('=', '');
  }

  String _codeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  Future<String> getClientId() async {
    final stored = await _store.readOAuthClientId();
    if (stored != null && stored.isNotEmpty) return stored;
    return bundledClientId;
  }

  /// Step 1 — open the real Supabase login page in the system browser.
  /// Saves the PKCE verifier + state first (the OS may kill the app
  /// while the user signs in). Throws if no OAuth client ID is set.
  Future<void> startOAuthLogin() async {
    final clientId = await getClientId();
    if (clientId.isEmpty) {
      throw Exception(
          'No OAuth client ID yet — register the "Supabase Mobile" OAuth app on the Supabase dashboard and paste its client ID below.');
    }
    final verifier = _randomBase64Url(32);
    final state = _randomBase64Url(16);
    await _store.saveOAuthRoundTrip(state: state, verifier: verifier);
    final uri = Uri.parse(authorizeBase).replace(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'code_challenge': _codeChallenge(verifier),
      'code_challenge_method': 'S256',
      'state': state,
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open the Supabase login page');
    }
  }

  /// Step 3 — exchange the authorization code for tokens, DIRECTLY at
  /// Supabase's token endpoint (public-client PKCE, no secret in app).
  /// Returns true on success. Throws a plain-language error otherwise;
  /// an invalid_client error means Supabase demands the secret, i.e.
  /// the proxy backend is required (see oauth-proxy/).
  Future<bool> exchangeAuthorizationCode({
    required String code,
    required String verifier,
    required String clientId,
  }) async {
    try {
      final r = await _dio.post(tokenUrl,
          data: {
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': redirectUri,
            'code_verifier': verifier,
            'client_id': clientId,
          },
          options: Options(
              contentType: Headers.formUrlEncodedContentType));
      final data = r.data as Map<String, dynamic>;
      final access = data['access_token'] as String?;
      if (access == null || access.isEmpty) {
        throw Exception('Token exchange returned no access token.');
      }
      await _store.saveManagementToken(access);
      final refresh = data['refresh_token'] as String?;
      if (refresh != null && refresh.isNotEmpty) {
        await _store.saveRefreshToken(refresh);
      }
      return true;
    } on DioException catch (e) {
      final err = e.response?.data is Map
          ? (e.response?.data as Map)['error']?.toString()
          : null;
      if (err == 'invalid_client') {
        throw Exception(
            'Supabase refused the direct code exchange (invalid_client) — the token exchange needs the client secret, so the OAuth proxy backend is required. The proxy code is ready (oauth-proxy/); it needs hosting + the secret in its own environment.');
      }
      throw Exception('Login failed at the token exchange: '
          '${err ?? e.message ?? e.response?.statusCode}');
    }
  }

  /// Step 2+3 — handle the deep link Supabase redirected to.
  /// Returns true if this URI was our OAuth callback (handled or failed
  /// with an exception), false if it is some other link.
  Future<bool> handleOAuthCallback(Uri uri) async {
    if (uri.scheme != 'com.novaworks.supabase_mobile' ||
        uri.host != 'oauth' ||
        uri.path != '/callback') {
      return false;
    }
    final error = uri.queryParameters['error'];
    if (error != null) {
      throw Exception('Supabase login failed: $error');
    }
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || state == null) {
      throw Exception('Login callback is missing the authorization code.');
    }
    final savedState = await _store.readOAuthState();
    final verifier = await _store.readOAuthVerifier();
    if (savedState == null || verifier == null || savedState != state) {
      throw Exception(
          'Login state mismatch — the sign-in was started somewhere else. Please try again.');
    }
    final clientId = await getClientId();
    await _store.clearOAuthRoundTrip();
    await exchangeAuthorizationCode(
        code: code, verifier: verifier, clientId: clientId);
    return true;
  }

  /// Refresh the Management API token using the saved refresh token.
  Future<bool> refreshManagementToken() async {
    final refresh = await _store.readRefreshToken();
    final clientId = await getClientId();
    if (refresh == null || refresh.isEmpty || clientId.isEmpty) return false;
    try {
      final r = await _dio.post(tokenUrl,
          data: {
            'grant_type': 'refresh_token',
            'refresh_token': refresh,
            'client_id': clientId,
          },
          options: Options(
              contentType: Headers.formUrlEncodedContentType));
      final data = r.data as Map<String, dynamic>;
      final access = data['access_token'] as String?;
      if (access == null || access.isEmpty) return false;
      await _store.saveManagementToken(access);
      final next = data['refresh_token'] as String?;
      if (next != null && next.isNotEmpty) {
        await _store.saveRefreshToken(next);
      }
      return true;
    } on DioException {
      return false;
    }
  }

  /// Revoke the token server-side, then clear local credentials.
  Future<void> revokeAndSignOut() async {
    final token = await _store.readManagementToken();
    if (token != null && token.isNotEmpty) {
      try {
        await _dio.post(revokeUrl,
            data: {'token': token},
            options: Options(
                contentType: Headers.formUrlEncodedContentType));
      } on DioException {
        // Revoke is best-effort; local sign-out still happens.
      }
    }
    await signOut();
  }

  /// PAT-paste fallback. Validates nothing here — the first live call
  /// will surface a bad token as a real error, never a fake success.
  Future<void> connectWithPat(String pat) async {
    final token = pat.trim();
    if (token.isEmpty) throw Exception('Paste a Personal Access Token first.');
    await _store.saveManagementToken(token);
  }

  Future<void> signOut() => _store.clearManagementToken();
}
