import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/services/project_client_registry.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Realtime & Logs (preview 2).
/// Realtime = LIVE WebSocket via supabase_flutter channel
/// (wss://<ref>.supabase.co/realtime/v1/websocket, Phoenix protocol),
/// subscribed to table 'users' exactly as before — NOT polling.
/// The channel payload carries no timestamp, so the time shown for a
/// live event is the time it was RECEIVED (recorded with DateTime.now()
/// on arrival). Logs = Management GET .../analytics/endpoints/logs
/// (ClickHouse, GET-only, <=24h). Legacy logs.all was removed 2026-09-23.
class RealtimeLogsScreen extends StatefulWidget {
  final SupabaseProject? project;
  const RealtimeLogsScreen({this.project, super.key});
  @override
  State<RealtimeLogsScreen> createState() => _RealtimeLogsScreenState();
}

class _RealtimeLogsScreenState extends State<RealtimeLogsScreen> {
  List<LogEvent> _logs = [];
  final List<Map<String, dynamic>> _events = [];
  bool _loading = false;
  String? _error;
  String _source = 'all';
  Timer? _ticker;

  // ClickHouse tables are per source (see management_api_client.dart).
  // "All" merges the four main source tables, newest first.
  static const _allSources = [
    'postgres_logs',
    'edge_logs',
    'auth_logs',
    'storage_logs',
  ];

  String _sqlFor(String source) {
    return switch (source) {
      'auth_logs' => 'SELECT * FROM auth_logs LIMIT 50',
      'postgres_logs' => 'SELECT * FROM postgres_logs LIMIT 50',
      'storage_logs' => 'SELECT * FROM storage_logs LIMIT 50',
      'edge_logs' => 'SELECT * FROM edge_logs LIMIT 50',
      _ => 'SELECT * FROM postgres_logs LIMIT 50',
    };
  }

  Future<void> _loadLogs() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final List<LogEvent> logs;
      if (_source == 'all') {
        final parts = await Future.wait(_allSources.map((t) async {
          try {
            return await ManagementApiClient()
                .queryLogs(p.ref, 'SELECT * FROM $t LIMIT 50');
          } catch (_) {
            return const <LogEvent>[];
          }
        }));
        logs = parts.expand((e) => e).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        if (logs.length > 50) logs.removeRange(50, logs.length);
      } else {
        logs = await ManagementApiClient().queryLogs(p.ref, _sqlFor(_source));
      }
      if (mounted) setState(() => _logs = logs);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
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
        setState(() => _events.insert(
            0, {...payload, 'receivedAt': DateTime.now()}));
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _subscribe();
    // Refresh the "just now / 3s ago" labels on live events.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _events.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _fmtTime(DateTime t) {
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$h12:${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')} $ampm';
  }

  String _relativeSince(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 5) return 'just now';
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }

  Widget _filterChip(String key, String label) {
    final active = _source == key;
    return GestureDetector(
      onTap: () {
        if (_source == key) return;
        setState(() => _source = key);
        _loadLogs();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppTheme.green : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? AppTheme.green
                : Colors.white.withValues(alpha: 0.25),
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? Colors.black : AppTheme.text,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _eventCard(Map<String, dynamic> e) {
    final type = '${e['eventType'] ?? 'INSERT'}';
    final table = '${e['table'] ?? 'users'}';
    final received = e['receivedAt'] as DateTime?;
    final timeLabel =
        received == null ? '—' : _fmtTime(received.toLocal());
    final relLabel =
        received == null ? '' : ' • ${_relativeSince(received.toLocal())}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RichCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                eventPill(type),
                const SizedBox(height: 8),
                Text('into $table',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('$timeLabel$relLabel',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logRow(LogEvent l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(l.timestamp,
                style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 12,
                    fontFamily: 'monospace')),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                levelPill(l.level),
                const SizedBox(height: 6),
                Text(l.message,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first to see live events and logs.'));
    }
    final p = widget.project!;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 4),
              Text('PROJECT • ${p.name.toUpperCase()}',
                  style: const TextStyle(
                      color: AppTheme.green,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Text('Realtime & Logs',
                    style:
                        TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.green),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 10, color: AppTheme.green),
                  SizedBox(width: 6),
                  Text('LIVE',
                      style: TextStyle(
                          color: AppTheme.green,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Row(children: [
            Icon(Icons.bolt, color: AppTheme.green, size: 20),
            SizedBox(width: 6),
            Text('Live Events',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.muted)),
          ]),
          const SizedBox(height: 12),
          if (_events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Waiting for live changes…',
                  style: TextStyle(color: AppTheme.muted)),
            ),
          ..._events.take(10).map(_eventCard),
          const SizedBox(height: 16),
          const Row(children: [
            Icon(Icons.description_outlined,
                color: AppTheme.green, size: 20),
            SizedBox(width: 6),
            Text('Logs',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.muted)),
          ]),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('all', 'All'),
                const SizedBox(width: 10),
                _filterChip('auth_logs', 'Auth'),
                const SizedBox(width: 10),
                _filterChip('postgres_logs', 'Database'),
                const SizedBox(width: 10),
                _filterChip('storage_logs', 'Storage'),
                const SizedBox(width: 10),
                _filterChip('edge_logs', 'Functions'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_loading) const LoadingView(),
          if (_error != null) ErrorView(_error!, onRetry: _loadLogs),
          if (!_loading && _error == null && _logs.isEmpty)
            const EmptyView('No logs in the last 24 hours for this filter.'),
          ..._logs.map(_logRow),
        ]),
      ),
    );
  }
}
