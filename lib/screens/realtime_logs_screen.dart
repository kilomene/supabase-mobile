import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/services/project_client_registry.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Realtime & Logs (preview 8).
/// Realtime = LIVE WebSocket via supabase_flutter channel
/// (wss://<ref>.supabase.co/realtime/v1/websocket, Phoenix protocol).
/// NOT polling. Logs = Management GET .../analytics/endpoints/logs
/// (ClickHouse, GET-only, <=24h). Legacy logs.all was removed 2026-09-23.
class RealtimeLogsScreen extends StatefulWidget {
  final SupabaseProject? project;
  const RealtimeLogsScreen({this.project, super.key});
  @override
  State<RealtimeLogsScreen> createState() => _RealtimeLogsScreenState();
}

class _RealtimeLogsScreenState extends State<RealtimeLogsScreen> {
  List<LogEvent> _logs = [];
  List<Map<String, dynamic>> _events = [];
  bool _loading = false;
  String? _error;
  String _source = 'edge_logs';

  Future<void> _loadLogs() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final logs = await ManagementApiClient().queryLogs(
          p.ref, "SELECT * FROM logs WHERE source = '$_source' LIMIT 50");
      setState(() => _logs = logs);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _subscribe() async {
    final p = widget.project;
    if (p == null) return;
    try {
      await ProjectClientRegistry().subscribeTable(p, table: 'users',
          onChange: (payload) {
        if (!mounted) return;
        setState(() => _events.insert(0, payload));
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _subscribe();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first to see live events and logs.'));
    }
    return Scaffold(
      appBar: SupaAppBar('Realtime & Logs — ${widget.project!.name}'),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const Row(children: [
          Icon(Icons.circle, color: Colors.green, size: 12),
          SizedBox(width: 6),
          Text('LIVE', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        const Text('Live events (Postgres Changes)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        if (_events.isEmpty)
          const Text('Waiting for live changes…',
              style: TextStyle(color: Colors.grey)),
        ..._events.take(10).map((e) => Card(
            child: ListTile(title: Text('${e['eventType'] ?? e}')))),
        const SizedBox(height: 16),
        const Text('Logs', style: TextStyle(fontWeight: FontWeight.bold)),
        DropdownButton<String>(
          value: _source,
          items: const ['edge_logs', 'auth_logs', 'postgres_logs',
                  'storage_logs', 'realtime_logs']
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _source = v);
            _loadLogs();
          },
        ),
        if (_loading) const LoadingView(),
        if (_error != null) ErrorView(_error!, onRetry: _loadLogs),
        ..._logs.map((l) => Card(
              child: ListTile(
                leading: Text(l.level),
                title: Text(l.message),
                subtitle: Text('${l.timestamp} • ${l.source}'),
              ),
            )),
      ]),
    );
  }
}
