import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Edge Function secrets. Live: GET /v1/projects/{ref}/secrets,
/// POST /v1/projects/{ref}/secrets, DELETE /v1/projects/{ref}/secrets.
/// The API returns name + hash only — secret VALUES are never returned
/// and never displayed. Create sends name + value once.
class SecretsScreen extends StatefulWidget {
  final SupabaseProject? project;
  const SecretsScreen({this.project, super.key});
  @override
  State<SecretsScreen> createState() => _SecretsScreenState();
}

class _SecretsScreenState extends State<SecretsScreen> {
  final _api = ManagementApiClient();
  List<Map<String, dynamic>> _secrets = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;
  final _name = TextEditingController();
  final _value = TextEditingController();

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final rows = await _api.listSecrets(p.ref);
      if (mounted) setState(() => _secrets = rows);
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
    _value.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final p = widget.project;
    final name = _name.text.trim();
    final value = _value.text;
    if (p == null || name.isEmpty || value.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _api.createSecrets(p.ref, [
        {'name': name, 'value': value}
      ]);
      _name.clear();
      _value.clear();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Secret created')));
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

  Future<void> _delete(String name) async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _busy = true);
    try {
      await _api.deleteSecrets(p.ref, [name]);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Secret deleted')));
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

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first to see its secrets.'));
    }
    return Scaffold(
      appBar: SupaAppBar('Function Secrets — ${widget.project!.name}'),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const Text(
                      'Values are never returned by the API and are never shown here — only names and hashes.',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _name,
                      decoration:
                          const InputDecoration(labelText: 'Secret name')),
                  TextField(
                      controller: _value,
                      decoration:
                          const InputDecoration(labelText: 'Secret value'),
                      obscureText: true),
                  const SizedBox(height: 8),
                  ElevatedButton(
                      onPressed: _busy ? null : _create,
                      child: const Text('Create secret')),
                  const SizedBox(height: 16),
                  if (_secrets.isEmpty)
                    const EmptyView('No secrets yet.'),
                  ..._secrets.map((s) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.key),
                          title:
                              Text('${s['name'] ?? s['id'] ?? ''}'),
                          subtitle: Text(
                              '${s['hash'] ?? s['value_hash'] ?? ''}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: _busy
                                ? null
                                : () => _delete('${s['name'] ?? ''}'),
                          ),
                        ),
                      )),
                ]),
    );
  }
}
