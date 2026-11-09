import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/project_client_registry.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Storage (preview 6). Live: Storage API /storage/v1/bucket + object
/// list. Policies are SQL-only (RLS on storage.objects) — no REST.
class StorageScreen extends StatefulWidget {
  final SupabaseProject? project;
  const StorageScreen({this.project, super.key});
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  List<StorageBucket> _buckets = [];
  bool _loading = false;
  String? _error;

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      final buckets = await api.listBuckets();
      setState(() => _buckets = buckets);
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
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first, then browse its Storage buckets.'));
    }
    return Scaffold(
      appBar: SupaAppBar('Storage — ${widget.project!.name}'),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : _buckets.isEmpty
                  ? const EmptyView('No buckets yet.')
                  : ListView.builder(
                      itemCount: _buckets.length,
                      itemBuilder: (context, i) {
                        final b = _buckets[i];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.folder),
                            title: Text(b.name),
                            subtitle: Text(b.isPublic ? 'Public' : 'Private'),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        );
                      },
                    ),
    );
  }
}
