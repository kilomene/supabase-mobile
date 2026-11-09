import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/widgets/common.dart';
import 'package:supabase_mobile/screens/sql_editor_screen.dart';

/// Database administration. Live Management API:
/// migrations (GET/POST/PATCH), saved SQL snippets (GET /v1/snippets),
/// TS types (GET /types/typescript), Postgres config + pooler + PgBouncer,
/// disk config/autoscale/util, JIT access, Postgres upgrade, read
/// replicas. DB roles have NO REST endpoint — they run as live SQL
/// through the query endpoint (SQL-backed, labelled as such).
/// NOTE: no read-only-mode endpoint exists in the live spec, so it is
/// not offered here — the report table's entry was not verified.
class DatabaseScreen extends StatefulWidget {
  final SupabaseProject? project;
  const DatabaseScreen({this.project, super.key});
  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> {
  final _api = ManagementApiClient();
  bool _loading = true;
  String? _error;
  bool _busy = false;
  List<Map<String, dynamic>> _migrations = [];
  List<Map<String, dynamic>> _snippets = [];
  List<Map<String, dynamic>> _jitUsers = [];
  Map<String, dynamic>? _upgradeEligibility;
  Map<String, dynamic>? _upgradeStatus;
  Map<String, dynamic>? _diskUtil;

  final _migQuery = TextEditingController();
  final _migName = TextEditingController();
  final _roleName = TextEditingController();
  final _replicaRegion = TextEditingController();

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.listMigrations(p.ref),
        _api.listSnippets(),
        _api.listJitUsers(p.ref),
        _api.upgradeEligibility(p.ref),
        _api.upgradeStatus(p.ref),
        _api.getDiskUtil(p.ref),
      ]);
      if (!mounted) return;
      setState(() {
        _migrations = results[0] as List<Map<String, dynamic>>;
        _snippets = results[1] as List<Map<String, dynamic>>;
        _jitUsers = results[2] as List<Map<String, dynamic>>;
        _upgradeEligibility = results[3] as Map<String, dynamic>;
        _upgradeStatus = results[4] as Map<String, dynamic>;
        _diskUtil = results[5] as Map<String, dynamic>;
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

  @override
  void dispose() {
    _migQuery.dispose();
    _migName.dispose();
    _roleName.dispose();
    _replicaRegion.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _act(String done, Future<void> Function() call) async {
    setState(() => _busy = true);
    try {
      await call();
      _snack(done);
      await _load();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editJson(String title,
      Future<Map<String, dynamic>> Function() load,
      Future<void> Function(Map<String, dynamic>) save) async {
    try {
      final current = await load();
      if (!mounted) return;
      final edited = await showJsonEditor(context,
          title: title, initial: current);
      if (edited == null) return;
      await save(edited);
      _snack('Saved');
      await _load();
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _runSql(String label, String sql) async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _busy = true);
    try {
      final r = await _api.runQuery(p.ref, sql);
      if (!mounted) return;
      await showJsonDialog(context,
          title: label, value: {'rows': r.rows});
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _pillButton(String label, VoidCallback? onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(label),
    );
  }

  Widget _listRow({
    required IconData icon,
    required String title,
    String subtitle = '',
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichCard(
        onTap: onTap,
        child: Row(children: [
          IconTile(
              icon: icon, color: AppTheme.green, bg: AppTheme.green, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(color: AppTheme.muted)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first to administer its database.'));
    }
    final p = widget.project!;
    return Scaffold(
      appBar: SupaAppBar('Database — ${p.name}',
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const SectionLabel('Migrations'),
                  const SizedBox(height: 8),
                  RichCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                            controller: _migName,
                            decoration: const InputDecoration(
                                labelText: 'Migration name (optional)')),
                        const SizedBox(height: 8),
                        TextField(
                            controller: _migQuery,
                            maxLines: 4,
                            decoration: const InputDecoration(
                                labelText: 'Migration SQL (required)')),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    final q = _migQuery.text.trim();
                                    if (q.isEmpty) return;
                                    await _act(
                                        'Migration created',
                                        () => _api.createMigration(p.ref,
                                            query: q,
                                            name: _migName.text.trim().isEmpty
                                                ? null
                                                : _migName.text.trim()));
                                    _migQuery.clear();
                                    _migName.clear();
                                  },
                            child: const Text('Create migration'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_migrations.isEmpty)
                    const Text('No migrations yet.',
                        style: TextStyle(color: AppTheme.muted)),
                  ..._migrations.map((m) => _listRow(
                        icon: Icons.history,
                        title:
                            '${m['version'] ?? m['name'] ?? 'migration'}',
                        subtitle: '${m['status'] ?? ''}',
                        trailing: const Icon(Icons.chevron_right,
                            color: AppTheme.muted),
                        onTap: () => showJsonDialog(context,
                            title: 'Migration', value: m),
                      )),
                  const SizedBox(height: 16),
                  const SectionLabel('Saved SQL snippets'),
                  const SizedBox(height: 8),
                  if (_snippets.isEmpty)
                    const Text('No saved snippets.',
                        style: TextStyle(color: AppTheme.muted)),
                  ..._snippets.map((s) => _listRow(
                        icon: Icons.code,
                        title: '${s['name'] ?? s['id'] ?? 'snippet'}',
                        subtitle: '${s['description'] ?? ''}',
                        trailing: const Icon(Icons.play_arrow,
                            color: AppTheme.green),
                        onTap: () async {
                          try {
                            final full =
                                await _api.getSnippet('${s['id']}');
                            final sql =
                                '${full['query'] ?? full['content'] ?? ''}';
                            if (!context.mounted) return;
                            if (sql.isEmpty) {
                              await showJsonDialog(context,
                                  title: 'Snippet', value: full);
                            } else {
                              await Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => SqlEditorScreen(
                                          project: p, initialSql: sql)));
                            }
                          } catch (e) {
                            _snack('$e');
                          }
                        },
                      )),
                  const SizedBox(height: 16),
                  const SectionLabel('Types & config'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _pillButton(
                      'TypeScript types',
                      _busy
                          ? null
                          : () async {
                              try {
                                final ts =
                                    await _api.getTypescriptTypes(p.ref);
                                if (!context.mounted) return;
                                await showJsonDialog(context,
                                    title: 'TypeScript types',
                                    value: {'types': ts});
                              } catch (e) {
                                _snack('$e');
                              }
                            },
                    ),
                    _pillButton(
                      'Postgres config',
                      _busy
                          ? null
                          : () => _editJson(
                              'Postgres config',
                              () => _api.getDbPostgresConfig(p.ref),
                              (m) =>
                                  _api.updateDbPostgresConfig(p.ref, m)),
                    ),
                    _pillButton(
                      'Pooler config',
                      _busy
                          ? null
                          : () => _editJson(
                              'Pooler config',
                              () => _api.getPoolerConfig(p.ref),
                              (m) => _api.updatePoolerConfig(p.ref, m)),
                    ),
                    _pillButton(
                      'PgBouncer',
                      _busy
                          ? null
                          : () async {
                              try {
                                final c =
                                    await _api.getPgbouncerConfig(p.ref);
                                if (!context.mounted) return;
                                await showJsonDialog(context,
                                    title: 'PgBouncer', value: c);
                              } catch (e) {
                                _snack('$e');
                              }
                            },
                    ),
                    _pillButton(
                      'Disk config',
                      _busy
                          ? null
                          : () => _editJson('Disk config',
                              () => _api.getDiskConfig(p.ref),
                              (m) => _api.updateDiskConfig(p.ref, m)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  RichCard(
                    child: SelectableText(
                        'Disk usage: ${prettyJson(_diskUtil)}',
                        style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 16),
                  const SectionLabel('Postgres upgrade'),
                  const SizedBox(height: 8),
                  RichCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                            'Eligibility: ${prettyJson(_upgradeEligibility)}\nStatus: ${prettyJson(_upgradeStatus)}',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _busy
                                ? null
                                : () => _act('Upgrade started',
                                    () => _api.startUpgrade(p.ref)),
                            child: const Text('Start Postgres upgrade'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionLabel('Read replicas'),
                  const SizedBox(height: 8),
                  RichCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                            controller: _replicaRegion,
                            decoration: const InputDecoration(
                                labelText:
                                    'Replica region (e.g. us-east-1)')),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    final region =
                                        _replicaRegion.text.trim();
                                    if (region.isEmpty) return;
                                    _act('Read replica setup requested',
                                        () =>
                                            _api.setupReadReplica(p.ref, region));
                                  },
                            child: const Text('Set up read replica'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionLabel('JIT access'),
                  const SizedBox(height: 8),
                  if (_jitUsers.isEmpty)
                    const Text('No JIT users.',
                        style: TextStyle(color: AppTheme.muted)),
                  ..._jitUsers.map((u) => _listRow(
                        icon: Icons.person,
                        title: '${u['email'] ?? u['user_id'] ?? ''}',
                        subtitle: '${u['status'] ?? ''}',
                        trailing: IconButton(
                          icon: const Icon(Icons.delete,
                              color: PreviewColors.dangerRed),
                          onPressed: _busy
                              ? null
                              : () => _act(
                                  'JIT user removed',
                                  () => _api.removeJitUser(p.ref,
                                      '${u['user_id'] ?? u['id'] ?? ''}')),
                        ),
                      )),
                  const SizedBox(height: 16),
                  const SectionLabel('DB roles — SQL-backed'),
                  const SizedBox(height: 8),
                  RichCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                            'Roles have no REST endpoint. These run as live SQL through the query endpoint.',
                            style: TextStyle(
                                color: AppTheme.muted, fontSize: 12)),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: TextField(
                                controller: _roleName,
                                decoration: const InputDecoration(
                                    labelText: 'Role name')),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    final name = _roleName.text.trim();
                                    if (name.isEmpty) return;
                                    _runSql('Create role',
                                        'CREATE ROLE $name LOGIN;');
                                  },
                            child: const Text('Create'),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          ElevatedButton(
                            onPressed: _busy
                                ? null
                                : () => _runSql('Roles',
                                    'SELECT rolname FROM pg_roles ORDER BY rolname;'),
                            child: const Text('List roles'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    final name = _roleName.text.trim();
                                    if (name.isEmpty) return;
                                    _runSql(
                                        'Drop role', 'DROP ROLE $name;');
                                  },
                            child: const Text('Drop role'),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                      'Extensions, RLS policies, pgvector, Queues (pgmq) and Cron (pg_cron) are SQL-backed — run them in the SQL Editor.',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                ]),
    );
  }
}
