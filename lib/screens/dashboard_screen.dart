import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/app_state.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
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

  Widget _quickAction(
      IconData icon, String label, VoidCallback? onPressed) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
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
                    RichCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.circle,
                                color: p.isActive
                                    ? AppTheme.green
                                    : Colors.grey,
                                size: 12),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(p.name,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold)),
                            ),
                            projectStatusPill(p.status),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            const Icon(Icons.location_on,
                                size: 16, color: AppTheme.muted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                  '${p.region} • ${p.organizationSlug}',
                                  style: const TextStyle(
                                      color: AppTheme.muted)),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.link,
                                size: 16, color: AppTheme.muted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(p.url,
                                  style: const TextStyle(
                                      color: AppTheme.muted)),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    RichCard(
                      child: Row(children: [
                        Expanded(
                            child: StatColumn(
                                label: 'API requests',
                                value: formatCompact(_requests))),
                        Expanded(
                            child: StatColumn(
                                label: 'Advisor findings',
                                value: '$_advisorCount')),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    const SectionLabel('Health'),
                    const SizedBox(height: 8),
                    RichCard(
                      child: Row(children: [
                        Icon(Icons.circle,
                            color: _health.isEmpty
                                ? Colors.grey
                                : AppTheme.green,
                            size: 12),
                        const SizedBox(width: 12),
                        const IconTile(
                            icon: Icons.monitor_heart,
                            color: AppTheme.green,
                            bg: AppTheme.green,
                            size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Health',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              const SizedBox(height: 2),
                              Text(_health.isEmpty ? '—' : _health,
                                  style: const TextStyle(
                                      color: AppTheme.muted)),
                            ],
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    const SectionLabel('Usage & egress'),
                    const SizedBox(height: 8),
                    RichCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            IconTile(
                                icon: Icons.show_chart,
                                color: AppTheme.green,
                                bg: AppTheme.green,
                                size: 44),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text('Usage & egress',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ),
                          ]),
                          if (_usage.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text('No usage returned.',
                                  style: TextStyle(color: AppTheme.muted)),
                            ),
                          ..._usage.entries.map((e) => Padding(
                                padding:
                                    const EdgeInsets.only(top: 8),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(e.key,
                                        style: const TextStyle(
                                            color: AppTheme.muted)),
                                    Text('${e.value}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const SectionLabel('Security advisors'),
                    const SizedBox(height: 8),
                    RichCard(
                      child: Row(children: [
                        const IconTile(
                            icon: Icons.shield,
                            color: AppTheme.green,
                            bg: AppTheme.green,
                            size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Security advisors',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              const SizedBox(height: 2),
                              Text(
                                  _advisorCount == 0
                                      ? 'No open advisor findings.'
                                      : '$_advisorCount open findings — see Advisors.',
                                  style: const TextStyle(
                                      color: AppTheme.muted)),
                            ],
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    const SectionLabel('Quick actions'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _quickAction(
                          Icons.storage,
                          'Table Editor',
                          () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  TableEditorScreen(project: p)))),
                      _quickAction(
                          Icons.terminal,
                          'SQL Editor',
                          () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  SqlEditorScreen(project: p)))),
                      _quickAction(
                          Icons.restart_alt,
                          'Restart',
                          _busy
                              ? null
                              : () => _projectAction(
                                  () => _api.restartProject(p.ref),
                                  'Restart requested')),
                      _quickAction(
                          Icons.pause,
                          'Pause',
                          _busy
                              ? null
                              : () => _projectAction(
                                  () => _api.pauseProject(p.ref),
                                  'Pause requested')),
                    ]),
                    const SizedBox(height: 16),
                    const SectionLabel('Recent logs (postgres, last 24h)'),
                    const SizedBox(height: 8),
                    if (_logs.isEmpty)
                      const Text('No recent postgres logs.',
                          style: TextStyle(color: AppTheme.muted)),
                    ..._logs.map((l) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: RichCard(
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                levelPill(l.level),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(l.message,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 2),
                                      Text(relativeTime(l.timestamp),
                                          style: const TextStyle(
                                              color: AppTheme.muted,
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                  ]),
                ),
    );
  }
}
