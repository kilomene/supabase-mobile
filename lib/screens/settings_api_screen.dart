import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/services/secure_token_storage.dart';
import 'package:supabase_mobile/services/dashboard_links.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Settings — API keys (preview 9). Live: GET
/// /v1/projects/{ref}/api-keys. Secret value needs API Key Secrets Read.
/// Keys are NEVER shown in full unless the API returns them, and the
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
  final _pub = TextEditingController();
  final _secret = TextEditingController();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final keys =
          await ManagementApiClient().listApiKeys(widget.project.ref);
      setState(() => _keys = keys);
    } catch (e) {
      setState(() => _error = '$e');
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SupaAppBar('Settings — API (${widget.project.name})'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Project URL: ${widget.project.url}'),
        const SizedBox(height: 12),
        if (_loading) const LoadingView(),
        if (_error != null) ErrorView(_error!, onRetry: _load),
        ..._keys.map((k) => Card(
              child: ListTile(
                  title: Text(k.name),
                  subtitle: Text(k.apiKey ?? '(value not returned)')),
            )),
        const SizedBox(height: 16),
        DashboardOnlyBanner(
            feature: 'Billing / invoices',
            onOpenDashboard: () =>
                DashboardLinks.projectBilling(widget.project.ref)),
        const SizedBox(height: 16),
        const Text('Connect this project (keys stay on this device)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        TextField(
            controller: _pub,
            decoration: const InputDecoration(
                labelText: 'Publishable key (sb_publishable_…)')),
        TextField(
            controller: _secret,
            decoration: const InputDecoration(
                labelText: 'Secret key (sb_secret_…) — optional, server-only')),
        const Text(
            'Warning: the secret key bypasses Row Level Security. Only paste it if you need Auth Admin. It is stored only in Keychain/Keystore.',
            style: TextStyle(color: Colors.amber, fontSize: 12)),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () async {
            await SecureTokenStorage().saveProjectKeys(
                ref: widget.project.ref,
                publishableKey: _pub.text.trim(),
                secretKey: _secret.text.trim());
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Keys saved securely')));
            }
          },
          child: const Text('Save keys securely'),
        ),
      ]),
    );
  }
}
