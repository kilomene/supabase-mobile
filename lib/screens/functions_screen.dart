import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Edge Functions (preview 7). Live: Management GET
/// /v1/projects/{ref}/functions; invoke is project-host
/// POST /functions/v1/<slug>. Deploy is multipart with server-side
/// bundling — no Deno on-device. NO rollback endpoint.
class FunctionsScreen extends StatefulWidget {
  final SupabaseProject project;
  const FunctionsScreen({required this.project, super.key});
  @override
  State<FunctionsScreen> createState() => _FunctionsScreenState();
}

class _FunctionsScreenState extends State<FunctionsScreen> {
  List<EdgeFunction> _fns = [];
  bool _loading = false;
  String? _error;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final fns =
          await ManagementApiClient().listFunctions(widget.project.ref);
      setState(() => _fns = fns);
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
      appBar: SupaAppBar('Edge Functions — ${widget.project.name}'),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : _fns.isEmpty
                  ? const EmptyView('No Edge Functions deployed yet.')
                  : ListView.builder(
                      itemCount: _fns.length,
                      itemBuilder: (context, i) {
                        final f = _fns[i];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.bolt,
                                color: Colors.green),
                            title: Text(f.slug),
                            subtitle: Text(f.status),
                          ),
                        );
                      },
                    ),
    );
  }
}
