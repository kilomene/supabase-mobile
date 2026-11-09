import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/services/project_client_registry.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Edge Functions. Live: Management GET /v1/projects/{ref}/functions,
/// GET .../functions/{slug}, GET .../functions/{slug}/body,
/// DELETE .../functions/{slug}, multipart POST .../functions/deploy
/// (server-side bundling — no Deno on-device). Invoke is project-host
/// POST /functions/v1/<slug>. NO rollback endpoint — redeploy.
class FunctionsScreen extends StatefulWidget {
  final SupabaseProject project;
  const FunctionsScreen({required this.project, super.key});
  @override
  State<FunctionsScreen> createState() => _FunctionsScreenState();
}

class _FunctionsScreenState extends State<FunctionsScreen> {
  List<EdgeFunction> _fns = [];
  bool _loading = false;
  String? _error;
  bool _busy = false;
  final _slug = TextEditingController();
  final _code = TextEditingController(
      text: 'Deno.serve(async (req) => {\n'
          '  return new Response(\n'
          '    JSON.stringify({ message: "hello" }),\n'
          '    { headers: { "Content-Type": "application/json" } },\n'
          '  );\n'
          '});');
  final _invokeBody = TextEditingController(text: '{}');

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final fns =
          await ManagementApiClient().listFunctions(widget.project.ref);
      if (mounted) setState(() => _fns = fns);
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
    _slug.dispose();
    _code.dispose();
    _invokeBody.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _deploy() async {
    final slug = _slug.text.trim();
    final code = _code.text;
    if (slug.isEmpty || code.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ManagementApiClient()
          .deployFunction(widget.project.ref, slug, code);
      _snack('Function deployed');
      _slug.clear();
      await _load();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showBody(String slug) async {
    try {
      final body =
          await ManagementApiClient().getFunctionBody(widget.project.ref, slug);
      if (!mounted) return;
      await showJsonDialog(context,
          title: '$slug — body', value: {'body': body});
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _invoke(String slug) async {
    setState(() => _busy = true);
    try {
      final api =
          await ProjectClientRegistry().apiClient(widget.project);
      final result = await api.invokeFunction(slug, _invokeBody.text);
      if (!mounted) return;
      await showJsonDialog(context, title: '$slug — invoke result', value: result);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SupaAppBar('Edge Functions — ${widget.project.name}'),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('Deploy a function',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextField(
                      controller: _slug,
                      decoration:
                          const InputDecoration(labelText: 'Slug')),
                  TextField(
                      controller: _code,
                      maxLines: 8,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                          labelText: 'index.ts source')),
                  const SizedBox(height: 8),
                  ElevatedButton(
                      onPressed: _busy ? null : _deploy,
                      child: const Text('Deploy')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _invokeBody,
                      decoration: const InputDecoration(
                          labelText: 'Invoke body (JSON text)')),
                  const SizedBox(height: 16),
                  const Text('Deployed functions',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_fns.isEmpty)
                    const EmptyView('No Edge Functions deployed yet.'),
                  ..._fns.map((f) => Card(
                        child: ListTile(
                          leading:
                              const Icon(Icons.bolt, color: Colors.green),
                          title: Text(f.slug),
                          subtitle: Text(f.status),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.play_arrow),
                                tooltip: 'Invoke',
                                onPressed: _busy
                                    ? null
                                    : () => _invoke(f.slug),
                              ),
                              IconButton(
                                icon: const Icon(Icons.visibility),
                                tooltip: 'View body',
                                onPressed: () => _showBody(f.slug),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                tooltip: 'Delete',
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        try {
                                          await ManagementApiClient()
                                              .deleteFunction(
                                                  widget.project.ref,
                                                  f.slug);
                                          _snack('Function deleted');
                                          await _load();
                                        } catch (e) {
                                          _snack('$e');
                                        }
                                      },
                              ),
                            ],
                          ),
                        ),
                      )),
                ]),
    );
  }
}
