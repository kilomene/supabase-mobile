import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Auth configuration. Live: GET/PATCH /v1/projects/{ref}/config/auth,
/// SSO providers (GET/POST/PUT/DELETE .../config/auth/sso/providers),
/// signing keys (GET/POST/DELETE .../config/auth/signing-keys),
/// third-party auth (GET/POST/DELETE .../config/auth/third-party-auth).
/// Provider secrets are pasted by the user in the JSON editor and sent
/// straight to the API — never stored by the app.
class AuthConfigScreen extends StatefulWidget {
  final SupabaseProject? project;
  const AuthConfigScreen({this.project, super.key});
  @override
  State<AuthConfigScreen> createState() => _AuthConfigScreenState();
}

class _AuthConfigScreenState extends State<AuthConfigScreen> {
  final _api = ManagementApiClient();
  bool _loading = true;
  String? _error;
  bool _busy = false;
  Map<String, dynamic>? _config;
  List<Map<String, dynamic>> _sso = [];
  List<Map<String, dynamic>> _keys = [];
  List<Map<String, dynamic>> _tpa = [];
  final _ssoType = TextEditingController();
  final _ssoMetadataUrl = TextEditingController();

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getAuthConfig(p.ref),
        _api.listSsoProviders(p.ref),
        _api.listSigningKeys(p.ref),
        _api.listThirdPartyAuth(p.ref),
      ]);
      if (!mounted) return;
      setState(() {
        _config = results[0] as Map<String, dynamic>;
        _sso = results[1] as List<Map<String, dynamic>>;
        _keys = results[2] as List<Map<String, dynamic>>;
        _tpa = results[3] as List<Map<String, dynamic>>;
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
    _ssoType.dispose();
    _ssoMetadataUrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _act(String done, Future<void> Function() call) async {
    setState(() => _busy = true);
    try {
      await call();
      _snack(done);
      await _load();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first to configure its Auth.'));
    }
    final p = widget.project!;
    return Scaffold(
      appBar: SupaAppBar('Auth Config — ${p.name}',
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('Auth config (providers, SMTP, MFA, URLs)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SelectableText(prettyJson(_config),
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            try {
                              final current =
                                  await _api.getAuthConfig(p.ref);
                              if (!context.mounted) return;
                              final edited = await showJsonEditor(context,
                                  title: 'Edit Auth config',
                                  initial: current);
                              if (edited == null) return;
                              await _api.updateAuthConfig(p.ref, edited);
                              _snack('Auth config saved');
                              await _load();
                            } catch (e) {
                              _snack('$e');
                            }
                          },
                    child: const Text('Edit Auth config (JSON)'),
                  ),
                  const SizedBox(height: 16),
                  const Text('SSO providers',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextField(
                      controller: _ssoType,
                      decoration: const InputDecoration(
                          labelText: 'Type (e.g. saml)')),
                  TextField(
                      controller: _ssoMetadataUrl,
                      decoration: const InputDecoration(
                          labelText: 'Metadata URL')),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final type = _ssoType.text.trim();
                            final url = _ssoMetadataUrl.text.trim();
                            if (type.isEmpty) return;
                            await _act(
                                'SSO provider created',
                                () => _api.createSsoProvider(p.ref, {
                                      'type': type,
                                      if (url.isNotEmpty)
                                        'metadata_url': url,
                                    }));
                            _ssoType.clear();
                            _ssoMetadataUrl.clear();
                          },
                    child: const Text('Add SSO provider'),
                  ),
                  const SizedBox(height: 8),
                  if (_sso.isEmpty)
                    const Text('No SSO providers.',
                        style: TextStyle(color: Colors.grey)),
                  ..._sso.map((s) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.key),
                          title: Text(
                              '${s['type'] ?? s['id'] ?? 'provider'}'),
                          subtitle:
                              Text('${s['domains'] ?? ''}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: _busy
                                ? null
                                : () => _act(
                                    'SSO provider deleted',
                                    () => _api.deleteSsoProvider(
                                        p.ref, '${s['id'] ?? ''}')),
                          ),
                          onTap: () => showJsonDialog(context,
                              title: 'SSO provider', value: s),
                        ),
                      )),
                  const SizedBox(height: 16),
                  const Text('Signing keys',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_keys.isEmpty)
                    const Text('No signing keys returned.',
                        style: TextStyle(color: Colors.grey)),
                  ..._keys.map((k) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.vpn_key),
                          title: Text('${k['id'] ?? ''}'),
                          subtitle: Text('${k['created_at'] ?? ''}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: _busy
                                ? null
                                : () => _act(
                                    'Signing key deleted',
                                    () => _api.deleteSigningKey(
                                        p.ref, '${k['id'] ?? ''}')),
                          ),
                        ),
                      )),
                  const SizedBox(height: 16),
                  const Text('Third-party auth',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_tpa.isEmpty)
                    const Text('No third-party auth configured.',
                        style: TextStyle(color: Colors.grey)),
                  ..._tpa.map((t) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.link),
                          title: Text('${t['type'] ?? t['id'] ?? ''}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: _busy
                                ? null
                                : () => _act(
                                    'Third-party auth deleted',
                                    () => _api.deleteThirdPartyAuth(
                                        p.ref, '${t['id'] ?? ''}')),
                          ),
                          onTap: () => showJsonDialog(context,
                              title: 'Third-party auth', value: t),
                        ),
                      )),
                ]),
    );
  }
}
