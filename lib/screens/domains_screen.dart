import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Custom domains & vanity subdomains. Live:
/// POST /v1/projects/{ref}/custom-hostname/initialize,
/// GET/PATCH /v1/projects/{ref}/custom-hostname, POST .../activate,
/// POST .../reverify, DELETE .../custom-hostname;
/// GET /v1/projects/{ref}/vanity-subdomain,
/// POST .../check-availability, POST .../activate, DELETE.
/// DNS itself is the user's side — the app shows what Supabase reports.
class DomainsScreen extends StatefulWidget {
  final SupabaseProject? project;
  const DomainsScreen({this.project, super.key});
  @override
  State<DomainsScreen> createState() => _DomainsScreenState();
}

class _DomainsScreenState extends State<DomainsScreen> {
  final _api = ManagementApiClient();
  bool _loading = true;
  String? _error;
  bool _busy = false;
  Map<String, dynamic>? _custom;
  Map<String, dynamic>? _vanity;
  final _hostname = TextEditingController();
  final _subdomain = TextEditingController();
  final _search = TextEditingController();
  String _query = '';

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      Map<String, dynamic>? custom;
      Map<String, dynamic>? vanity;
      try {
        custom = await _api.getCustomHostname(p.ref);
      } catch (_) {
        custom = null;
      }
      try {
        vanity = await _api.getVanitySubdomain(p.ref);
      } catch (_) {
        vanity = null;
      }
      if (!mounted) return;
      setState(() {
        _custom = custom;
        _vanity = vanity;
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
    _hostname.dispose();
    _subdomain.dispose();
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

  Pill _statusPill(Map<String, dynamic>? data) {
    final status = '${data?['status'] ?? ''}';
    if (status.isEmpty) {
      return Pill('Not configured',
          bg: Colors.grey.withValues(alpha: 0.2), fg: AppTheme.muted);
    }
    final s = status.toUpperCase();
    if (s.contains('ACTIVE') || s.contains('VERIFIED') || s.contains('OK')) {
      return Pill(status, bg: AppTheme.green, fg: Colors.black);
    }
    return Pill(status,
        bg: Colors.grey.withValues(alpha: 0.2), fg: AppTheme.muted);
  }

  String _hostnameOf(Map<String, dynamic>? data) =>
      '${data?['custom_hostname'] ?? data?['hostname'] ?? data?['domain'] ?? ''}';

  String _subdomainOf(Map<String, dynamic>? data) =>
      '${data?['vanity_subdomain'] ?? data?['subdomain'] ?? data?['domain'] ?? ''}';

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first to manage its domains.'));
    }
    final p = widget.project!;
    final customName = _hostnameOf(_custom);
    final vanityName = _subdomainOf(_vanity);
    final showCustom = _query.isEmpty ||
        customName.toLowerCase().contains(_query) ||
        'custom hostname'.contains(_query);
    final showVanity = _query.isEmpty ||
        vanityName.toLowerCase().contains(_query) ||
        'vanity subdomain'.contains(_query);
    return Scaffold(
      appBar: SupaAppBar('Domains — ${p.name}',
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  PreviewSearchBar(
                    controller: _search,
                    hint: 'Search domains…',
                    onChanged: (v) =>
                        setState(() => _query = v.toLowerCase()),
                  ),
                  const SizedBox(height: 16),
                  if (showCustom) ...[
                    const SectionLabel('Custom hostname'),
                    const SizedBox(height: 8),
                    RichCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const IconTile(
                                icon: Icons.language,
                                color: AppTheme.green,
                                bg: AppTheme.green,
                                size: 44),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      customName.isEmpty
                                          ? 'No custom hostname'
                                          : customName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  const SizedBox(height: 2),
                                  const Text('Custom hostname',
                                      style: TextStyle(
                                          color: AppTheme.muted)),
                                ],
                              ),
                            ),
                            _statusPill(_custom),
                          ]),
                          const SizedBox(height: 12),
                          SelectableText(prettyJson(_custom),
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 12),
                          TextField(
                              controller: _hostname,
                              decoration: const InputDecoration(
                                  labelText:
                                      'Hostname (e.g. api.example.com)')),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            ElevatedButton(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      final h = _hostname.text.trim();
                                      if (h.isEmpty) return;
                                      _act(
                                          'Custom hostname initialized',
                                          () => _api.initCustomHostname(
                                              p.ref, {'hostname': h}));
                                    },
                              child: const Text('Initialize'),
                            ),
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _act('Activated',
                                      () => _api.activateCustomHostname(p.ref)),
                              child: const Text('Activate'),
                            ),
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _act('Re-verification requested',
                                      () => _api.reverifyCustomHostname(p.ref)),
                              child: const Text('Reverify'),
                            ),
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _act('Custom hostname removed',
                                      () => _api.deleteCustomHostname(p.ref)),
                              child: const Text('Delete'),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (showVanity) ...[
                    const SectionLabel('Vanity subdomain'),
                    const SizedBox(height: 8),
                    RichCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const IconTile(
                                icon: Icons.subdirectory_arrow_right,
                                color: AppTheme.green,
                                bg: AppTheme.green,
                                size: 44),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      vanityName.isEmpty
                                          ? 'No vanity subdomain'
                                          : vanityName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  const SizedBox(height: 2),
                                  const Text('Vanity subdomain',
                                      style: TextStyle(
                                          color: AppTheme.muted)),
                                ],
                              ),
                            ),
                            _statusPill(_vanity),
                          ]),
                          const SizedBox(height: 12),
                          SelectableText(prettyJson(_vanity),
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 12),
                          TextField(
                              controller: _subdomain,
                              decoration: const InputDecoration(
                                  labelText: 'Subdomain to check')),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            ElevatedButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final s = _subdomain.text.trim();
                                      if (s.isEmpty) return;
                                      setState(() => _busy = true);
                                      try {
                                        final r = await _api
                                            .checkVanityAvailability(p.ref, s);
                                        if (!context.mounted) return;
                                        await showJsonDialog(context,
                                            title: 'Availability', value: r);
                                      } catch (e) {
                                        _snack('$e');
                                      } finally {
                                        if (mounted) setState(() => _busy = false);
                                      }
                                    },
                              child: const Text('Check availability'),
                            ),
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      final s = _subdomain.text.trim();
                                      if (s.isEmpty) return;
                                      _act(
                                          'Vanity subdomain activated',
                                          () => _api.activateVanitySubdomain(
                                              p.ref, {'subdomain': s}));
                                    },
                              child: const Text('Activate'),
                            ),
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _act('Vanity subdomain removed',
                                      () => _api.deleteVanitySubdomain(p.ref)),
                              child: const Text('Delete'),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text(
                      'Custom hostnames are a paid add-on (~\$10/mo). DNS records are set on your side — the app only reports what Supabase verifies.',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                ]),
    );
  }
}
