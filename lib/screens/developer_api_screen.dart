import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/project_client_registry.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Developer — API Docs (preview 11). Live: PostgREST + GraphQL against
/// the selected project. Docs themselves are fetched as data
/// (supabase.com/llms.txt / per-page .md) — never a dashboard WebView.
class DeveloperApiScreen extends StatefulWidget {
  final SupabaseProject project;
  const DeveloperApiScreen({required this.project, super.key});
  @override
  State<DeveloperApiScreen> createState() => _DeveloperApiScreenState();
}

class _DeveloperApiScreenState extends State<DeveloperApiScreen> {
  final _gql = TextEditingController(text: '{ __schema { types { name } } }');
  String? _gqlResult;
  bool _busy = false;
  String? _error;

  Future<void> _runGraphql() async {
    setState(() => _busy = true);
    try {
      final api = await ProjectClientRegistry().apiClient(widget.project);
      final r = await api.graphql(_gql.text);
      setState(() => _gqlResult = '$r');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SupaAppBar('Developer — API (${widget.project.name})'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('REST  •  GraphQL  •  Realtime',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SelectableText('GET ${widget.project.url}/rest/v1/users\n'
            'Header: apikey: <publishable key>'),
        const SizedBox(height: 16),
        const Text('GraphQL', style: TextStyle(fontWeight: FontWeight.bold)),
        TextField(controller: _gql, maxLines: 4),
        const SizedBox(height: 8),
        ElevatedButton(
            onPressed: _busy ? null : _runGraphql,
            child: const Text('Run GraphQL')),
        if (_busy) const LoadingView(),
        if (_error != null) ErrorView(_error!),
        if (_gqlResult != null)
          SelectableText(_gqlResult!, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}
