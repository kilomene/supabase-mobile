import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
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
  final _search = TextEditingController();
  String _query = '';

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
    _search.dispose();
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
    final visible = _secrets
        .where((s) =>
            _query.isEmpty ||
            '${s['name'] ?? s['id'] ?? ''}'
                .toLowerCase()
                .contains(_query))
        .toList();
    return Scaffold(
      appBar: SupaAppBar('Function Secrets — ${widget.project!.name}'),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const Text(
                      'Values are never returned by the API and are never shown here — only names and hashes.',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                  const SizedBox(height: 12),
                  RichCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('New secret'),
                        const SizedBox(height: 12),
                        TextField(
                            controller: _name,
                            decoration: const InputDecoration(
                                labelText: 'Secret name')),
                        const SizedBox(height: 8),
                        TextField(
                            controller: _value,
                            decoration: const InputDecoration(
                                labelText: 'Secret value'),
                            obscureText: true),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                              onPressed: _busy ? null : _create,
                              child: const Text('Create secret')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PreviewSearchBar(
                    controller: _search,
                    hint: 'Search secrets…',
                    onChanged: (v) =>
                        setState(() => _query = v.toLowerCase()),
                  ),
                  const SizedBox(height: 16),
                  if (visible.isEmpty)
                    const EmptyView('No secrets yet.'),
                  ...visible.map((s) {
                    final name = '${s['name'] ?? s['id'] ?? ''}';
                    final hash = '${s['hash'] ?? s['value_hash'] ?? ''}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RichCard(
                        child: Row(children: [
                          const IconTile(
                              icon: Icons.key,
                              color: AppTheme.green,
                              bg: AppTheme.green,
                              size: 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                if (hash.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(hash,
                                      style: const TextStyle(
                                          color: AppTheme.muted,
                                          fontSize: 13)),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete,
                                color: PreviewColors.dangerRed),
                            onPressed: _busy
                                ? null
                                : () => _delete(name),
                          ),
                        ]),
                      ),
                    );
                  }),
                ]),
    );
  }
}
