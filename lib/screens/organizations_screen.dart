import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Organizations. Live: GET /v1/organizations, POST /v1/organizations,
/// GET /v1/organizations/{slug}, GET /v1/organizations/{slug}/members.
/// Member invites/removal are NOT in the live Management API spec, so
/// members are read-only here — the API surface is the limit, not the app.
class OrganizationsScreen extends StatefulWidget {
  const OrganizationsScreen({super.key});
  @override
  State<OrganizationsScreen> createState() => _OrganizationsScreenState();
}

class _OrganizationsScreenState extends State<OrganizationsScreen> {
  final _api = ManagementApiClient();
  late Future<List<Organization>> _future;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _api.listOrganizations();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    try {
      await _api.createOrganization(name: name);
      _name.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Organization created')));
        setState(() => _future = _api.listOrganizations());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SupaAppBar('Organizations'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
              labelText: 'New organization name'),
          onSubmitted: (_) => _create(),
        ),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: _create, child: const Text('Create')),
        const SizedBox(height: 16),
        FutureBuilder<List<Organization>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const LoadingView();
            }
            if (snap.hasError) {
              return ErrorView('${snap.error}',
                  onRetry: () =>
                      setState(() => _future = _api.listOrganizations()));
            }
            final orgs = snap.data ?? const [];
            if (orgs.isEmpty) {
              return const EmptyView('No organizations yet.');
            }
            return Column(
              children: orgs
                  .map((o) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.business),
                          title: Text(o.name),
                          subtitle: Text(
                              '${o.slug}${o.plan == null ? '' : ' • ${o.plan}'}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => OrgDetailScreen(org: o))),
                        ),
                      ))
                  .toList(),
            );
          },
        ),
      ]),
    );
  }
}

class OrgDetailScreen extends StatefulWidget {
  final Organization org;
  const OrgDetailScreen({required this.org, super.key});
  @override
  State<OrgDetailScreen> createState() => _OrgDetailScreenState();
}

class _OrgDetailScreenState extends State<OrgDetailScreen> {
  final _api = ManagementApiClient();
  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  String? _error;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getOrganization(widget.org.slug),
        _api.listOrgMembers(widget.org.slug),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = results[0] as Map<String, dynamic>;
        _members = results[1] as List<Map<String, dynamic>>;
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
    return Scaffold(
      appBar: SupaAppBar('Organization — ${widget.org.name}'),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  SelectableText(prettyJson(_detail),
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 16),
                  const Text('Members',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text(
                      'Member invites and removal are not exposed by the Management API — members are read-only here.',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 8),
                  if (_members.isEmpty)
                    const Text('No members returned.',
                        style: TextStyle(color: Colors.grey)),
                  ..._members.map((m) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(
                              '${m['email'] ?? m['user_id'] ?? m['id'] ?? ''}'),
                          subtitle: Text(
                              '${m['role'] ?? ''} ${m['status'] ?? ''}'.trim()),
                        ),
                      )),
                ]),
    );
  }
}
