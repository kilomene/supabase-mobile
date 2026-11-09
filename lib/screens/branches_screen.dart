import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Branches. Live: GET/POST /v1/projects/{ref}/branches,
/// GET /v1/projects/{ref}/branches/{name}, DELETE /v1/branches/{id},
/// actions at /v1/branches/{id}/merge|push|reset|restore (POST) and
/// /diff (GET). Merge covers DB + Functions only, per the docs.
class BranchesScreen extends StatefulWidget {
  final SupabaseProject? project;
  const BranchesScreen({this.project, super.key});
  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  final _api = ManagementApiClient();
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;
  String? _error;
  final _name = TextEditingController();
  final _region = TextEditingController();
  bool _busy = false;

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final rows = await _api.listBranches(p.ref);
      if (mounted) setState(() => _branches = rows);
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
    _name.dispose();
    _region.dispose();
    super.dispose();
  }

  String _idOf(Map<String, dynamic> b) => '${b['id'] ?? b['name'] ?? ''}';
  String _nameOf(Map<String, dynamic> b) => '${b['name'] ?? b['id'] ?? ''}';

  Future<void> _act(String label, Future<dynamic> Function() call,
      {bool showResult = false}) async {
    setState(() => _busy = true);
    try {
      final result = await call();
      if (!mounted) return;
      if (showResult) {
        await showJsonDialog(context,
            title: label, value: result is Map ? result : {'result': '$result'});
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$label done')));
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

  Future<void> _create() async {
    final p = widget.project;
    final name = _name.text.trim();
    if (p == null || name.isEmpty) return;
    await _act(
        'Branch created',
        () => _api.createBranch(p.ref,
            branchName: name,
            region:
                _region.text.trim().isEmpty ? null : _region.text.trim()));
    _name.clear();
    _region.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first to see its branches.'));
    }
    return Scaffold(
      appBar: SupaAppBar('Branches — ${widget.project!.name}'),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                          labelText: 'New branch name')),
                  TextField(
                      controller: _region,
                      decoration: const InputDecoration(
                          labelText: 'Region (optional)')),
                  const SizedBox(height: 8),
                  ElevatedButton(
                      onPressed: _busy ? null : _create,
                      child: const Text('Create branch')),
                  const SizedBox(height: 16),
                  if (_branches.isEmpty)
                    const EmptyView('No branches yet.'),
                  ..._branches.map((b) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.account_tree),
                          title: Text(_nameOf(b)),
                          subtitle: Text(
                              '${b['status'] ?? ''} ${b['git_branch'] ?? ''}'
                                  .trim()),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              final id = _idOf(b);
                              switch (action) {
                                case 'diff':
                                  _act('Diff',
                                      () => _api.branchAction(id, 'diff'),
                                      showResult: true);
                                case 'merge':
                                  _act('Merge',
                                      () => _api.branchAction(id, 'merge'));
                                case 'push':
                                  _act('Push',
                                      () => _api.branchAction(id, 'push'));
                                case 'reset':
                                  _act('Reset',
                                      () => _api.branchAction(id, 'reset'));
                                case 'restore':
                                  _act('Restore',
                                      () => _api.branchAction(id, 'restore'));
                                case 'delete':
                                  _act('Delete',
                                      () => _api.deleteBranch(id));
                                case 'details':
                                  showJsonDialog(context,
                                      title: _nameOf(b), value: b);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                  value: 'diff', child: Text('Diff')),
                              PopupMenuItem(
                                  value: 'merge', child: Text('Merge')),
                              PopupMenuItem(
                                  value: 'push', child: Text('Push')),
                              PopupMenuItem(
                                  value: 'reset', child: Text('Reset')),
                              PopupMenuItem(
                                  value: 'restore', child: Text('Restore')),
                              PopupMenuItem(
                                  value: 'details', child: Text('Details')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ),
                      )),
                ]),
    );
  }
}
