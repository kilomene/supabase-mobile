import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/project_api_client.dart';
import 'package:supabase_mobile/services/secure_token_storage.dart';

/// One SupabaseClient per project — the supabase_flutter singleton is
/// ONE project only and must not be used as the manager's client.
/// Realtime uses the SDK channel (live WebSocket, Phoenix protocol);
/// everything else goes through ProjectApiClient (Dio).
class ProjectClientRegistry {
  final _store = SecureTokenStorage();
  final _clients = <String, SupabaseClient>{};
  final _api = <String, ProjectApiClient>{};

  Future<SupabaseClient> realtimeClient(SupabaseProject p) async {
    final pub = await _store.readProjectPublishable(p.ref);
    if (pub == null || pub.isEmpty) {
      throw Exception('Add this project\'s publishable key in Settings first.');
    }
    return _clients.putIfAbsent(
        p.ref, () => SupabaseClient(p.url, pub));
  }

  Future<ProjectApiClient> apiClient(SupabaseProject p) async {
    final pub = await _store.readProjectPublishable(p.ref);
    if (pub == null || pub.isEmpty) {
      throw Exception('Add this project\'s publishable key in Settings first.');
    }
    final secret = await _store.readProjectSecret(p.ref);
    return _api.putIfAbsent(p.ref,
        () => ProjectApiClient(ref: p.ref, publishableKey: pub, secretKey: secret));
  }

  /// Live Postgres Changes subscription. Reconnect + resync is the
  /// caller's job on resume (iOS/Android kill background sockets);
  /// Realtime does not replay missed changes while offline.
  Future<RealtimeChannel> subscribeTable(
    SupabaseProject p, {
    required String table,
    void Function(Map<String, dynamic> payload)? onChange,
  }) async {
    final client = await realtimeClient(p);
    final channel = client.channel('public:$table');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: (payload) => onChange?.call({
            'eventType': payload.eventType.name,
            'schema': payload.schema,
            'table': payload.table,
            'newRecord': payload.newRecord,
            'oldRecord': payload.oldRecord,
          }),
    );
    channel.subscribe();
    return channel;
  }
}
