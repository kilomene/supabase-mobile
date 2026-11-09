import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/project_client_registry.dart';
import 'package:supabase_mobile/widgets/common.dart';
import 'package:supabase_mobile/screens/sql_editor_screen.dart';

/// Storage. Live: Storage API /storage/v1/bucket + object list,
/// signed URLs (POST /storage/v1/object/sign/...), image transforms
/// (GET /storage/v1/render/image/public/...). Policies are SQL-only
/// (RLS on storage.objects) — no REST endpoint — the note below links
/// to the SQL Editor instead of faking a policies UI.
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
  final _bucketId = TextEditingController();
  bool _public = false;

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      final buckets = await api.listBuckets();
      if (mounted) setState(() => _buckets = buckets);
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
  void dispose() {
    _bucketId.dispose();
    super.dispose();
  }

  Future<void> _createBucket() async {
    final p = widget.project;
    final id = _bucketId.text.trim();
    if (p == null || id.isEmpty) return;
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      await api.createBucket(id, isPublic: _public);
      _bucketId.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bucket created')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first, then browse its Storage buckets.'));
    }
    final p = widget.project!;
    return Scaffold(
      appBar: SupaAppBar('Storage — ${p.name}'),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.shield),
                      title: const Text('Storage policies are SQL-only'),
                      subtitle: const Text(
                          'No REST endpoint exists for storage policies — they are RLS on storage.objects.'),
                      trailing: TextButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => SqlEditorScreen(
                                    project: p,
                                    initialSql:
                                        "CREATE POLICY \"public read\" ON storage.objects FOR SELECT USING (bucket_id = 'my-bucket');"))),
                        child: const Text('Open SQL'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _bucketId,
                      decoration: const InputDecoration(
                          labelText: 'New bucket id')),
                  Row(children: [
                    const Text('Public'),
                    Switch(
                        value: _public,
                        onChanged: (v) => setState(() => _public = v)),
                    const Spacer(),
                    ElevatedButton(
                        onPressed: _createBucket,
                        child: const Text('Create bucket')),
                  ]),
                  const SizedBox(height: 12),
                  if (_buckets.isEmpty)
                    const EmptyView('No buckets yet.'),
                  ..._buckets.map((b) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.folder),
                          title: Text(b.name),
                          subtitle: Text(b.isPublic ? 'Public' : 'Private'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => _BucketDetailScreen(
                                      project: p, bucket: b))),
                        ),
                      )),
                ]),
    );
  }
}

class _BucketDetailScreen extends StatefulWidget {
  final SupabaseProject project;
  final StorageBucket bucket;
  const _BucketDetailScreen({required this.project, required this.bucket});
  @override
  State<_BucketDetailScreen> createState() => _BucketDetailScreenState();
}

class _BucketDetailScreenState extends State<_BucketDetailScreen> {
  List<StorageObject> _objects = [];
  bool _loading = true;
  String? _error;
  final _width = TextEditingController(text: '800');
  final _height = TextEditingController();
  final _quality = TextEditingController(text: '80');

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = await ProjectClientRegistry().apiClient(widget.project);
      final objects = await api.listObjects(widget.bucket.id);
      if (mounted) setState(() => _objects = objects);
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
  void dispose() {
    _width.dispose();
    _height.dispose();
    _quality.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _signedUrl(String path) async {
    try {
      final api = await ProjectClientRegistry().apiClient(widget.project);
      final url =
          await api.createSignedUrl(widget.bucket.id, path, expiresIn: 3600);
      if (!mounted) return;
      await showJsonDialog(context,
          title: 'Signed URL (1h)',
          value: {'signed_url': url, 'note': 'Prefix with https://<ref>.supabase.co to open.'});
    } catch (e) {
      _snack('$e');
    }
  }

  void _transformUrl(String path) async {
    try {
      // Built locally from the documented render path — no network call
      // until the URL is actually opened. Pro+, <=25 MB, <=50 MP.
      final api = await ProjectClientRegistry().apiClient(widget.project);
      final url = api.imageTransformUrl(widget.bucket.id, path,
          width: int.tryParse(_width.text.trim()),
          height: int.tryParse(_height.text.trim()),
          quality: int.tryParse(_quality.text.trim()));
      if (!mounted) return;
      await showJsonDialog(context,
          title: 'Image transform URL', value: {'url': url});
    } catch (e) {
      _snack('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SupaAppBar('Bucket — ${widget.bucket.name}'),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('Image transform (public render URL)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: _width,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Width'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: _height,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Height (optional)'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: _quality,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Quality'))),
                  ]),
                  const Text('Pro+, ≤25 MB, ≤50 MP, 1–2500 px.',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 12),
                  const Text('Objects',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_objects.isEmpty)
                    const EmptyView('No objects in this bucket.'),
                  ..._objects.map((o) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.insert_drive_file),
                          title: Text(o.name),
                          subtitle: Text(
                              '${o.size == null ? '' : '${o.size} bytes • '}${o.updatedAt ?? ''}'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'signed') {
                                await _signedUrl(o.name);
                              } else if (action == 'transform') {
                                _transformUrl(o.name);
                              } else if (action == 'delete') {
                                try {
                                  final api = await ProjectClientRegistry()
                                      .apiClient(widget.project);
                                  await api.deleteObjects(widget.bucket.id,
                                      [o.name]);
                                  _snack('Object deleted');
                                  await _load();
                                } catch (e) {
                                  _snack('$e');
                                }
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                  value: 'signed',
                                  child: Text('Signed URL (1h)')),
                              PopupMenuItem(
                                  value: 'transform',
                                  child: Text('Image transform URL')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ),
                      )),
                ]),
    );
  }
}
