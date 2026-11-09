import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/dashboard_links.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Billing & usage. Live: GET /v1/projects/{ref}/billing/addons,
/// usage.api-counts, usage.api-requests-count. Invoices, payments,
/// spend caps and plans have NO endpoint — the dashboard deep-link is
/// the honest path (DashboardOnlyBanner), never invented numbers.
class BillingScreen extends StatefulWidget {
  final SupabaseProject? project;
  const BillingScreen({this.project, super.key});
  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final _api = ManagementApiClient();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _addons = {};
  Map<String, dynamic> _usage = {};
  int _requests = 0;

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.billingAddons(p.ref),
        _api.usageCounts(p.ref),
        _api.apiRequestsCount(p.ref),
      ]);
      if (!mounted) return;
      setState(() {
        _addons = results[0] as Map<String, dynamic>;
        _usage = results[1] as Map<String, dynamic>;
        _requests = results[2] as int;
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
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first to see billing & usage.'));
    }
    final p = widget.project!;
    return Scaffold(
      appBar: SupaAppBar('Billing & Usage — ${p.name}'),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  DashboardOnlyBanner(
                      feature: 'Invoices / payments / plan',
                      onOpenDashboard: () =>
                          DashboardLinks.projectBilling(p.ref)),
                  const SizedBox(height: 12),
                  const Text('Addons (compute / disk / replicas)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText(prettyJson(_addons),
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 16),
                  const Text('Usage & egress',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.show_chart),
                      title: Text('API requests: $_requests'),
                      subtitle: Text(_usage.entries
                          .map((e) => '${e.key}: ${e.value}')
                          .join('\n')),
                    ),
                  ),
                ]),
    );
  }
}
