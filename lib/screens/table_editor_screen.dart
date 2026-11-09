import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/project_client_registry.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Table Editor (preview 3). Live: PostgREST /rest/v1/{table} for rows
/// + Management database/metadata for the table list. DDL / RLS /
/// extensions are SQL-backed (POST /database/query) — see SqlBacked.
class TableEditorScreen extends StatefulWidget {
  final SupabaseProject? project;
  const TableEditorScreen({this.project, super.key});
  @override
  State<TableEditorScreen> createState() => _TableEditorScreenState();
}

class _TableEditorScreenState extends State<TableEditorScreen> {
  String _table = 'users';
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String? _error;

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      final rows = await api.selectRows(_table, limit: 100);
      setState(() => _rows = rows);
    } catch (e) {
      setState(() => _error = '$e');
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
  Widget build(BuildContext context) {
    final p = widget.project;
    if (p == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first, then browse its tables.'));
    }
    return Scaffold(
      appBar: SupaAppBar('Table Editor — ${p.name}'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(labelText: 'Table'),
                controller: TextEditingController(text: _table),
                onSubmitted: (v) {
                  _table = v.trim();
                  _load();
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: _load, child: const Text('Load')),
          ]),
        ),
        if (_loading) const LoadingView(),
        if (_error != null) ErrorView(_error!, onRetry: _load),
        if (!_loading && _error == null)
          Expanded(
            child: _rows.isEmpty
                ? const EmptyView('No rows in this table (or RLS hides them).')
                : ListView.builder(
                    itemCount: _rows.length,
                    itemBuilder: (context, i) {
                      final row = _rows[i];
                      final keys = row.keys.toList();
                      return Card(
                        child: ListTile(
                          title: Text(keys.isNotEmpty
                              ? '${row[keys.first]}'
                              : 'Row ${i + 1}'),
                          subtitle: Text(row.entries
                              .take(3)
                              .map((e) => '${e.key}: ${e.value}')
                              .join('  •  ')),
                        ),
                      );
                    },
                  ),
          ),
      ]),
    );
  }
}
