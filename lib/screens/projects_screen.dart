import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/widgets/common.dart';
import 'package:supabase_mobile/screens/create_project_screen.dart';
import 'package:supabase_mobile/screens/table_editor_screen.dart';

/// Projects list (preview 2). Live: GET /v1/projects.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _api = ManagementApiClient();
  late Future<List<SupabaseProject>> _future;
  @override
  void initState() {
    super.initState();
    _future = _api.listProjects();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SupaAppBar('Projects'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const CreateProjectScreen())),
        label: const Text('New Project'),
        icon: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<SupabaseProject>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }
          if (snap.hasError) {
            return ErrorView('${snap.error}',
                onRetry: () => setState(() => _future = _api.listProjects()));
          }
          final projects = snap.data ?? const [];
          if (projects.isEmpty) {
            return const EmptyView('No projects yet. Create your first project.');
          }
          return RefreshIndicator(
            onRefresh: () async =>
                setState(() => _future = _api.listProjects()),
            child: ListView.builder(
              itemCount: projects.length,
              itemBuilder: (context, i) {
                final p = projects[i];
                return Card(
                  child: ListTile(
                    leading: Icon(Icons.circle,
                        color: p.isActive ? Colors.green : Colors.grey, size: 12),
                    title: Text(p.name),
                    subtitle: Text('${p.region} • ${p.status} • ${p.ref}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => TableEditorScreen(project: p))),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
