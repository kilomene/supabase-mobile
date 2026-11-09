import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/app_state.dart';
import 'package:supabase_mobile/services/project_client_registry.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/widgets/common.dart';
import 'package:supabase_mobile/screens/sql_editor_screen.dart';

/// Storage (preview). Live: Storage API /storage/v1/bucket + object list,
/// signed URLs (POST /storage/v1/object/sign/...), image transforms
/// (GET /storage/v1/render/image/public/...). Policies are SQL-only
/// (RLS on storage.objects) — no REST endpoint — the note below links
/// to the SQL Editor instead of faking a policies UI.
/// Bucket file/size stats come from POST /storage/v1/object/list/{bucket}
/// (limit 100): count = objects returned, size = sum of object sizes.
/// There is no file picker in the app, so Upload says so honestly.
class StorageScreen extends StatefulWidget {
  final SupabaseProject? project;
  const StorageScreen({this.project, super.key});
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _BucketStats {
  final int count;
  final int size;
  final bool capped;
  final List<StorageObject> objects;
  const _BucketStats(
      {required this.count,
      required this.size,
      required this.capped,
      required this.objects});
}

class _RecentFile {
  final String bucketId;
  final StorageObject object;
  const _RecentFile(this.bucketId, this.object);
}

class _StorageScreenState extends State<StorageScreen> {
  List<StorageBucket> _buckets = [];
  Map<String, _BucketStats> _stats = {};
  bool _loading = false;
  String? _error;
  final _bucketId = TextEditingController();
  final _search = TextEditingController();
  bool _public = false;
  bool _showSearch = false;
  bool _filesMode = false;
  StorageBucket? _selectedBucket;
  List<StorageObject> _modeObjects = [];
  bool _modeObjectsLoading = false;

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      final buckets = await api.listBuckets();
      if (!mounted) return;
      setState(() => _buckets = buckets);
      // Per-bucket object stats concurrently; a failed bucket shows "—".
      final stats = await Future.wait(buckets.map((b) async {
        try {
          final objects = await api.listObjects(b.id);
          final size = objects.fold<int>(
              0, (sum, o) => sum + (o.size ?? 0));
          return MapEntry(
              b.id,
              _BucketStats(
                  count: objects.length,
                  size: size,
                  capped: objects.length == 100,
                  objects: objects));
        } catch (_) {
          return MapEntry<String, _BucketStats?>(b.id, null);
        }
      }));
      if (!mounted) return;
      setState(() {
        _stats = {
          for (final e in stats)
            if (e.value != null) e.key: e.value!
        };
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
  void didUpdateWidget(StorageScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.project?.ref != oldWidget.project?.ref) {
      _selectedBucket = null;
      _filesMode = false;
      _load();
    }
  }

  @override
  void dispose() {
    _bucketId.dispose();
    _search.dispose();
    super.dispose();
  }

  List<StorageBucket> get _filteredBuckets {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _buckets;
    return _buckets.where((b) => b.name.toLowerCase().contains(q)).toList();
  }

  List<_RecentFile> get _recentFiles {
    final all = <_RecentFile>[];
    for (final b in _buckets) {
      final s = _stats[b.id];
      if (s == null) continue;
      for (final o in s.objects) {
        all.add(_RecentFile(b.id, o));
      }
    }
    all.sort((a, b) {
      final at = DateTime.tryParse(a.object.updatedAt ?? '');
      final bt = DateTime.tryParse(b.object.updatedAt ?? '');
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return all.take(5).toList();
  }

  Future<void> _loadModeObjects(StorageBucket bucket) async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _modeObjectsLoading = true);
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      final objects = await api.listObjects(bucket.id);
      if (mounted) setState(() => _modeObjects = objects);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _modeObjectsLoading = false);
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _signedUrl(String bucketId, String path) async {
    final p = widget.project;
    if (p == null) return;
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      final url =
          await api.createSignedUrl(bucketId, path, expiresIn: 3600);
      if (!mounted) return;
      await showJsonDialog(context,
          title: 'Signed URL (1h)',
          value: {
            'signed_url': url,
            'note': 'Prefix with https://<ref>.supabase.co to open.'
          });
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _transformUrl(String bucketId, String path) async {
    final p = widget.project;
    if (p == null) return;
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      final url = api.imageTransformUrl(bucketId, path,
          width: 800, quality: 80);
      if (!mounted) return;
      await showJsonDialog(context,
          title: 'Image transform URL', value: {'url': url});
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _deleteObject(String bucketId, String path) async {
    final p = widget.project;
    if (p == null) return;
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      await api.deleteObjects(bucketId, [path]);
      _snack('Object deleted');
      await _load();
      if (_selectedBucket != null) {
        await _loadModeObjects(_selectedBucket!);
      }
    } catch (e) {
      _snack('$e');
    }
  }

  PopupMenuButton<String> _objectMenu(String bucketId, String path) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz, color: AppTheme.muted),
      onSelected: (action) async {
        if (action == 'signed') {
          await _signedUrl(bucketId, path);
        } else if (action == 'transform') {
          await _transformUrl(bucketId, path);
        } else if (action == 'delete') {
          await _deleteObject(bucketId, path);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'signed', child: Text('Signed URL (1h)')),
        PopupMenuItem(value: 'transform', child: Text('Image transform URL')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  bool _isImage(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.gif') ||
        n.endsWith('.webp') ||
        n.endsWith('.heic') ||
        n.endsWith('.avif') ||
        n.endsWith('.bmp');
  }

  /// File-type icon tile — real thumbnails are not fetched; never a
  /// stock photo.
  Widget _fileTile(String name) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
          _isImage(name) ? Icons.image : Icons.insert_drive_file,
          color: AppTheme.muted),
    );
  }

