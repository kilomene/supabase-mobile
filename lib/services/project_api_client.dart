import 'package:dio/dio.dart';
import 'package:supabase_mobile/models/models.dart';

/// Project APIs — https://<ref>.supabase.co
/// Auth: apikey: <publishable|secret> header (+ user JWT where noted).
/// Secret key = service_role, bypasses RLS — only ever user-pasted and
/// stored in secure storage; Auth Admin returns 401 on publishable.
class ProjectApiClient {
  final String ref;
  final String publishableKey;
  final String? secretKey;
  late final Dio _dio;
  ProjectApiClient({required this.ref, required this.publishableKey, this.secretKey}) {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://$ref.supabase.co',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'apikey': publishableKey},
    ));
  }

  Map<String, String> get _adminHeaders => {
        'apikey': secretKey ?? publishableKey,
        'Authorization': 'Bearer ${secretKey ?? publishableKey}',
      };

  // --- PostgREST: /rest/v1/{table} ---
  Future<List<Map<String, dynamic>>> selectRows(
    String table, {
    String select = '*',
    int limit = 100,
    int offset = 0,
    Map<String, String>? filters,
  }) async {
    final qp = <String, dynamic>{
      'select': select,
      'limit': '$limit',
      'offset': '$offset',
      ...?filters,
    };
    final r = await _dio.get('/rest/v1/$table', queryParameters: qp);
    return (r.data as List).whereType<Map<String, dynamic>>().toList();
  }

  Future<List<Map<String, dynamic>>> insertRows(
          String table, List<Map<String, dynamic>> rows) async =>
      _postRest(table, rows, 'POST');
  Future<List<Map<String, dynamic>>> _postRest(
      String table, Object body, String method) async {
    final r = await _dio.request('/rest/v1/$table',
        data: body,
        options: Options(
            method: method,
            headers: {'Prefer': 'return=representation'}));
    final d = r.data;
    return d is List ? d.whereType<Map<String, dynamic>>().toList() : const [];
  }

  Future<void> updateRows(String table, Map<String, String> filter,
      Map<String, dynamic> patch) async {
    await _dio.patch('/rest/v1/$table',
        queryParameters: filter, data: patch);
  }

  Future<void> deleteRows(String table, Map<String, String> filter) async {
    await _dio.delete('/rest/v1/$table', queryParameters: filter);
  }

  Future<dynamic> rpc(String fn, Map<String, dynamic> params) async {
    final r = await _dio.post('/rest/v1/rpc/$fn', data: params);
    return r.data;
  }

  // --- Auth Admin (GoTrue): secret key ONLY ---
  void _requireSecret() {
    if (secretKey == null || secretKey!.isEmpty) {
      throw Exception(
          'Auth Admin needs the project secret key (service_role). Add it in Settings — it stays on this device only.');
    }
  }

  Future<List<AuthUser>> listAuthUsers({int page = 1, int perPage = 50}) async {
    _requireSecret();
    final r = await _dio.get('/auth/v1/admin/users',
        queryParameters: {'page': '$page', 'per_page': '$perPage'},
        options: Options(headers: _adminHeaders));
    final users = (r.data['users'] as List?) ?? (r.data as List? ?? const []);
    return users.whereType<Map<String, dynamic>>().map(AuthUser.fromJson).toList();
  }

  Future<AuthUser> createAuthUser(String email,
      {String? password, bool emailConfirm = true}) async {
    _requireSecret();
    final r = await _dio.post('/auth/v1/admin/users',
        data: {'email': email, 'password': password, 'email_confirm': emailConfirm},
        options: Options(headers: _adminHeaders));
    return AuthUser.fromJson(r.data);
  }

  Future<void> deleteAuthUser(String id) async {
    _requireSecret();
    await _dio.delete('/auth/v1/admin/users/$id',
        options: Options(headers: _adminHeaders));
  }

  Future<void> inviteAuthUser(String email) async {
    _requireSecret();
    await _dio.post('/auth/v1/admin/invite',
        data: {'email': email}, options: Options(headers: _adminHeaders));
  }

  Future<List<Map<String, dynamic>>> listUserFactors(String userId) async {
    _requireSecret();
    final r = await _dio.get('/auth/v1/admin/users/$userId/factors',
        options: Options(headers: _adminHeaders));
    return (r.data as List).whereType<Map<String, dynamic>>().toList();
  }

  // --- Storage: /storage/v1/ ---
  Future<List<StorageBucket>> listBuckets() async {
    final r = await _dio.get('/storage/v1/bucket');
    return (r.data as List).map((e) => StorageBucket.fromJson(e)).toList();
  }

  Future<void> createBucket(String id, {bool isPublic = false}) async {
    await _dio.post('/storage/v1/bucket',
        data: {'id': id, 'name': id, 'public': isPublic});
  }

  Future<List<StorageObject>> listObjects(String bucket,
      {String prefix = ''}) async {
    final r = await _dio.post('/storage/v1/object/list/$bucket',
        data: {'prefix': prefix, 'limit': 100, 'offset': 0});
    return (r.data as List).map((e) => StorageObject.fromJson(e)).toList();
  }

  Future<String> createSignedUrl(String bucket, String path,
      {int expiresIn = 3600}) async {
    final r = await _dio.post('/storage/v1/object/sign/$bucket/$path',
        data: {'expiresIn': expiresIn});
    return '${r.data['signedURL'] ?? ''}';
  }

  // Upload: multipart via Dio (<=6 MB standard; >6 MB use TUS resumable
  // POST /storage/v1/upload/resumable — verify path at build, report §3.4).
  Future<void> uploadObject(String bucket, String path, List<int> bytes,
      {String contentType = 'application/octet-stream'}) async {
    await _dio.post('/storage/v1/object/$bucket/$path',
        data: bytes,
        options: Options(
            headers: {'Content-Type': contentType, 'x-upsert': 'true'}));
  }

  Future<void> deleteObjects(String bucket, List<String> prefixes) async {
    await _dio.delete('/storage/v1/object/$bucket',
        data: {'prefixes': prefixes});
  }

  // --- Edge Functions invoke (project host, never Management) ---
  Future<dynamic> invokeFunction(String slug, [Object? body]) async {
    final r = await _dio.post('/functions/v1/$slug', data: body);
    return r.data;
  }

  // --- GraphQL ---
  Future<dynamic> graphql(String query) async {
    final r = await _dio.post('/graphql/v1', data: {'query': query});
    return r.data;
  }
}
