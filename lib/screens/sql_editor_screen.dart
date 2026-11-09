import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// SQL Editor (preview 4). Live backend: POST
/// /v1/projects/{ref}/database/query (Beta, 201) + read-only variant.
/// Also the route for DDL, RLS, extensions, pgvector/pgmq/pg_cron.
class SqlEditorScreen extends StatefulWidget {
  final SupabaseProject project;
  final String? initialSql;
  const SqlEditorScreen({required this.project, this.initialSql, super.key});
  @override
  State<SqlEditorScreen> createState() => _SqlEditorScreenState();
}

class _SqlEditorScreenState extends State<SqlEditorScreen> {
  late final TextEditingController _sql;
  SqlResult? _result;
  bool _busy = false;
  String? _error;
  int? _ms;

  @override
  void initState() {
    super.initState();
    _sql = TextEditingController(
        text: widget.initialSql ??
            'SELECT id, email FROM auth.users ORDER BY created_at DESC LIMIT 10;');
  }

  @override
  void dispose() {
    _sql.dispose();
    super.dispose();
  }

  Future<void> _run({bool readOnly = false}) async {
    setState(() => _busy = true);
    final t0 = DateTime.now();
    try {
      final r = await ManagementApiClient()
          .runQuery(widget.project.ref, _sql.text, readOnly: readOnly);
      setState(() {
        _result = r;
        _ms = DateTime.now().difference(t0).inMilliseconds;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SupaAppBar('SQL Editor — ${widget.project.name}',
          actions: [
            IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: _busy ? null : () => _run(),
                tooltip: 'Run'),
          ]),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        TextField(
            controller: _sql,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Query')),
        const SizedBox(height: 8),
        Row(children: [
          ElevatedButton(
              onPressed: _busy ? null : () => _run(),
              child: const Text('Run')),
          const SizedBox(width: 8),
          OutlinedButton(
              onPressed: _busy ? null : () => _run(readOnly: true),
              child: const Text('Run read-only')),
        ]),
        if (_busy) const LoadingView(),
        if (_error != null) ErrorView(_error!),
        if (_result != null) ...[
          const SizedBox(height: 12),
          Text(
              '${_result!.rows.length} rows • ${_ms ?? 0}ms',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          ..._result!.rows.take(50).map((row) => Card(
                child: ListTile(
                    title: Text(row.entries
                        .take(3)
                        .map((e) => '${e.key}: ${e.value}')
                        .join('  •  '))),
              )),
        ],
        const SizedBox(height: 12),
        const Text(
            'SQL-backed: DDL, RLS policies, extensions, pgvector, Queues (pgmq) and Cron (pg_cron) all run through this same query endpoint — there is no dedicated REST endpoint for them.',
            style: TextStyle(color: Colors.grey)),
      ]),
    );
  }
}
