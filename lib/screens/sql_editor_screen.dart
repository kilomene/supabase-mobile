import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// SQL Editor (preview). Live backend: POST
/// /v1/projects/{ref}/database/query (Beta, 201) + read-only variant.
/// Also the route for DDL, RLS, extensions, pgvector/pgmq/pg_cron.
/// NOTE: the live Management spec (api.supabase.com/api/v1-json) has NO
/// POST /v1/snippets — snippets are GET-only — so no "Save query" button
/// is offered here; it would call an endpoint that does not exist.
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
  bool _editing = false;
  String? _error;
  int? _ms;
  int _resultBytes = 0;

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
    setState(() {
      _busy = true;
      _error = null;
    });
    final t0 = DateTime.now();
    try {
      final r = await ManagementApiClient()
          .runQuery(widget.project.ref, _sql.text, readOnly: readOnly);
      if (!mounted) return;
      setState(() {
        _result = r;
        _ms = DateTime.now().difference(t0).inMilliseconds;
        _resultBytes = utf8.encode(jsonEncode(r.rows)).length;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _runPill() {
    return InkWell(
      onTap: _busy ? null : () => _run(),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _busy
              ? AppTheme.green.withValues(alpha: 0.5)
              : AppTheme.green,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.play_arrow, size: 18, color: Colors.black),
          SizedBox(width: 4),
          Text('Run',
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _valueCell(Object? value) {
    return SizedBox(
      width: 160,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text('${value ?? ''}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _result?.rows ?? const [];
    final columns = rows.isEmpty ? const <String>[] : rows.first.keys.toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('SQL Editor',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _runPill()),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Static label of the default target — not a selector.
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.storage, size: 16, color: AppTheme.muted),
            SizedBox(width: 8),
            Text('main / public',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 12),
        RichCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.surface2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min,
                        children: [
                      Icon(Icons.code, size: 16),
                      SizedBox(width: 6),
                      Text('Query',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (action) {
                      if (action == 'run') {
                        _run();
                      } else if (action == 'readonly') {
                        _run(readOnly: true);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'run', child: Text('Run')),
                      PopupMenuItem(
                          value: 'readonly', child: Text('Run read-only')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_editing) ...[
                TextField(
                  controller: _sql,
                  autofocus: true,
                  maxLines: 10,
                  minLines: 6,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 14),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    filled: false,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _editing = false),
                    child: const Text('Done'),
                  ),
                ),
              ] else
                GestureDetector(
                  onTap: () => setState(() => _editing = true),
                  child: SqlCodeView(_sql.text),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_busy) const LoadingView(),
        if (_error != null) ErrorView(_error!, onRetry: () => _run()),
        if (_result != null) ...[
          RichCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Results',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(
                        '${rows.length} rows • ${_ms ?? 0}ms • ${formatBytes(_resultBytes)}',
                        style: const TextStyle(color: AppTheme.muted)),
                  ],
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const Text('Query ran — no rows returned.',
                      style: TextStyle(color: AppTheme.muted))
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          color: AppTheme.surface2,
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 40,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  child: Text('#',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                              ...columns.map((c) => SizedBox(
                                    width: 160,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      child: Text(c,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  )),
                            ],
                          ),
                        ),
                        ...rows.asMap().entries.map((e) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 40,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                        child: Text('${e.key + 1}',
                                            style: const TextStyle(
                                                color: AppTheme.muted)),
                                      ),
                                    ),
                                    ...columns.map(
                                        (c) => _valueCell(e.value[c])),
                                  ],
                                ),
                                const Divider(
                                    height: 1, color: Colors.white12),
                              ],
                            )),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Text('Showing ${rows.length} of ${rows.length} rows',
                    style: const TextStyle(color: AppTheme.muted)),
                const SizedBox(height: 4),
                const Text(
                    'Saving queries is not offered: the Management API has no endpoint to save a snippet (GET /v1/snippets only).',
                    style: TextStyle(color: AppTheme.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
            'SQL-backed: DDL, RLS policies, extensions, pgvector, Queues (pgmq) and Cron (pg_cron) all run through this same query endpoint — there is no dedicated REST endpoint for them.',
            style: TextStyle(color: Colors.grey)),
      ]),
    );
  }
}
