import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Log drains. Live (v2): GET/POST /v2/projects/{ref}/analytics/log-drains,
/// PUT/DELETE /v2/projects/{ref}/analytics/log-drains/{id}.
/// NOTE: the v1 path is NOT in the live spec — the old client called it
/// and was wrong; this screen uses v2. Drains forward logs to an
/// external sink; they do not give access to logs older than 24h.
class LogDrainsScreen extends StatefulWidget {
  final SupabaseProject? project;
  const LogDrainsScreen({this.project, super.key});
  @override
  State<LogDrainsScreen> createState() => _LogDrainsScreenState();
}

class _LogDrainsScreenState extends State<LogDrainsScreen> {
  final _api = ManagementApiClient();
  List<Map<String, dynamic>> _drains = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _type = TextEditingController(text: 'http');

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final rows = await _api.listLogDrains(p.ref);
      if (mounted) setState(() => _drains = rows);
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
    _url.dispose();
    _type.dispose();
    super.dispose();
  }

  String _idOf(Map<String, dynamic> d) => '${d['id'] ?? ''}';

  Future<void> _create() async {
    final p = widget.project;
    if (p == null) return;
    final name = _name.text.trim();
    final url = _url.text.trim();
    final type = _type.text.trim();
    if (name.isEmpty || url.isEmpty || type.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _api.createLogDrain(p.ref, {
        'data': {'name': name, 'url': url, 'type': type}
      });
      _name.clear();
      _url.clear();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Drain created')));
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
          body: EmptyView('Pick a project first to see its log drains.'));
    }
    return Scaffold(
      appBar: SupaAppBar('Log Drains — ${widget.project!.name}'),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  TextField(
                      controller: _name,
                      decoration:
                          const InputDecoration(labelText: 'Drain name')),
                  TextField(
                      controller: _url,
                      decoration: const InputDecoration(
                          labelText: 'Destination URL')),
                  TextField(
                      controller: _type,
                      decoration: const InputDecoration(
                          labelText: 'Type (e.g. http)')),
                  const SizedBox(height: 8),
                  ElevatedButton(
                      onPressed: _busy ? null : _create,
                      child: const Text('Create drain')),
                  const SizedBox(height: 16),
                  if (_drains.isEmpty)
                    const EmptyView('No log drains configured.'),
                  ..._drains.map((d) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.plumbing),
                          title: Text(
                              '${d['name'] ?? d['id'] ?? ''}'),
                          subtitle: Text(
                              '${d['url'] ?? d['type'] ?? ''}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.visibility),
                                onPressed: () => showJsonDialog(context,
                                    title: 'Drain', value: d),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        try {
                                          await _api.deleteLogDrain(
                                              widget.project!.ref,
                                              _idOf(d));
                                          await _load();
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    content: Text('$e')));
                                          }
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
