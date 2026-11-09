import 'package:dio/dio.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/secure_token_storage.dart';

/// Management API — https://api.supabase.com/v1 (+ v2 where noted).
/// Auth: Authorization: Bearer <PAT | OAuth token>.
/// Live spec: https://api.supabase.com/api/v1-json (115 paths / 170 ops)
/// and /api/v2-json. Rate limit 120/min (logs/usage 30/min).
/// Endpoints NOT in the live spec are not called here.
class ManagementApiClient {
  static const _v1 = 'https://api.supabase.com/v1';
  static const _v2 = 'https://api.supabase.com/v2';
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  final _store = SecureTokenStorage();

  Future<Dio> _authed() async {
    final token = await _store.readManagementToken();
    if (token == null || token.isEmpty) {
      throw Exception('Not connected — add a Personal Access Token or sign in with OAuth first.');
    }
    _dio.options.headers['Authorization'] = 'Bearer $token';
    return _dio;
  }

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        throw Exception('Rate limited (120/min, 30/min for logs/usage). Try again shortly.');
      }
      if (e.response?.statusCode == 410) {
        throw Exception('That endpoint was removed by Supabase (410). See the endpoint plan.');
      }
      if (e.response?.statusCode == 403) {
        throw Exception('Forbidden — your token lacks this permission: ${e.response?.data}');
      }
      if (e.response?.statusCode == 401) {
        throw Exception('Unauthorized — your token is invalid or expired.');
      }
      rethrow;
    }
  }

  // --- Profile / organisations ---
  Future<List<Organization>> listOrganizations() => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/organizations');
        return (r.data as List).map((e) => Organization.fromJson(e)).toList();
      });

  // --- Projects ---
  Future<List<SupabaseProject>> listProjects() => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects');
        return (r.data as List).map((e) => SupabaseProject.fromJson(e)).toList();
      });

  Future<List<SupabaseProject>> listOrgProjectsV2(String slug) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v2/organizations/$slug/projects');
        final data = r.data is Map ? r.data['data'] ?? r.data['projects'] : r.data;
        return (data as List).map((e) => SupabaseProject.fromJson(e)).toList();
      });

  Future<SupabaseProject> getProject(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref');
        return SupabaseProject.fromJson(r.data);
      });

  Future<SupabaseProject> createProject({
    required String name,
    required String organizationSlug,
    required String dbPass,
    required String region,
  }) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post('$_v1/projects', data: {
          'name': name,
          'organization_slug': organizationSlug,
          'db_pass': dbPass, // required, never retrievable later
          'region': region,
        });
        return SupabaseProject.fromJson(r.data);
      });

  Future<void> pauseProject(String ref) => _guard(() async {
        final d = await _authed();
        await d.post('$_v1/projects/$ref/pause');
      });
  Future<void> restoreProject(String ref) => _guard(() async {
        final d = await _authed();
        await d.post('$_v1/projects/$ref/restore');
      });
  Future<void> restartProject(String ref) => _guard(() async {
        final d = await _authed();
        await d.post('$_v1/projects/$ref/restart');
      });
  Future<void> deleteProject(String ref) => _guard(() async {
        final d = await _authed();
        await d.delete('$_v1/projects/$ref');
      });
  Future<String> projectHealth(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/health');
        return '${r.data}';
      });

  Future<List<String>> availableRegions() => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/available-regions');
        return (r.data as List).map((e) => '$e').toList();
      });

  // --- API keys ---
  Future<List<ApiKeyItem>> listApiKeys(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/api-keys');
        return (r.data as List).map((e) => ApiKeyItem.fromJson(e)).toList();
      });

  // --- SQL (the SQL Editor backend, Beta) ---
  Future<SqlResult> runQuery(String ref, String query,
      {bool readOnly = false}) =>
      _guard(() async {
        final d = await _authed();
        final path = readOnly
            ? '$_v1/projects/$ref/database/query/read-only'
            : '$_v1/projects/$ref/database/query';
        final r = await d.post(path, data: {'query': query});
        return SqlResult.fromJson(r.data);
      });

  Future<List<Map<String, dynamic>>> databaseMetadata(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/database/metadata');
        final data = r.data;
        if (data is List) return data.whereType<Map<String, dynamic>>().toList();
        return const [];
      });

  // --- Usage / logs (30/min) ---
  Future<Map<String, dynamic>> usageCounts(String ref,
      {String interval = '1day'}) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get(
            '$_v1/projects/$ref/analytics/endpoints/usage.api-counts',
            queryParameters: {'interval': interval});
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<List<LogEvent>> queryLogs(String ref, String sql) => _guard(() async {
        final d = await _authed();
        // NOTE: legacy logs.all was removed 2026-09-23 (410). Use the
        // ClickHouse endpoint, GET-only, <=24h window, filter `source`.
        final r = await d.get(
          '$_v1/projects/$ref/analytics/endpoints/logs',
          queryParameters: {'sql': sql},
        );
        final data = r.data is Map ? r.data['data'] : r.data;
        if (data is List) {
          return data
              .whereType<Map<String, dynamic>>()
              .map(LogEvent.fromJson)
              .toList();
        }
        return const [];
      });

  // --- Logs: drains (ingestion sinks) + egress/usage counts ---
  // Log Explorer itself is queryLogs() above (ClickHouse, <=24h).
  // Drains forward logs to an external sink; the app lists them but
  // cannot retroactively fetch logs older than 24h.
  Future<List<Map<String, dynamic>>> listLogDrains(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/analytics/log-drains');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  Future<int> apiRequestsCount(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get(
            '$_v1/projects/$ref/analytics/endpoints/usage.api-requests-count');
        final data = r.data;
        if (data is Map) return (data['count'] as num?)?.toInt() ?? 0;
        return 0;
      });

  // --- Edge Functions (Management) ---
  Future<List<EdgeFunction>> listFunctions(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/functions');
        return (r.data as List).map((e) => EdgeFunction.fromJson(e)).toList();
      });

  Future<void> deleteFunction(String ref, String slug) => _guard(() async {
        final d = await _authed();
        await d.delete('$_v1/projects/$ref/functions/$slug');
      });
  // NOTE: deploy is multipart (POST .../functions/deploy?slug=) with
  // server-side bundling — no Deno/esbuild on-device. See README.
  // NOTE: there is NO rollback endpoint — redeploy previous source.

  Future<List<Map<String, dynamic>>> listSecrets(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/secrets');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  // --- Branches ---
  Future<List<Map<String, dynamic>>> listBranches(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/branches');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  // --- Backups — DISPUTED (report §4 #9) ---
  // PAT table lists download/restore; a third-party guide says
  // dashboard-only. These methods call the PAT-table endpoints; if they
  // 404/402 on a Pro project, surface as dashboard-only, do not fake.
  Future<List<Map<String, dynamic>>> listBackups(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/database/backups');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  Future<void> restoreBackup(String ref, String backupId) => _guard(() async {
        final d = await _authed();
        await d.post('$_v1/projects/$ref/database/backups/restore',
            data: {'id': backupId});
      });

  // --- Billing addons (NOT invoices — no invoice endpoint exists) ---
  Future<Map<String, dynamic>> billingAddons(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/billing/addons');
        return Map<String, dynamic>.from(r.data as Map);
      });

  // --- Advisors / config ---
  Future<Map<String, dynamic>> projectConfigV2(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v2/projects/$ref/config');
        return Map<String, dynamic>.from(r.data as Map);
      });
  Future<List<Map<String, dynamic>>> securityAdvisors(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/advisors/security');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });
}
