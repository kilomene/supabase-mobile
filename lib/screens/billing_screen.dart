import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/dashboard_links.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
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

  /// Egress, when the usage endpoint reports one — otherwise honest '—'.
  String get _egress {
    for (final e in _usage.entries) {
      if (e.key.toLowerCase().contains('egress')) {
        final v = e.value;
        if (v is int) return formatBytes(v);
        if (v is num) return formatBytes(v.toInt());
        return '$v';
      }
    }
    return '—';
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
                  const SizedBox(height: 16),
                  RichCard(
                    child: Row(children: [
                      Expanded(
                          child: StatColumn(
                              label: 'API requests',
                              value: formatCompact(_requests))),
                      Expanded(
                          child:
                              StatColumn(label: 'Egress', value: _egress)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  const SectionLabel('Addons (compute / disk / replicas)'),
                  const SizedBox(height: 8),
                  RichCard(
                    child: SelectableText(prettyJson(_addons),
                        style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 16),
                  const SectionLabel('Usage & egress'),
                  const SizedBox(height: 8),
                  RichCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const IconTile(
                              icon: Icons.show_chart,
                              color: AppTheme.green,
                              bg: AppTheme.green,
                              size: 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Usage & egress',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                const SizedBox(height: 2),
                                Text('API requests: ${formatCompact(_requests)}',
                                    style: const TextStyle(
                                        color: AppTheme.muted)),
                              ],
                            ),
                          ),
                        ]),
                        if (_usage.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text('No usage returned.',
                                style: TextStyle(color: AppTheme.muted)),
                          ),
                        ..._usage.entries.map((e) => Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(e.key,
                                      style: const TextStyle(
                                          color: AppTheme.muted)),
                                  Text('${e.value}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                ]),
    );
  }
}
