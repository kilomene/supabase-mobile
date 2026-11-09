import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
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
          body: EmptyView('Pick a project first to manage its domains.'));
    }
    final p = widget.project!;
    return Scaffold(
      appBar: SupaAppBar('Domains — ${p.name}',
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('Custom hostname',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText(prettyJson(_custom),
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _hostname,
                      decoration: const InputDecoration(
                          labelText: 'Hostname (e.g. api.example.com)')),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 16),
                  const Text('Vanity subdomain',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText(prettyJson(_vanity),
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _subdomain,
                      decoration: const InputDecoration(
                          labelText: 'Subdomain to check')),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 16),
                  const Text(
                      'Custom hostnames are a paid add-on (~\$10/mo). DNS records are set on your side — the app only reports what Supabase verifies.',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
    );
  }
}