  Widget _fileRow(String bucketId, StorageObject o) {
    return RichCard(
      child: Row(
        children: [
          _fileTile(o.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                    '${o.size == null ? '—' : formatBytes(o.size!)} • ${relativeTime(o.updatedAt)}',
                    style: const TextStyle(color: AppTheme.muted)),
              ],
            ),
          ),
          _objectMenu(bucketId, o.name),
        ],
      ),
    );
  }

  Future<void> _createBucket() async {
    final p = widget.project;
    final id = _bucketId.text.trim();
    if (p == null || id.isEmpty) return;
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      await api.createBucket(id, isPublic: _public);
      _bucketId.clear();
      _snack('Bucket created');
      await _load();
    } catch (e) {
      _snack('$e');
    }
  }

  Widget _modePill(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.transparent : AppTheme.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? AppTheme.green : Colors.transparent, width: 1.5),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? AppTheme.green : AppTheme.text,
                fontWeight: FontWeight.w600,
                fontSize: 16)),
      ),
    );
  }

  Widget _bucketCard(StorageBucket b) {
    final s = _stats[b.id];
    final countLabel = s == null ? '—' : (s.capped ? '100+' : '${s.count}');
    final sizeLabel = s == null ? '—' : formatBytes(s.size);
    return RichCard(
      onTap: () {
        if (_filesMode) {
          setState(() => _selectedBucket = b);
          _loadModeObjects(b);
        } else {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _BucketDetailScreen(
                  project: widget.project!, bucket: b)));
        }
      },
      child: Row(
        children: [
          IconTile(
            icon: Icons.folder,
            color: AppTheme.green,
            bg: b.isPublic ? AppTheme.green : AppTheme.surface2,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.name,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('$countLabel files • $sizeLabel',
                    style: const TextStyle(color: AppTheme.muted)),
              ],
            ),
          ),
          if (b.isPublic)
            const Pill('Public',
                bg: AppTheme.green, fg: Colors.black, icon: Icons.public)
          else
            Pill('Private',
                bg: PreviewColors.dangerRed.withValues(alpha: 0.15),
                fg: PreviewColors.dangerRed,
                border: PreviewColors.dangerRed,
                icon: Icons.lock),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView(
              'Pick a project first, then browse its Storage buckets.'));
    }
    final p = widget.project!;
    final buckets = _filteredBuckets;
    final recent = _recentFiles;
    final modeObjects = _modeObjects
        .where((o) => o.name
            .toLowerCase()
            .contains(_search.text.trim().toLowerCase()))
        .toList();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: AppTheme.surface2,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back),
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () => AppState.instance.clearProject(),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Row(children: [
                        Text(p.name,
                            style: const TextStyle(
                                color: AppTheme.green,
                                fontSize: 17,
                                fontWeight: FontWeight.bold)),
                        const Icon(Icons.keyboard_arrow_down,
                            color: AppTheme.green),
                      ]),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.search, color: AppTheme.muted),
                    onPressed: () =>
                        setState(() => _showSearch = !_showSearch),
                  ),
                  // Decorative icon only — not wired to anything.
                  const Icon(Icons.notifications_outlined,
                      color: AppTheme.muted),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Storage',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  _modePill('Buckets', !_filesMode, () {
                    setState(() {
                      _filesMode = false;
                      _selectedBucket = null;
                    });
                  }),
                  const SizedBox(width: 12),
                  _modePill('Files', _filesMode, () {
                    setState(() => _filesMode = true);
                  }),
                ],
              ),
              if (_showSearch) ...[
                const SizedBox(height: 12),
                PreviewSearchBar(
                  controller: _search,
                  hint: 'Search buckets…',
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: _loading
                    ? const LoadingView()
                    : _error != null
                        ? ErrorView(_error!, onRetry: _load)
                        : ListView(
                            children: [
                              if (_filesMode && _selectedBucket != null) ...[
                                Row(
                                  children: [
                                    const SectionLabel('Files'),
                                    const Spacer(),
                                    InkWell(
                                      onTap: () => setState(
                                          () => _selectedBucket = null),
                                      child: Text(
                                          'Bucket: ${_selectedBucket!.name} ✕',
                                          style: const TextStyle(
                                              color: AppTheme.green)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (_modeObjectsLoading)
                                  const LoadingView()
                                else if (modeObjects.isEmpty)
                                  const EmptyView(
                                      'No objects in this bucket.')
                                else
                                  ...modeObjects.map((o) => Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: 10),
                                        child: _fileRow(
                                            _selectedBucket!.id, o),
                                      )),
                              ] else ...[
                                const SectionLabel('Buckets'),
                                const SizedBox(height: 12),
                                if (buckets.isEmpty)
                                  const EmptyView('No buckets yet.')
                                else
                                  ...buckets.map((b) => Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: 10),
                                        child: _bucketCard(b),
                                      )),
                              ],
                              if (!_filesMode || _selectedBucket == null) ...[
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    const SectionLabel('Recent files'),
                                    const Spacer(),
                                    InkWell(
                                      onTap: () => _snack(
                                          'Upload needs a file — pick one in the bucket detail'),
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: AppTheme.green,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.add,
                                                  size: 18,
                                                  color: Colors.black),
                                              SizedBox(width: 4),
                                              Text('+ Upload',
                                                  style: TextStyle(
                                                      color: Colors.black,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ]),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (recent.isEmpty)
                                  const Text('No files yet.',
                                      style: TextStyle(
                                          color: AppTheme.muted))
                                else
                                  ...recent.map((f) => Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: 10),
                                        child: _fileRow(f.bucketId, f.object),
                                      )),
                                const SizedBox(height: 16),
                                RichCard(
                                  child: Row(
                                    children: [
                                      const Icon(Icons.shield,
                                          color: AppTheme.muted),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                'Storage policies are SQL-only',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            SizedBox(height: 4),
                                            Text(
                                                'No REST endpoint exists for storage policies — they are RLS on storage.objects.',
                                                style: TextStyle(
                                                    color: AppTheme.muted,
                                                    fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).push(
                                                MaterialPageRoute(
                                                    builder: (_) =>
                                                        SqlEditorScreen(
                                                            project: p,
                                                            initialSql:
                                                                "CREATE POLICY \"public read\" ON storage.objects FOR SELECT USING (bucket_id = 'my-bucket');"))),
                                        child: const Text('Open SQL'),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                    controller: _bucketId,
                                    decoration: const InputDecoration(
                                        labelText: 'New bucket id')),
                                Row(children: [
                                  const Text('Public'),
                                  Switch(
                                      value: _public,
                                      onChanged: (v) =>
                                          setState(() => _public = v)),
                                  const Spacer(),
                                  ElevatedButton(
                                      onPressed: _createBucket,
                                      child: const Text('Create bucket')),
                                ]),
                              ],
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
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

  bool _isImage(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.gif') ||
        n.endsWith('.webp') ||
        n.endsWith('.heic') ||
        n.endsWith('.avif') ||
        n.endsWith('.bmp');
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
                  const SizedBox(height: 8),
                  if (_objects.isEmpty)
                    const EmptyView('No objects in this bucket.'),
                  ..._objects.map((o) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: RichCard(
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppTheme.surface2,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                    _isImage(o.name)
                                        ? Icons.image
                                        : Icons.insert_drive_file,
                                    color: AppTheme.muted),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(o.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text(
                                        '${o.size == null ? '—' : formatBytes(o.size!)} • ${relativeTime(o.updatedAt)}',
                                        style: const TextStyle(
                                            color: AppTheme.muted)),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_horiz,
                                    color: AppTheme.muted),
                                onSelected: (action) async {
                                  if (action == 'signed') {
                                    await _signedUrl(o.name);
                                  } else if (action == 'transform') {
                                    _transformUrl(o.name);
                                  } else if (action == 'delete') {
                                    try {
                                      final api =
                                          await ProjectClientRegistry()
                                              .apiClient(widget.project);
                                      await api.deleteObjects(
                                          widget.bucket.id, [o.name]);
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
                            ],
                          ),
                        ),
                      )),
                ]),
    );
  }
}
