/// Models mapped from the Management API (api.supabase.com) and the
/// project APIs (<ref>.supabase.co). Field names follow the live docs
/// (see research report). Unknown fields are ignored, never invented.
class Organization {
  final String id;
  final String slug;
  final String name;
  final String? plan;
  Organization({required this.id, required this.slug, required this.name, this.plan});
  factory Organization.fromJson(Map<String, dynamic> j) => Organization(
        id: '${j['id'] ?? j['slug'] ?? ''}',
        slug: '${j['slug'] ?? ''}',
        name: '${j['name'] ?? j['slug'] ?? ''}',
        plan: j['plan'] as String?,
      );
}

class SupabaseProject {
  final String ref;
  final String name;
  final String organizationSlug;
  final String region;
  final String status;
  SupabaseProject({required this.ref, required this.name, required this.organizationSlug, required this.region, required this.status});
  factory SupabaseProject.fromJson(Map<String, dynamic> j) => SupabaseProject(
        ref: '${j['id'] ?? j['ref'] ?? ''}',
        name: '${j['name'] ?? ''}',
        organizationSlug: '${j['organization_slug'] ?? ''}',
        region: '${j['region'] ?? ''}',
        status: '${j['status'] ?? ''}',
      );
  bool get isActive => status == 'ACTIVE_HEALTHY';
  String get url => 'https://$ref.supabase.co';
}

class ApiKeyItem {
  final String id;
  final String name;
  final String? type;
  final String? apiKey;
  ApiKeyItem({required this.id, required this.name, this.type, this.apiKey});
  factory ApiKeyItem.fromJson(Map<String, dynamic> j) => ApiKeyItem(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? j['type'] ?? ''}',
        type: j['type'] as String?,
        apiKey: j['api_key'] as String?,
      );
}

class AuthUser {
  final String id;
  final String email;
  final String? provider;
  final String? lastSignInAt;
  final String? createdAt;
  final bool emailConfirmed;
  AuthUser({required this.id, required this.email, this.provider, this.lastSignInAt, this.createdAt, required this.emailConfirmed});
  factory AuthUser.fromJson(Map<String, dynamic> j) {
    final identities = (j['identities'] as List?) ?? const [];
    return AuthUser(
      id: '${j['id'] ?? ''}',
      email: '${j['email'] ?? ''}',
      provider: identities.isNotEmpty ? '${identities.first['provider'] ?? ''}' : null,
      lastSignInAt: j['last_sign_in_at'] as String?,
      createdAt: j['created_at'] as String?,
      emailConfirmed: j['email_confirmed_at'] != null,
    );
  }
}

class StorageBucket {
  final String id;
  final String name;
  final bool isPublic;
  StorageBucket({required this.id, required this.name, required this.isPublic});
  factory StorageBucket.fromJson(Map<String, dynamic> j) => StorageBucket(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? j['id'] ?? ''}',
        isPublic: j['public'] as bool? ?? false,
      );
}

class StorageObject {
  final String name;
  final int? size;
  final String? updatedAt;
  StorageObject({required this.name, this.size, this.updatedAt});
  factory StorageObject.fromJson(Map<String, dynamic> j) => StorageObject(
        name: '${j['name'] ?? ''}',
        size: j['metadata'] is Map ? (j['metadata']['size'] as num?)?.toInt() : null,
        updatedAt: j['updated_at'] as String?,
      );
}

class EdgeFunction {
  final String slug;
  final String status;
  final String? version;
  EdgeFunction({required this.slug, required this.status, this.version});
  factory EdgeFunction.fromJson(Map<String, dynamic> j) => EdgeFunction(
        slug: '${j['slug'] ?? j['name'] ?? ''}',
        status: '${j['status'] ?? ''}',
        version: j['version'] != null ? '${j['version']}' : null,
      );
}

class LogEvent {
  final String timestamp;
  final String source;
  final String level;
  final String message;
  LogEvent({required this.timestamp, required this.source, required this.level, required this.message});
  factory LogEvent.fromJson(Map<String, dynamic> j) {
    final attrs = (j['log_attributes'] as Map?) ?? const {};
    return LogEvent(
      timestamp: '${j['timestamp'] ?? ''}',
      source: '${j['source'] ?? ''}',
      level: '${attrs['level'] ?? 'INF'}',
      message: '${j['event_message'] ?? attrs['message'] ?? ''}',
    );
  }
}

class SqlResult {
  final List<Map<String, dynamic>> rows;
  final int? rowCount;
  SqlResult({required this.rows, this.rowCount});
  factory SqlResult.fromJson(dynamic j) {
    if (j is List) {
      return SqlResult(rows: j.whereType<Map<String, dynamic>>().toList());
    }
    if (j is Map<String, dynamic>) {
      final data = j['data'];
      if (data is List) {
        return SqlResult(rows: data.whereType<Map<String, dynamic>>().toList());
      }
    }
    return SqlResult(rows: const []);
  }
}
