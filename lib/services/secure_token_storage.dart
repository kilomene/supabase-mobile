import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// All credentials live ONLY in the OS secure store
/// (iOS Keychain / Android Keystore). Nothing is written to
/// SharedPreferences, files, logs or the repo.
/// Keys: management PAT/OAuth token, per-project publishable + secret keys.
/// The secret key bypasses RLS — it is user-pasted, per project, with an
/// explicit warning in the UI, and never hard-coded or logged.
class SecureTokenStorage {
  static const _storage = FlutterSecureStorage();
  static const _mgmtToken = 'mgmt_token';
  static const _mgmtRefresh = 'mgmt_refresh_token';

  Future<void> saveManagementToken(String token) =>
      _storage.write(key: _mgmtToken, value: token);
  Future<String?> readManagementToken() => _storage.read(key: _mgmtToken);
  Future<bool> hasManagementToken() async =>
      (await readManagementToken())?.isNotEmpty ?? false;
  Future<void> clearManagementToken() async {
    await _storage.delete(key: _mgmtToken);
    await _storage.delete(key: _mgmtRefresh);
  }

  Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _mgmtRefresh, value: token);
  Future<String?> readRefreshToken() => _storage.read(key: _mgmtRefresh);

  // --- OAuth login round-trip (PKCE verifier + state) ---
  // Saved BEFORE the system browser opens (the OS may kill the app
  // while the user signs in); read back when the deep link returns.
  static const _oauthState = 'oauth_state';
  static const _oauthVerifier = 'oauth_verifier';
  static const _oauthClientId = 'oauth_client_id';

  Future<void> saveOAuthRoundTrip(
          {required String state, required String verifier}) async {
    await _storage.write(key: _oauthState, value: state);
    await _storage.write(key: _oauthVerifier, value: verifier);
  }

  Future<String?> readOAuthState() => _storage.read(key: _oauthState);
  Future<String?> readOAuthVerifier() => _storage.read(key: _oauthVerifier);
  Future<void> clearOAuthRoundTrip() async {
    await _storage.delete(key: _oauthState);
    await _storage.delete(key: _oauthVerifier);
  }

  /// The OAuth app's client ID (public value, not a secret). Stored here
  /// so it can be pasted in the app until it is bundled as a constant.
  Future<void> saveOAuthClientId(String id) =>
      _storage.write(key: _oauthClientId, value: id);
  Future<String?> readOAuthClientId() => _storage.read(key: _oauthClientId);

  Future<void> saveProjectKeys({
    required String ref,
    required String publishableKey,
    String? secretKey,
  }) async {
    await _storage.write(key: 'proj_${ref}_publishable', value: publishableKey);
    if (secretKey != null && secretKey.isNotEmpty) {
      await _storage.write(key: 'proj_${ref}_secret', value: secretKey);
    }
  }

  Future<String?> readProjectPublishable(String ref) =>
      _storage.read(key: 'proj_${ref}_publishable');
  Future<String?> readProjectSecret(String ref) =>
      _storage.read(key: 'proj_${ref}_secret');
  Future<void> clearProjectKeys(String ref) async {
    await _storage.delete(key: 'proj_${ref}_publishable');
    await _storage.delete(key: 'proj_${ref}_secret');
  }
}
