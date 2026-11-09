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
