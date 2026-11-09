import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/services/secure_token_storage.dart';
import 'package:supabase_mobile/services/dashboard_links.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Settings — API keys (preview 3). Live: GET
/// /v1/projects/{ref}/api-keys. The publishable and legacy keys come
/// from that endpoint; a key row is shown only when the API returns a
/// value for it. The secret key is NEVER fetched or invented — it is
/// the user-pasted per-project secret from secure storage, shown masked
/// with an eye toggle, or "not saved on this device" when absent.
/// Keys are never shown in full unless the API returns them, and the
/// secret key is stored only in secure storage, never logged.
class SettingsApiScreen extends StatefulWidget {
  final SupabaseProject project;
  const SettingsApiScreen({required this.project, super.key});
  @override
  State<SettingsApiScreen> createState() => _SettingsApiScreenState();
}

class _SettingsApiScreenState extends State<SettingsApiScreen> {
  List<ApiKeyItem> _keys = [];
  bool _loading = false;
  String? _error;
  String? _secret;
  bool _showPub = false;
  bool _showSecret = false;
  bool _busy = false;
  final _pub = TextEditingController();
  final _secretField = TextEditingController();

  @override
  void dispose() {
    _pub.dispose();
    _secretField.dispose();
    super.dispose();
  }

  ApiKeyItem? _findKey(String needle) {
    final n = needle.toLowerCase();
    for (final k in _keys) {
      final hay = '${k.name} ${k.type ?? ''}'.toLowerCase();
      if (hay.contains(n)) return k;
    }
    return null;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final keys =
          await ManagementApiClient().listApiKeys(widget.project.ref);
      final secret =
          await SecureTokenStorage().readProjectSecret(widget.project.ref);
      if (mounted) {
        setState(() {
          _keys = keys;
          _secret = secret;
        });
      }
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

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _generateKey() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate new key'),
        content: TextField(
          controller: nameController,
          decoration:
              const InputDecoration(labelText: 'Key name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pop(nameController.text.trim()),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ManagementApiClient()
          .createApiKey(widget.project.ref, {'name': name});
      _snack('Key generated');
      await _load();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _keyCard({
    required String value,
    required bool revealed,
    required VoidCallback onToggleEye,
    bool showCopy = true,
    Widget? below,
  }) {
    return RichCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(revealed ? value : maskKey(value),
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 15)),
              ),
              IconButton(
                icon: Icon(
                    revealed ? Icons.visibility_off : Icons.visibility,
                    color: AppTheme.muted),
                tooltip: revealed ? 'Hide' : 'Reveal',
                onPressed: onToggleEye,
              ),
              if (showCopy) CopyButton(value),
            ],
          ),
          if (below != null) ...[
            const SizedBox(height: 8),
            below,
          ],
        ],
      ),
    );
  }

  Widget _legacyRow({
    required String label,
    required String value,
    bool lock = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              if (lock) ...[
                const SizedBox(width: 8),
                const Icon(Icons.lock, size: 18, color: AppTheme.muted),
              ],
            ],
          ),
        ),
        Text(maskKey(value),
            style: const TextStyle(
                fontFamily: 'monospace',
                color: AppTheme.muted,
                fontSize: 14)),
        CopyButton(value),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pub = _findKey('publishable');
    final anon = _findKey('anon');
    final serviceRole = _findKey('service_role');
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SupaBolt(size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.project.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz),
                onSelected: (v) {
                  if (v == 'dashboard') {
                    DashboardLinks.open(Uri.parse(
                        'https://supabase.com/dashboard/project/${widget.project.ref}/settings/api'));
                  } else if (v == 'refresh') {
                    _load();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                      value: 'dashboard',
                      child: Text('Manage in dashboard')),
                  PopupMenuItem(
                      value: 'refresh', child: Text('Refresh keys')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Settings — API',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          if (_loading) const LoadingView(),
          if (_error != null) ErrorView(_error!, onRetry: _load),
          const Text('Project URL',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          RichCard(
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.project.url,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 15)),
                ),
                CopyButton(widget.project.url),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Publishable key',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (pub == null || pub.apiKey == null || pub.apiKey!.isEmpty)
            const RichCard(
              child: Text(
                  'No publishable key returned by the API. Paste one below to connect this project.',
                  style: TextStyle(color: AppTheme.muted)),
            )
          else
            _keyCard(
              value: pub.apiKey!,
              revealed: _showPub,
              onToggleEye: () => setState(() => _showPub = !_showPub),
            ),
          const SizedBox(height: 24),
          const Text('Secret key',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_secret == null || _secret!.isEmpty)
            const RichCard(
              child: Text(
                  'Not saved on this device — paste it below.',
                  style: TextStyle(color: AppTheme.muted)),
            )
          else
            _keyCard(
              value: _secret!,
              revealed: _showSecret,
              onToggleEye: () =>
                  setState(() => _showSecret = !_showSecret),
              showCopy: false,
              below: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: PreviewColors.warnYellow.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: PreviewColors.warnYellow),
                  SizedBox(width: 6),
                  Text('Server only — never share',
                      style: TextStyle(
                          color: PreviewColors.warnYellow,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          const SizedBox(height: 24),
          const SectionLabel('Legacy keys'),
          const SizedBox(height: 8),
          if ((anon == null || anon.apiKey == null || anon.apiKey!.isEmpty) &&
              (serviceRole == null ||
                  serviceRole.apiKey == null ||
                  serviceRole.apiKey!.isEmpty))
            const RichCard(
              child: Text('No legacy keys returned by the API.',
                  style: TextStyle(color: AppTheme.muted)),
            )
          else
            RichCard(
              child: Column(
                children: [
                  if (anon != null &&
                      anon.apiKey != null &&
                      anon.apiKey!.isNotEmpty)
                    _legacyRow(label: 'anon (public)', value: anon.apiKey!),
                  if (anon != null &&
                      anon.apiKey != null &&
                      anon.apiKey!.isNotEmpty &&
                      serviceRole != null &&
                      serviceRole.apiKey != null &&
                      serviceRole.apiKey!.isNotEmpty)
                    const Divider(height: 24),
                  if (serviceRole != null &&
                      serviceRole.apiKey != null &&
                      serviceRole.apiKey!.isNotEmpty)
                    _legacyRow(
                        label: 'service_role (secret)',
                        value: serviceRole.apiKey!,
                        lock: true),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _generateKey,
                  icon: const Icon(Icons.add),
                  label: const Text('Generate new key'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => DashboardLinks.open(Uri.parse(
                      'https://supabase.com/dashboard/project/${widget.project.ref}/settings/api')),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Manage in dashboard'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.text,
                    side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          DashboardOnlyBanner(
              feature: 'Billing / invoices',
              onOpenDashboard: () =>
                  DashboardLinks.projectBilling(widget.project.ref)),
          const SizedBox(height: 24),
          const Text('Connect this project (keys stay on this device)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
              controller: _pub,
              decoration: const InputDecoration(
                  labelText: 'Publishable key (sb_publishable_…)')),
          const SizedBox(height: 8),
          TextField(
              controller: _secretField,
              decoration: const InputDecoration(
                  labelText:
                      'Secret key (sb_secret_…) — optional, server-only')),
          const SizedBox(height: 8),
          const Text(
              'Warning: the secret key bypasses Row Level Security. Only paste it if you need Auth Admin. It is stored only in Keychain/Keystore.',
              style: TextStyle(color: Colors.amber, fontSize: 12)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () async {
              await SecureTokenStorage().saveProjectKeys(
                  ref: widget.project.ref,
                  publishableKey: _pub.text.trim(),
                  secretKey: _secretField.text.trim());
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Keys saved securely')));
              }
              await _load();
            },
            child: const Text('Save keys securely'),
          ),
        ]),
      ),
    );
  }
}
