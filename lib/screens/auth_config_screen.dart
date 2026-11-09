import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
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
  final _search = TextEditingController();
  String _query = '';

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
    _search.dispose();
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

  bool _matches(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first to configure its Auth.'));
    }
    final p = widget.project!;
    final sso = _sso
        .where((s) => _matches('${s['type'] ?? s['id'] ?? ''}'))
        .toList();
    final keys = _keys
        .where((k) => _matches('${k['id'] ?? ''}'))
        .toList();
    final tpa = _tpa
        .where((t) => _matches('${t['type'] ?? t['id'] ?? ''}'))
        .toList();
    return Scaffold(
      appBar: SupaAppBar('Auth Config — ${p.name}',
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const SectionLabel('Auth config (providers, SMTP, MFA, URLs)'),
                  const SizedBox(height: 8),
                  RichCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          IconTile(
                              icon: Icons.shield,
                              color: AppTheme.green,
                              bg: AppTheme.green,
                              size: 44),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text('Auth config',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        SelectableText(prettyJson(_config),
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
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
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PreviewSearchBar(
                    controller: _search,
                    hint: 'Search providers, keys…',
                    onChanged: (v) =>
                        setState(() => _query = v.toLowerCase()),
                  ),
                  const SizedBox(height: 16),
                  const SectionLabel('SSO providers'),
                  const SizedBox(height: 8),
                  RichCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                            controller: _ssoType,
                            decoration: const InputDecoration(
                                labelText: 'Type (e.g. saml)')),
                        const SizedBox(height: 8),
                        TextField(
                            controller: _ssoMetadataUrl,
                            decoration: const InputDecoration(
                                labelText: 'Metadata URL')),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
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
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (sso.isEmpty)
                    const Text('No SSO providers.',
                        style: TextStyle(color: AppTheme.muted)),
                  ...sso.map((s) {
                    final type = '${s['type'] ?? s['id'] ?? 'provider'}';
                    final domains = '${s['domains'] ?? ''}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RichCard(
                        onTap: () => showJsonDialog(context,
                            title: 'SSO provider', value: s),
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
                                Text(type,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                if (domains.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(domains,
                                      style: const TextStyle(
                                          color: AppTheme.muted)),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete,
                                color: PreviewColors.dangerRed),
                            onPressed: _busy
                                ? null
                                : () => _act(
                                    'SSO provider deleted',
                                    () => _api.deleteSsoProvider(
                                        p.ref, '${s['id'] ?? ''}')),
                          ),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  const SectionLabel('Signing keys'),
                  const SizedBox(height: 8),
                  if (keys.isEmpty)
                    const Text('No signing keys returned.',
                        style: TextStyle(color: AppTheme.muted)),
                  ...keys.map((k) {
                    final id = '${k['id'] ?? ''}';
                    final created = '${k['created_at'] ?? ''}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RichCard(
                        child: Row(children: [
                          const IconTile(
                              icon: Icons.vpn_key,
                              color: AppTheme.green,
                              bg: AppTheme.green,
                              size: 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(id.isEmpty ? '—' : id,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                if (created.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(relativeTime(created),
                                      style: const TextStyle(
                                          color: AppTheme.muted)),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete,
                                color: PreviewColors.dangerRed),
                            onPressed: _busy
                                ? null
                                : () => _act(
                                    'Signing key deleted',
                                    () => _api.deleteSigningKey(
                                        p.ref, id)),
                          ),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  const SectionLabel('Third-party auth'),
                  const SizedBox(height: 8),
                  if (tpa.isEmpty)
                    const Text('No third-party auth configured.',
                        style: TextStyle(color: AppTheme.muted)),
                  ...tpa.map((t) {
                    final type = '${t['type'] ?? t['id'] ?? ''}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RichCard(
                        onTap: () => showJsonDialog(context,
                            title: 'Third-party auth', value: t),
                        child: Row(children: [
                          const IconTile(
                              icon: Icons.link,
                              color: AppTheme.green,
                              bg: AppTheme.green,
                              size: 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(type.isEmpty ? '—' : type,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete,
                                color: PreviewColors.dangerRed),
                            onPressed: _busy
                                ? null
                                : () => _act(
                                    'Third-party auth deleted',
                                    () => _api.deleteThirdPartyAuth(
                                        p.ref, '${t['id'] ?? ''}')),
                          ),
                        ]),
                      ),
                    );
                  }),
                ]),
    );
  }
}
