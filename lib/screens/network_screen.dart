import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Network & security. Live:
/// GET/PATCH /v1/projects/{ref}/network-restrictions,
/// POST /v1/projects/{ref}/network-bans/retrieve,
/// DELETE /v1/projects/{ref}/network-bans,
/// GET/PUT /v1/projects/{ref}/ssl-enforcement,
/// GET/PUT /v1/projects/{ref}/pgsodium.
/// Network restrictions/bans are paid-plan features — the API says so
/// if the plan does not include them.
class NetworkScreen extends StatefulWidget {
  final SupabaseProject? project;
  const NetworkScreen({this.project, super.key});
  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  final _api = ManagementApiClient();
  bool _loading = true;
  String? _error;
  bool _busy = false;
  Map<String, dynamic>? _restrictions;
  List<Map<String, dynamic>> _bans = [];
  Map<String, dynamic>? _ssl;
  Map<String, dynamic>? _pgsodium;
  final _banIp = TextEditingController();

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getNetworkRestrictions(p.ref),
        _api.listNetworkBans(p.ref),
        _api.getSslEnforcement(p.ref),
        _api.getPgsodium(p.ref),
      ]);
      if (!mounted) return;
      setState(() {
        _restrictions = results[0] as Map<String, dynamic>;
        _bans = results[1] as List<Map<String, dynamic>>;
        _ssl = results[2] as Map<String, dynamic>;
        _pgsodium = results[3] as Map<String, dynamic>;
      });
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
    _banIp.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _editJson(String title,
      Future<Map<String, dynamic>> Function() load,
      Future<void> Function(Map<String, dynamic>) save) async {
    try {
      final current = await load();
      if (!mounted) return;
      final edited = await showJsonEditor(context,
          title: title, initial: current);
      if (edited == null) return;
      await save(edited);
      _snack('Saved');
      await _load();
    } catch (e) {
      _snack('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first to see network & security.'));
    }
    final p = widget.project!;
    return Scaffold(
      appBar: SupaAppBar('Network & Security — ${p.name}',
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('Network restrictions',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText(prettyJson(_restrictions),
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _editJson(
                            'Network restrictions',
                            () => _api.getNetworkRestrictions(p.ref),
                            (m) =>
                                _api.updateNetworkRestrictions(p.ref, m)),
                    child: const Text('Edit restrictions (JSON)'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Network bans',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_bans.isEmpty)
                    const Text('No bans.',
                        style: TextStyle(color: Colors.grey)),
                  ..._bans.map((b) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.block),
                          title: Text(
                              '${b['ipv4_address'] ?? b['ip'] ?? b['id'] ?? ''}'),
                          subtitle: Text('${b['reason'] ?? ''}'),
                        ),
                      )),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                          controller: _banIp,
                          decoration: const InputDecoration(
                              labelText: 'IPv4 address to unban')),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              final ip = _banIp.text.trim();
                              if (ip.isEmpty) return;
                              setState(() => _busy = true);
                              try {
                                await _api
                                    .deleteNetworkBan(p.ref, [ip]);
                                _snack('Ban removed');
                                await _load();
                              } catch (e) {
                                _snack('$e');
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                      child: const Text('Unban'),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  const Text('SSL enforcement',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText(prettyJson(_ssl),
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _editJson(
                            'SSL enforcement',
                            () => _api.getSslEnforcement(p.ref),
                            (m) => _api.updateSslEnforcement(p.ref, m)),
                    child: const Text('Edit SSL enforcement (JSON)'),
                  ),
                  const SizedBox(height: 16),
                  const Text('pgsodium config',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText(prettyJson(_pgsodium),
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _editJson(
                            'pgsodium config',
                            () => _api.getPgsodium(p.ref),
                            (m) => _api.updatePgsodium(p.ref, m)),
                    child: const Text('Edit pgsodium (JSON)'),
                  ),
                ]),
    );
  }
}
