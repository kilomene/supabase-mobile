import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Advisors. Live: GET /v1/projects/{ref}/advisors/security and
/// .../advisors/performance. NOTE: no POST .../advisors/run in the live
/// v1 spec — advisors are read-only here.
class AdvisorsScreen extends StatefulWidget {
  final SupabaseProject? project;
  const AdvisorsScreen({this.project, super.key});
  @override
  State<AdvisorsScreen> createState() => _AdvisorsScreenState();
}

class _AdvisorsScreenState extends State<AdvisorsScreen> {
  final _api = ManagementApiClient();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _security = [];
  List<Map<String, dynamic>> _performance = [];

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.securityAdvisors(p.ref),
        _api.performanceAdvisors(p.ref),
      ]);
      if (!mounted) return;
      setState(() {
        _security = results[0];
        _performance = results[1];
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

  Widget _section(String title, List<Map<String, dynamic>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Text('No findings.', style: TextStyle(color: Colors.grey)),
        ...items.map((m) => Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.amber),
                title: Text(
                    '${m['title'] ?? m['name'] ?? m['id'] ?? 'Advisor'}'),
                subtitle: Text(
                    '${m['description'] ?? m['recommendation'] ?? ''}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showJsonDialog(context,
                    title: '${m['title'] ?? m['name'] ?? 'Advisor'}',
                    value: m),
              ),
            )),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first to see its advisors.'));
    }
    return Scaffold(
      appBar: SupaAppBar('Advisors — ${widget.project!.name}',
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  _section('Security', _security),
                  _section('Performance', _performance),
                ]),
    );
  }
}
