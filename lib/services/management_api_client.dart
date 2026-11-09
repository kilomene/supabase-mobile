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
        // /health REQUIRES the services query param (live OpenAPI:
        // services is required). Calling it bare returns 400 — that
        // was the Dashboard 400 in the 2026-11-10 screenshot.
        final r = await d.get('$_v1/projects/$ref/health',
            queryParameters: {
              'services':
                  'auth,db,db_postgres_user,pooler,realtime,rest,storage,pg_bouncer',
            });
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
        // ClickHouse endpoint, GET-only, <=24h window.
        // ClickHouse tables are PER SOURCE (postgres_logs, edge_logs,
        // auth_logs, storage_logs, realtime_logs) — the live OpenAPI
        // example queries `from edge_logs`. There is no single `logs`
        // table; `FROM logs WHERE source=...` returns 400. Callers
        // must pass the per-source table. Pass explicit ISO bounds
        // for the 24h window (documented params).
        final end = DateTime.now().toUtc();
        final start = end.subtract(const Duration(hours: 24));
        final r = await d.get(
          '$_v1/projects/$ref/analytics/endpoints/logs',
          queryParameters: {
            'sql': sql,
            'iso_timestamp_start': start.toIso8601String(),
            'iso_timestamp_end': end.toIso8601String(),
          },
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

  // --- Logs: drains (v2 — the v1 path is NOT in the live spec) ---
  // Log Explorer itself is queryLogs() above (ClickHouse, <=24h).
  // Drains forward logs to an external sink; the app lists them but
  // cannot retroactively fetch logs older than 24h.
  Future<List<Map<String, dynamic>>> listLogDrains(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v2/projects/$ref/analytics/log-drains');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  Future<Map<String, dynamic>> createLogDrain(
          String ref, Map<String, dynamic> data) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post('$_v2/projects/$ref/analytics/log-drains',
            data: data);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updateLogDrain(
          String ref, String id, Map<String, dynamic> data) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.put(
            '$_v2/projects/$ref/analytics/log-drains/$id',
            data: data);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<void> deleteLogDrain(String ref, String id) => _guard(() async {
        final d = await _authed();
        await d.delete('$_v2/projects/$ref/analytics/log-drains/$id');
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

  Future<List<Map<String, dynamic>>> performanceAdvisors(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/advisors/performance');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });
  // NOTE: no POST .../advisors/run in the live v1 spec — advisors are
  // read-only here. The report table's /advisors/run is not wired.

  // --- Organizations: create / get / members ---
  // Live spec: POST /v1/organizations {name}; GET /v1/organizations/{slug};
  // GET /v1/organizations/{slug}/members (list only — no invite/remove
  // in the live spec, so members are read-only here).
  Future<Organization> createOrganization({required String name}) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post('$_v1/organizations', data: {'name': name});
        return Organization.fromJson(r.data);
      });

  Future<Map<String, dynamic>> getOrganization(String slug) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/organizations/$slug');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<List<Map<String, dynamic>>> listOrgMembers(String slug) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/organizations/$slug/members');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  // --- Auth config (providers, SMTP, MFA, URLs, templates) ---
  Future<Map<String, dynamic>> getAuthConfig(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/config/auth');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updateAuthConfig(
          String ref, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.patch('$_v1/projects/$ref/config/auth', data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  // --- Auth SSO providers / signing keys / third-party auth ---
  Future<List<Map<String, dynamic>>> listSsoProviders(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r =
            await d.get('$_v1/projects/$ref/config/auth/sso/providers');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  Future<Map<String, dynamic>> createSsoProvider(
          String ref, Map<String, dynamic> data) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post(
            '$_v1/projects/$ref/config/auth/sso/providers',
            data: data);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updateSsoProvider(
          String ref, String providerId, Map<String, dynamic> data) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.put(
            '$_v1/projects/$ref/config/auth/sso/providers/$providerId',
            data: data);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<void> deleteSsoProvider(String ref, String providerId) =>
      _guard(() async {
        final d = await _authed();
        await d.delete(
            '$_v1/projects/$ref/config/auth/sso/providers/$providerId');
      });

  Future<List<Map<String, dynamic>>> listSigningKeys(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r =
            await d.get('$_v1/projects/$ref/config/auth/signing-keys');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  Future<Map<String, dynamic>> createSigningKey(
          String ref, Map<String, dynamic> data) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post(
            '$_v1/projects/$ref/config/auth/signing-keys',
            data: data);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<void> deleteSigningKey(String ref, String id) => _guard(() async {
        final d = await _authed();
        await d.delete('$_v1/projects/$ref/config/auth/signing-keys/$id');
      });

  Future<List<Map<String, dynamic>>> listThirdPartyAuth(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d
            .get('$_v1/projects/$ref/config/auth/third-party-auth');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  Future<Map<String, dynamic>> createThirdPartyAuth(
          String ref, Map<String, dynamic> data) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post(
            '$_v1/projects/$ref/config/auth/third-party-auth',
            data: data);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<void> deleteThirdPartyAuth(String ref, String tpaId) =>
      _guard(() async {
        final d = await _authed();
        await d.delete(
            '$_v1/projects/$ref/config/auth/third-party-auth/$tpaId');
      });

  // --- PostgREST / Storage / Realtime config ---
  Future<Map<String, dynamic>> getPostgrestConfig(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/postgrest');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updatePostgrestConfig(
          String ref, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.patch('$_v1/projects/$ref/postgrest', data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> getStorageConfig(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/config/storage');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updateStorageConfig(
          String ref, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.patch('$_v1/projects/$ref/config/storage',
            data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> getRealtimeConfig(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/config/realtime');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updateRealtimeConfig(
          String ref, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.patch('$_v1/projects/$ref/config/realtime',
            data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<void> shutdownRealtime(String ref) => _guard(() async {
        final d = await _authed();
        await d.post('$_v1/projects/$ref/config/realtime/shutdown');
      });

  // --- Network restrictions / bans, SSL, pgsodium ---
  Future<Map<String, dynamic>> getNetworkRestrictions(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/network-restrictions');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updateNetworkRestrictions(
          String ref, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.patch('$_v1/projects/$ref/network-restrictions',
            data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<List<Map<String, dynamic>>> listNetworkBans(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r =
            await d.post('$_v1/projects/$ref/network-bans/retrieve');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  Future<void> deleteNetworkBan(
          String ref, List<String> ipv4Addresses) =>
      _guard(() async {
        final d = await _authed();
        await d.delete('$_v1/projects/$ref/network-bans',
            data: {'ipv4_addresses': ipv4Addresses});
      });

  Future<Map<String, dynamic>> getSslEnforcement(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/ssl-enforcement');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updateSslEnforcement(
          String ref, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.put('$_v1/projects/$ref/ssl-enforcement',
            data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> getPgsodium(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/pgsodium');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updatePgsodium(
          String ref, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r =
            await d.put('$_v1/projects/$ref/pgsodium', data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  // --- Custom hostname / vanity subdomain ---
  Future<Map<String, dynamic>> getCustomHostname(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/custom-hostname');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> initCustomHostname(
          String ref, Map<String, dynamic> data) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post(
            '$_v1/projects/$ref/custom-hostname/initialize',
            data: data);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updateCustomHostname(
          String ref, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.patch('$_v1/projects/$ref/custom-hostname',
            data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<void> activateCustomHostname(String ref) => _guard(() async {
        final d = await _authed();
        await d.post('$_v1/projects/$ref/custom-hostname/activate');
      });

  Future<void> reverifyCustomHostname(String ref) => _guard(() async {
        final d = await _authed();
        await d.post('$_v1/projects/$ref/custom-hostname/reverify');
      });

  Future<void> deleteCustomHostname(String ref) => _guard(() async {
        final d = await _authed();
        await d.delete('$_v1/projects/$ref/custom-hostname');
      });

  Future<Map<String, dynamic>> getVanitySubdomain(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/vanity-subdomain');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> checkVanityAvailability(
          String ref, String subdomain) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post(
            '$_v1/projects/$ref/vanity-subdomain/check-availability',
            data: {'subdomain': subdomain});
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> activateVanitySubdomain(
          String ref, Map<String, dynamic> data) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post(
            '$_v1/projects/$ref/vanity-subdomain/activate',
            data: data);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<void> deleteVanitySubdomain(String ref) => _guard(() async {
        final d = await _authed();
        await d.delete('$_v1/projects/$ref/vanity-subdomain');
      });

  // --- DB password (PATCH only per live spec — never retrievable) ---
  Future<void> setDbPassword(String ref, String password) =>
      _guard(() async {
        final d = await _authed();
        await d.patch('$_v1/projects/$ref/database/password',
            data: {'password': password});
      });

  // --- SQL snippets (account-wide) ---
  Future<List<Map<String, dynamic>>> listSnippets() => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/snippets');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  Future<Map<String, dynamic>> getSnippet(String id) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/snippets/$id');
        return Map<String, dynamic>.from(r.data as Map);
      });

  // --- Migrations ---
  Future<List<Map<String, dynamic>>> listMigrations(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/database/migrations');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  Future<Map<String, dynamic>> createMigration(String ref,
          {required String query, String? name, String? rollback}) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post(
            '$_v1/projects/$ref/database/migrations',
            data: {
              'query': query,
              if (name != null) 'name': name,
              if (rollback != null) 'rollback': rollback,
            });
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> getMigration(String ref, String version) =>
      _guard(() async {
        final d = await _authed();
        final r = await d
            .get('$_v1/projects/$ref/database/migrations/$version');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updateMigration(String ref, String version,
          Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.patch(
            '$_v1/projects/$ref/database/migrations/$version',
            data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  // --- DB types / config / pooler / disk ---
  // TS types live at /types/typescript (the report's /database/types
  // is NOT in the live spec). Returns plain text.
  Future<String> getTypescriptTypes(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/types/typescript',
            options: Options(responseType: ResponseType.plain));
        return '${r.data}';
      });

  Future<Map<String, dynamic>> getDbPostgresConfig(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/config/database/postgres');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updateDbPostgresConfig(
          String ref, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.patch(
            '$_v1/projects/$ref/config/database/postgres',
            data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> getPoolerConfig(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/config/database/pooler');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updatePoolerConfig(
          String ref, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.patch(
            '$_v1/projects/$ref/config/database/pooler',
            data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> getPgbouncerConfig(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d
            .get('$_v1/projects/$ref/config/database/pgbouncer');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> getDiskConfig(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/config/disk');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updateDiskConfig(
          String ref, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post('$_v1/projects/$ref/config/disk', data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> getDiskAutoscale(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/config/disk/autoscale');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> getDiskUtil(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/config/disk/util');
        return Map<String, dynamic>.from(r.data as Map);
      });

  // --- JIT access (DB) ---
  Future<List<Map<String, dynamic>>> listJitUsers(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/database/jit/list');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  Future<Map<String, dynamic>> inviteJitUser(
          String ref, Map<String, dynamic> data) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post('$_v1/projects/$ref/database/jit/invite',
            data: data);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> acceptJitInvite(
          String ref, Map<String, dynamic> data) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post(
            '$_v1/projects/$ref/database/jit/invite/accept',
            data: data);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<void> deleteJitInvite(String ref, String inviteId) =>
      _guard(() async {
        final d = await _authed();
        await d.delete(
            '$_v1/projects/$ref/database/jit/invite/$inviteId');
      });

  Future<void> removeJitUser(String ref, String userId) => _guard(() async {
        final d = await _authed();
        await d.delete('$_v1/projects/$ref/database/jit/$userId');
      });

  // --- Postgres upgrade / read replicas ---
  Future<Map<String, dynamic>> upgradeEligibility(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/upgrade/eligibility');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> upgradeStatus(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/upgrade/status');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> startUpgrade(String ref) => _guard(() async {
        final d = await _authed();
        final r = await d.post('$_v1/projects/$ref/upgrade');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> setupReadReplica(
          String ref, String region) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post('$_v1/projects/$ref/read-replicas/setup',
            data: {'read_replica_region': region});
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> removeReadReplica(
          String ref, Map<String, dynamic> data) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post('$_v1/projects/$ref/read-replicas/remove',
            data: data);
        return Map<String, dynamic>.from(r.data as Map);
      });

  // --- Backups: schedule / PITR / restore point / undo ---
  Future<Map<String, dynamic>> getBackupSchedule(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/database/backups/schedule');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updateBackupSchedule(
          String ref, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.patch(
            '$_v1/projects/$ref/database/backups/schedule',
            data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<void> restorePitr(String ref, int recoveryTimeTargetUnix) =>
      _guard(() async {
        final d = await _authed();
        await d.post('$_v1/projects/$ref/database/backups/restore-pitr',
            data: {'recovery_time_target_unix': recoveryTimeTargetUnix});
      });

  Future<Map<String, dynamic>> getRestorePoint(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d
            .get('$_v1/projects/$ref/database/backups/restore-point');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> createRestorePoint(
          String ref, Map<String, dynamic> data) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post(
            '$_v1/projects/$ref/database/backups/restore-point',
            data: data);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<void> undoRestore(String ref) => _guard(() async {
        final d = await _authed();
        await d.post('$_v1/projects/$ref/database/backups/undo');
      });

  // --- Edge Functions: get / body / update / deploy ---
  Future<Map<String, dynamic>> getFunction(String ref, String slug) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/functions/$slug');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<String> getFunctionBody(String ref, String slug) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/functions/$slug/body',
            options: Options(responseType: ResponseType.plain));
        return '${r.data}';
      });

  Future<Map<String, dynamic>> updateFunction(
          String ref, String slug, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.patch('$_v1/projects/$ref/functions/$slug',
            data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  /// Deploy (or create) a function from source text. Multipart
  /// POST .../functions/deploy?slug= with server-side bundling;
  /// no Deno/esbuild on-device. No rollback endpoint — redeploy.
  Future<Map<String, dynamic>> deployFunction(
          String ref, String slug, String code) =>
      _guard(() async {
        final d = await _authed();
        final form = FormData.fromMap({
          'file': MultipartFile.fromString(code, filename: 'index.ts'),
        });
        final r = await d.post(
            '$_v1/projects/$ref/functions/deploy?slug=$slug',
            data: form);
        final data = r.data;
        if (data is Map) return Map<String, dynamic>.from(data);
        return {'result': '$data'};
      });

  // --- Function secrets: create / delete (POST/DELETE /secrets) ---
  Future<void> createSecrets(
          String ref, List<Map<String, dynamic>> secrets) =>
      _guard(() async {
        final d = await _authed();
        await d.post('$_v1/projects/$ref/secrets', data: secrets);
      });

  Future<void> deleteSecrets(String ref, List<String> names) =>
      _guard(() async {
        final d = await _authed();
        await d.delete('$_v1/projects/$ref/secrets', data: names);
      });

  // --- API keys: create / update / delete ---
  Future<Map<String, dynamic>> createApiKey(
          String ref, Map<String, dynamic> data) =>
      _guard(() async {
        final d = await _authed();
        final r =
            await d.post('$_v1/projects/$ref/api-keys', data: data);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updateApiKey(
          String ref, String id, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.patch('$_v1/projects/$ref/api-keys/$id',
            data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<void> deleteApiKey(String ref, String id) => _guard(() async {
        final d = await _authed();
        await d.delete('$_v1/projects/$ref/api-keys/$id');
      });

  // --- Branches: create / get / delete / actions ---
  // List is listBranches() above (GET /v1/projects/{ref}/branches).
  // Actions live at /v1/branches/{id}: merge/push/reset/restore POST,
  // diff GET, delete DELETE.
  Future<Map<String, dynamic>> createBranch(String ref,
          {required String branchName,
          String? gitBranch,
          String? region,
          bool? withData}) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post('$_v1/projects/$ref/branches', data: {
          'branch_name': branchName,
          if (gitBranch != null) 'git_branch': gitBranch,
          if (region != null) 'region': region,
          if (withData != null) 'with_data': withData,
        });
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> getBranch(String ref, String name) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v1/projects/$ref/branches/$name');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<void> deleteBranch(String branchIdOrRef) => _guard(() async {
        final d = await _authed();
        await d.delete('$_v1/branches/$branchIdOrRef');
      });

  Future<Map<String, dynamic>> branchAction(
          String branchIdOrRef, String action) =>
      _guard(() async {
        final d = await _authed();
        final r = action == 'diff'
            ? await d.get('$_v1/branches/$branchIdOrRef/diff')
            : await d.post('$_v1/branches/$branchIdOrRef/$action');
        final data = r.data;
        if (data is Map) return Map<String, dynamic>.from(data);
        return {'result': '$data'};
      });

  // --- Platform webhooks (v2 — project level) ---
  // v1 has only /database/webhooks/enable; the endpoints API is v2.
  Future<List<Map<String, dynamic>>> listWebhooks(String ref) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get('$_v2/projects/$ref/webhooks/endpoints');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  Future<Map<String, dynamic>> createWebhook(
          String ref, Map<String, dynamic> data) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.post('$_v2/projects/$ref/webhooks/endpoints',
            data: data);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<Map<String, dynamic>> updateWebhook(
          String ref, String id, Map<String, dynamic> patch) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.patch(
            '$_v2/projects/$ref/webhooks/endpoints/$id',
            data: patch);
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<void> deleteWebhook(String ref, String id) => _guard(() async {
        final d = await _authed();
        await d.delete('$_v2/projects/$ref/webhooks/endpoints/$id');
      });

  Future<List<Map<String, dynamic>>> listWebhookDeliveries(
          String ref, String id) =>
      _guard(() async {
        final d = await _authed();
        final r = await d.get(
            '$_v2/projects/$ref/webhooks/endpoints/$id/deliveries');
        return (r.data as List).whereType<Map<String, dynamic>>().toList();
      });

  Future<void> testWebhook(String ref, String id) => _guard(() async {
        final d = await _authed();
        await d.post('$_v2/projects/$ref/webhooks/endpoints/$id/test');
      });

  Future<void> retryWebhookDelivery(String ref, String deliveryId) =>
      _guard(() async {
        final d = await _authed();
        await d.post(
            '$_v2/projects/$ref/webhooks/deliveries/$deliveryId/retry');
      });
}
