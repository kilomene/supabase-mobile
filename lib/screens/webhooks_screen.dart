import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Platform webhooks (project level, v2).
/// Live: GET/POST/DELETE /v2/projects/{ref}/webhooks/endpoints,
/// PATCH /v2/projects/{ref}/webhooks/endpoints/{id},
/// GET .../{id}/deliveries, POST .../{id}/test,
/// POST /v2/projects/{ref}/webhooks/deliveries/{id}/retry.
/// NOTE: v1 has only /database/webhooks/enable — the endpoints API is
/// v2, and event types are v1.project.* / v1.organization.*.
class WebhooksScreen extends StatefulWidget {
  final SupabaseProject? project;
  const WebhooksScreen({this.project, super.key});
  @override
  State<WebhooksScreen> createState() => _WebhooksScreenState();
}

class _WebhooksScreenState extends State<WebhooksScreen> {
  final _api = ManagementApiClient();
  List<Map<String, dynamic>> _hooks = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;
  final _url = TextEditingController();
  final _events = TextEditingController(text: 'v1.project.created');
  final _description = TextEditingController();
  final _search = TextEditingController();
  String _query = '';

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final rows = await _api.listWebhooks(p.ref);
      if (mounted) setState(() => _hooks = rows);
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
    _url.dispose();
    _events.dispose();
    _description.dispose();
    _search.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Map<String, dynamic> _attrsOf(Map<String, dynamic> h) {
    final data = h['data'];
    if (data is Map) {
      final attrs = data['attributes'];
      if (attrs is Map) return Map<String, dynamic>.from(attrs);
    }
    return h;
  }

  String _idOf(Map<String, dynamic> h) =>
      '${h['id'] ?? (h['data'] is Map ? h['data']['id'] ?? '' : '')}';

  Future<void> _create() async {
    final p = widget.project;
    final url = _url.text.trim();
    if (p == null || url.isEmpty) return;
    final eventTypes = _events.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => {'type': e})
        .toList();
    if (eventTypes.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _api.createWebhook(p.ref, {
        'data': {
          'type': 'endpoint',
          'attributes': {
            'url': url,
            'enabled': true,
            if (_description.text.trim().isNotEmpty)
              'description': _description.text.trim(),
            'event_types': eventTypes,
          }
        }
      });
      _url.clear();
      _description.clear();
      _snack('Webhook created');
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
          body: EmptyView('Pick a project first to manage its webhooks.'));
    }
    final p = widget.project!;
    final visible = _hooks.where((h) {
      if (_query.isEmpty) return true;
      final attrs = _attrsOf(h);
      final url = (attrs['url']?.toString() ?? '').toLowerCase();
      final events = ((attrs['event_types'] as List?)
                  ?.map((e) => e is Map ? e['type'] : e).join(', ') ??
              '')
          .toLowerCase();
      return url.contains(_query) || events.contains(_query);
    }).toList();
    return Scaffold(
      appBar: SupaAppBar('Webhooks — ${p.name}'),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  RichCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('New webhook'),
                        const SizedBox(height: 12),
                        TextField(
                            controller: _url,
                            decoration: const InputDecoration(
                                labelText: 'Endpoint URL (public, https)')),
                        const SizedBox(height: 8),
                        TextField(
                            controller: _events,
                            decoration: const InputDecoration(
                                labelText: 'Event types (comma separated)',
                                hintText:
                                    'v1.project.created, v1.project.paused')),
                        const SizedBox(height: 8),
                        TextField(
                            controller: _description,
                            decoration: const InputDecoration(
                                labelText: 'Description (optional)')),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                              onPressed: _busy ? null : _create,
                              child: const Text('Create webhook')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PreviewSearchBar(
                    controller: _search,
                    hint: 'Search webhooks…',
                    onChanged: (v) =>
                        setState(() => _query = v.toLowerCase()),
                  ),
                  const SizedBox(height: 16),
                  if (visible.isEmpty)
                    const EmptyView('No webhook endpoints yet.'),
                  ...visible.map((h) {
                    final attrs = _attrsOf(h);
                    final id = _idOf(h);
                    final url = attrs['url']?.toString() ?? '';
                    final events =
                        (attrs['event_types'] as List?)
                                ?.map((e) => e is Map ? e['type'] : e)
                                .join(', ') ??
                            '';
                    final enabled = attrs['enabled'] == true;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RichCard(
                        child: Row(children: [
                          const IconTile(
                              icon: Icons.webhook,
                              color: AppTheme.green,
                              bg: AppTheme.green,
                              size: 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(url.isEmpty ? '—' : url,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                if (events.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(events,
                                      style: const TextStyle(
                                          color: AppTheme.muted)),
                                ],
                              ],
                            ),
                          ),
                          Pill(enabled ? 'Enabled' : 'Disabled',
                              bg: enabled
                                  ? AppTheme.green
                                  : Colors.grey.withValues(alpha: 0.2),
                              fg: enabled ? Colors.black : AppTheme.muted),
                          PopupMenuButton<String>(
                            onSelected: (action) async {
                              setState(() => _busy = true);
                              try {
                                switch (action) {
                                  case 'test':
                                    await _api.testWebhook(p.ref, id);
                                    _snack('Test event sent');
                                  case 'deliveries':
                                    final rows = await _api
                                        .listWebhookDeliveries(p.ref, id);
                                    if (!context.mounted) return;
                                    await showJsonDialog(context,
                                        title: 'Deliveries',
                                        value: {'deliveries': rows});
                                  case 'details':
                                    await showJsonDialog(context,
                                        title: 'Webhook', value: h);
                                  case 'delete':
                                    await _api.deleteWebhook(p.ref, id);
                                    _snack('Webhook deleted');
                                    await _load();
                                }
                              } catch (e) {
                                _snack('$e');
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                  value: 'test', child: Text('Send test')),
                              PopupMenuItem(
                                  value: 'deliveries',
                                  child: Text('Deliveries')),
                              PopupMenuItem(
                                  value: 'details', child: Text('Details')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ]),
                      ),
                    );
                  }),
                ]),
    );
  }
}
