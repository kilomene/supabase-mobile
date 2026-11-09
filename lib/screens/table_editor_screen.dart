import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/app_state.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/services/project_client_registry.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Table Editor (preview). Live: PostgREST /rest/v1/{table} for rows
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
  List<String> _tables = [];
  List<Map<String, dynamic>> _meta = [];
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String? _error;
  String _filterColumn = '';
  String _filterValue = '';
  String? _sortColumn;
  bool _sortAsc = true;
  final _tableController = TextEditingController(text: 'users');
  final _filterColumnController = TextEditingController();
  final _filterValueController = TextEditingController();
  final _sortColumnController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTables();
    _load();
  }

  @override
  void didUpdateWidget(TableEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.project?.ref != oldWidget.project?.ref) {
      _loadTables();
      _load();
    }
  }

  @override
  void dispose() {
    _tableController.dispose();
    _filterColumnController.dispose();
    _filterValueController.dispose();
    _sortColumnController.dispose();
    super.dispose();
  }

  /// Metadata entries may be maps with a 'name' key, or nested under
  /// 'tables'. Anything else is ignored; an empty list falls back to
  /// the free-text table field.
  List<String> _parseTables(List<Map<String, dynamic>> meta) {
    final names = <String>{};
    for (final e in meta) {
      if (e['tables'] is List) {
        for (final t in e['tables'] as List) {
          if (t is Map && t['name'] != null) names.add('${t['name']}');
          if (t is String) names.add(t);
        }
      } else if (e['name'] is String &&
          (e.containsKey('columns') ||
              e.containsKey('rls_enabled') ||
              e.containsKey('schema'))) {
        names.add('${e['name']}');
      }
    }
    return names.toList()..sort();
  }

  /// RLS is only claimed when a metadata entry for this table carries a
  /// truthy rls flag; otherwise the meta row shows just the row count.
  bool _rlsEnabledFor(String table) {
    for (final e in _meta) {
      Map<String, dynamic>? entry;
      if ('${e['name']}' == table) entry = e;
      if (e['tables'] is List) {
        for (final t in e['tables'] as List) {
          if (t is Map && '${t['name']}' == table) {
            entry = t as Map<String, dynamic>;
          }
        }
      }
      if (entry != null) {
        for (final k in [
          'rls_enabled',
          'rls',
          'row_level_security',
          'rowLevelSecurity'
        ]) {
          if (entry[k] == true) return true;
        }
        return false;
      }
    }
    return false;
  }

  Future<void> _loadTables() async {
    final p = widget.project;
    if (p == null) return;
    try {
      final meta = await ManagementApiClient().databaseMetadata(p.ref);
      if (!mounted) return;
      setState(() {
        _meta = meta;
        _tables = _parseTables(meta);
        if (_tables.isNotEmpty && !_tables.contains(_table)) {
          _table = _tables.first;
          _tableController.text = _table;
        }
      });
    } catch (_) {
      // Table list is a nicety; the text field still works without it.
    }
  }

  Map<String, String> _composedFilters() {
    final f = <String, String>{};
    if (_filterColumn.isNotEmpty && _filterValue.isNotEmpty) {
      f[_filterColumn] = 'eq.$_filterValue';
    }
    if (_sortColumn != null) {
      f['order'] = '$_sortColumn.${_sortAsc ? 'asc' : 'desc'}';
    }
    return f;
  }

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      final rows = await api.selectRows(_table,
          limit: 100, filters: _composedFilters());
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _columns =>
      _rows.isEmpty ? const [] : _rows.first.keys.toList();

  Future<void> _showFilterDialog() async {
    _filterColumnController.text = _filterColumn;
    _filterValueController.text = _filterValue;
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter rows'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _filterColumnController,
              decoration: const InputDecoration(labelText: 'Column')),
          TextField(
              controller: _filterValueController,
              decoration: const InputDecoration(labelText: 'Equals value')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Clear')),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Apply')),
        ],
      ),
    );
    if (apply == null) return;
    setState(() {
      if (apply) {
        _filterColumn = _filterColumnController.text.trim();
        _filterValue = _filterValueController.text.trim();
      } else {
        _filterColumn = '';
        _filterValue = '';
      }
    });
    await _load();
  }

  Future<void> _showSortDialog() async {
    _sortColumnController.text = _sortColumn ?? '';
    var asc = _sortAsc;
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Sort rows'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _sortColumnController,
                decoration: const InputDecoration(labelText: 'Column')),
            const SizedBox(height: 8),
            Row(children: [
              ChoiceChip(
                label: const Text('Ascending'),
                selected: asc,
                onSelected: (_) => setDialogState(() => asc = true),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Descending'),
                selected: !asc,
                onSelected: (_) => setDialogState(() => asc = false),
              ),
            ]),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Clear')),
            ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (apply == null) return;
    setState(() {
      if (apply && _sortColumnController.text.trim().isNotEmpty) {
        _sortColumn = _sortColumnController.text.trim();
        _sortAsc = asc;
      } else {
        _sortColumn = null;
        _sortAsc = true;
      }
    });
    await _load();
  }

  Future<void> _addRow() async {
    final row = await showJsonEditor(context,
        title: 'Add row to $_table', initial: {});
    if (row == null) return;
    final p = widget.project;
    if (p == null) return;
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      await api.insertRows(_table, [row]);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    final p = widget.project;
    if (p == null || _columns.isEmpty) return;
    final firstKey = _columns.first;
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      await api.deleteRows(_table, {firstKey: 'eq.${row[firstKey]}'});
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Row deleted')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _darkButton(
      {required IconData icon,
      required String label,
      required VoidCallback onPressed}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _headerCell(String col) {
    final sorted = _sortColumn == col;
    return SizedBox(
      width: 160,
      child: InkWell(
        onTap: () {
          setState(() {
            if (sorted) {
              _sortAsc = !_sortAsc;
            } else {
              _sortColumn = col;
              _sortAsc = true;
            }
          });
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(children: [
            Expanded(
              child: Text(col,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Icon(Icons.keyboard_arrow_down,
                size: 16,
                color: sorted ? AppTheme.green : AppTheme.muted),
          ]),
        ),
      ),
    );
  }

  Widget _valueCell(Object? value) {
    return SizedBox(
      width: 160,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Text('${value ?? ''}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    if (p == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first, then browse its tables.'));
    }
    final n = _rows.length;
    final footer = n == 100
        ? 'Showing 1–100 of 100+ rows'
        : 'Showing 1–$n of $n rows';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SupaLogoRow(size: 20),
                  const Spacer(),
                  InkWell(
                    onTap: () => AppState.instance.clearProject(),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Row(children: [
                        Text(p.name,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const Icon(Icons.keyboard_arrow_down,
                            color: AppTheme.muted),
                      ]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Table Editor',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (_tables.isNotEmpty)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.green, width: 1.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButton<String>(
                          value: _tables.contains(_table) ? _table : null,
                          hint: Text(_table),
                          underline: const SizedBox.shrink(),
                          dropdownColor: AppTheme.surface2,
                          items: _tables
                              .map((t) => DropdownMenuItem(
                                  value: t, child: Text(t)))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _table = v;
                              _tableController.text = v;
                            });
                            _load();
                          },
                        ),
                      )
                    else
                      SizedBox(
                        width: 140,
                        child: TextField(
                          controller: _tableController,
                          decoration: const InputDecoration(
                              labelText: 'Table',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12)),
                          onSubmitted: (v) {
                            _table = v.trim();
                            _load();
                          },
                        ),
                      ),
                    const SizedBox(width: 8),
                    _darkButton(
                        icon: Icons.filter_list,
                        label: 'Filter',
                        onPressed: _showFilterDialog),
                    const SizedBox(width: 8),
                    _darkButton(
                        icon: Icons.swap_vert,
                        label: 'Sort',
                        onPressed: _showSortDialog),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _addRow,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min,
                            children: [
                          Icon(Icons.add, size: 18, color: Colors.black),
                          SizedBox(width: 4),
                          Text('+ Add row',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                      '$n rows${_rlsEnabledFor(_table) ? ' · RLS enabled' : ''}',
                      style: const TextStyle(color: AppTheme.muted)),
                  const Spacer(),
                  const Text('Swipe → to view more columns',
                      style: TextStyle(color: AppTheme.green, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Expanded(child: LoadingView())
              else if (_error != null)
                Expanded(child: ErrorView(_error!, onRetry: _load))
              else if (_rows.isEmpty)
                const Expanded(
                    child: EmptyView('No rows in this table (or RLS hides them).'))
              else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color:
                                    Colors.white.withValues(alpha: 0.08)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      ..._columns.map(_headerCell),
                                      const SizedBox(
                                        width: 56,
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 14),
                                          child: Text('actions',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(
                                      height: 1, color: Colors.white12),
                                  ..._rows.map((row) => Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              ..._columns.map((c) =>
                                                  _valueCell(row[c])),
                                              SizedBox(
                                                width: 56,
                                                child: PopupMenuButton<String>(
                                                  icon: const Icon(
                                                      Icons.more_horiz,
                                                      color: AppTheme.muted),
                                                  onSelected: (action) async {
                                                    if (action == 'view') {
                                                      await showJsonDialog(
                                                          context,
                                                          title: 'Row',
                                                          value: row);
                                                    } else if (action ==
                                                        'delete') {
                                                      await _deleteRow(row);
                                                    }
                                                  },
                                                  itemBuilder: (context) =>
                                                      const [
                                                    PopupMenuItem(
                                                        value: 'view',
                                                        child:
                                                            Text('View JSON')),
                                                    PopupMenuItem(
                                                        value: 'delete',
                                                        child:
                                                            Text('Delete')),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Divider(
                                              height: 1,
                                              color: Colors.white12),
                                        ],
                                      )),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(footer,
                          style: const TextStyle(color: AppTheme.muted)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
