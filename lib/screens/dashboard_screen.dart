import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/app_state.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/widgets/common.dart';
import 'package:supabase_mobile/screens/sql_editor_screen.dart';
import 'package:supabase_mobile/screens/table_editor_screen.dart';

/// Native Dashboard overview — the project home screen.
/// Live: GET /v1/projects/{ref} (via the selected project), health,
/// usage.api-counts + api-requests-count (egress), recent logs
/// (ClickHouse, <=24h), security advisors. Nothing here is cached or
/// invented; every number comes from the endpoint on load.
class DashboardScreen extends StatefulWidget {
  final SupabaseProject? project;
  const DashboardScreen({this.project, super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _api = ManagementApiClient();
  bool _loading = true;
  String? _error;
  String _health = '';
  Map<String, dynamic> _usage = {};
  int _requests = 0;
  List<LogEvent> _logs = [];
  int _advisorCount = 0;
  bool _busy = false;

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.projectHealth(p.ref),
        _api.usageCounts(p.ref),
        _api.apiRequestsCount(p.ref),
        _api.queryLogs(p.ref,
            "SELECT * FROM logs WHERE source = 'postgres_logs' LIMIT 10"),
        _api.securityAdvisors(p.ref),
      ]);
      if (!mounted) return;
      setState(() {
        _health = results[0] as String;
        _usage = results[1] as Map<String, dynamic>;
        _requests = results[2] as int;
        _logs = results[3] as List<LogEvent>;
        _advisorCount = (results[4] as List).length;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _projectAction(Future<void> Function() call, String done) async {
    setState(() => _busy = true);
    try {
      await call();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    if (p == null) {
      return const Scaffold(
          body: EmptyView(
              'Pick a project first — open the Projects tab and tap one.'));
    }
    return Scaffold(
      appBar: SupaAppBar('Dashboard — ${p.name}', actions: [
        IconButton(
          icon: const Icon(Icons.swap_horiz),
          tooltip: 'Switch project',
          onPressed: () => AppState.instance.clearProject(),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: _load,
        ),
      ]),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.circle,
                            color: p.isActive ? Colors.green : Colors.grey,
                            size: 12),
                        title: Text(p.name),
                        subtitle: Text(
                            '${p.status} • ${p.region} • ${p.organizationSlug}\n${p.url}'),
                        isThreeLine: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.monitor_heart),
                        title: const Text('Health'),
                        subtitle: Text(_health.isEmpty ? '—' : _health),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.show_chart),
                        title: const Text('Usage & egress'),
                        subtitle: Text(
                            'API requests: $_requests\n${_usage.entries.map((e) => '${e.key}: ${e.value}').join('\n')}'),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.shield),
                        title: const Text('Security advisors'),
                        subtitle: Text(_advisorCount == 0
                            ? 'No open advisor findings.'
                            : '$_advisorCount open findings — see Advisors.'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Quick actions',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.storage),
                        label: const Text('Table Editor'),
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    TableEditorScreen(project: p))),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.terminal),
                        label: const Text('SQL Editor'),
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => SqlEditorScreen(project: p))),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Restart'),
                        onPressed: _busy
                            ? null
                            : () => _projectAction(
                                () => _api.restartProject(p.ref),
                                'Restart requested'),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.pause),
                        label: const Text('Pause'),
                        onPressed: _busy
                            ? null
                            : () => _projectAction(
                                () => _api.pauseProject(p.ref),
                                'Pause requested'),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    const Text('Recent logs (postgres, last 24h)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (_logs.isEmpty)
                      const Text('No recent postgres logs.',
                          style: TextStyle(color: Colors.grey)),
                    ..._logs.map((l) => Card(
                          child: ListTile(
                            leading: Text(l.level),
                            title: Text(l.message),
                            subtitle: Text(l.timestamp),
                          ),
                        )),
                  ]),
                ),
    );
  }
}
