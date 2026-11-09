import 'package:flutter/material.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Create New Project (preview 10). Live: POST /v1/projects.
/// db_pass is required and never retrievable later. Poll health until
/// ACTIVE_HEALTHY before configuring Auth etc. (see README).
class CreateProjectScreen extends StatefulWidget {
  const CreateProjectScreen({super.key});
  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _name = TextEditingController();
  final _org = TextEditingController();
  final _pass = TextEditingController();
  String _region = 'eu-west-1';
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final p = await ManagementApiClient().createProject(
        name: _name.text.trim(),
        organizationSlug: _org.text.trim(),
        dbPass: _pass.text,
        region: _region,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Creating ${p.name} — wait for ACTIVE_HEALTHY')));
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SupaAppBar('New Project'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Project name')),
        TextField(
            controller: _org,
            decoration:
                const InputDecoration(labelText: 'Organization slug')),
        TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Database password (never retrievable later)')),
        DropdownButton<String>(
          value: _region,
          items: const ['eu-west-1', 'us-east-1', 'ap-southeast-1']
              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
              .toList(),
          onChanged: (v) => setState(() => _region = v ?? _region),
        ),
        if (_error != null) ErrorView(_error!),
        const SizedBox(height: 12),
        ElevatedButton(
            onPressed: _busy ? null : _create,
            child: const Text('Create project')),
        const Text('Project takes about 2 minutes to provision.',
            style: TextStyle(color: Colors.grey)),
      ]),
    );
  }
}
