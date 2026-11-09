import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/project_client_registry.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// GraphQL playground. Live: POST https://<ref>.supabase.co/graphql/v1
/// (pg_graphql) with the publishable key. Introspection may be disabled
/// on the project — the server error is shown, never faked.
class GraphqlScreen extends StatefulWidget {
  final SupabaseProject? project;
  const GraphqlScreen({this.project, super.key});
  @override
  State<GraphqlScreen> createState() => _GraphqlScreenState();
}

class _GraphqlScreenState extends State<GraphqlScreen> {
  final _query = TextEditingController(
      text: '{\n  __schema {\n    queryType { fields { name } }\n  }\n}');
  String? _result;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final p = widget.project;
    if (p == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      final r = await api.graphql(_query.text);
      if (mounted) setState(() => _result = prettyJson(r));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first to run GraphQL.'));
    }
    return Scaffold(
      appBar: SupaAppBar('GraphQL — ${widget.project!.name}'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'Runs against your project\'s /graphql/v1 endpoint (pg_graphql).',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
            controller: _query,
            maxLines: 10,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(labelText: 'Query')),
        const SizedBox(height: 8),
        ElevatedButton(
            onPressed: _busy ? null : _run,
            child: const Text('Run query')),
        if (_busy) const LoadingView(),
        if (_error != null) ErrorView(_error!),
        if (_result != null) ...[
          const SizedBox(height: 12),
          SelectableText(_result!, style: const TextStyle(fontSize: 12)),
        ],
      ]),
    );
  }
}
