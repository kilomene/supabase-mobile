import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/app_state.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/widgets/common.dart';
import 'package:supabase_mobile/screens/create_project_screen.dart';
import 'package:supabase_mobile/screens/dashboard_screen.dart';

/// Projects list (preview). Live: GET /v1/projects for the list.
/// Per-project stats are live too: GET /v1/projects/{ref}/config/disk/util
/// (database size) and GET .../analytics/endpoints/usage.api-requests-count
/// (API requests today). No endpoint gives a total row count per project,
/// so the preview's rows item is omitted entirely — never hardcoded.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectStats {
  final String? diskSize;
  final int? apiRequests;
  const _ProjectStats({this.diskSize, this.apiRequests});
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _api = ManagementApiClient();
  final _search = TextEditingController();
  List<SupabaseProject> _projects = [];
  Map<String, _ProjectStats> _stats = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<String?> _diskSize(String ref) async {
    try {
      final util = await _api.getDiskUtil(ref);
      return _diskSizeFrom(util);
    } catch (_) {
      return null;
    }
  }

  Future<int?> _apiRequests(String ref) async {
    try {
      return await _api.apiRequestsCount(ref);
    } catch (_) {
      return null;
    }
  }

  /// Defensive parse of the disk-util payload: candidate keys may hold
  /// gigabytes, megabytes, bytes, or a bare number. Unknown shape -> null
  /// (shown as "—"), never a guessed number.
  String? _diskSizeFrom(Map<String, dynamic> util) {
    final data = util['data'] is Map<String, dynamic>
        ? util['data'] as Map<String, dynamic>
        : util;
    const keys = [
      'disk_used_gb',
      'used_gb',
      'size_gb',
      'disk_size_gb',
      'disk_used_mb',
      'used_mb',
      'disk_used_bytes',
      'used_bytes',
      'disk_used',
      'used',
      'size',
      'disk_size',
    ];
    for (final key in keys) {
      final v = data[key];
      num? n;
      if (v is num) {
        n = v;
      } else if (v is String) {
        n = num.tryParse(v);
      }
      if (n == null) continue;
      if (key.contains('_gb')) {
        return formatBytes((n * 1073741824).round());
      }
      if (key.contains('_mb')) {
        return formatBytes((n * 1048576).round());
      }
      if (key.contains('byte')) return formatBytes(n.round());
      // Bare key: small values are gigabytes, large values are bytes.
      return formatBytes(
          n < 10000 ? (n * 1073741824).round() : n.round());
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final projects = await _api.listProjects();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _loading = false;
      });
      // Per-project stats concurrently; a failed stat shows "—" and
      // never blocks the list.
      final stats = await Future.wait(projects.map((p) async {
        final disk = await _diskSize(p.ref);
        final req = await _apiRequests(p.ref);
        return MapEntry(
            p.ref, _ProjectStats(diskSize: disk, apiRequests: req));
      }));
      if (!mounted) return;
      setState(() => _stats = Map.fromEntries(stats));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  List<SupabaseProject> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _projects;
    return _projects
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.region.toLowerCase().contains(q) ||
            p.ref.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final projects = _filtered;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.green,
        foregroundColor: Colors.black,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const CreateProjectScreen())),
        label: const Text('+ New Project',
            style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text('Projects',
                      style: TextStyle(
                          fontSize: 32, fontWeight: FontWeight.bold)),
                  Spacer(),
                  // No profile endpoint exists, so no initials are invented.
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppTheme.surface2,
                    child: Text('?',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              PreviewSearchBar(
                controller: _search,
                hint: 'Search projects…',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _loading
                    ? const LoadingView()
                    : _error != null
                        ? ErrorView(_error!, onRetry: _load)
                        : _projects.isEmpty
                            ? const EmptyView(
                                'No projects yet. Create your first project.')
                            : projects.isEmpty
                                ? const EmptyView(
                                    'No projects match that search.')
                                : RefreshIndicator(
                                    onRefresh: _load,
                                    child: ListView.separated(
                                      itemCount: projects.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 12),
                                      itemBuilder: (context, i) {
                                        final p = projects[i];
                                        final s = _stats[p.ref];
                                        return RichCard(
                                          onTap: () {
                                            // Shared selection: every tab
                                            // now works on this project.
                                            AppState.instance.selectProject(p);
                                            Navigator.of(context).push(
                                                MaterialPageRoute(
                                                    builder: (_) =>
                                                        DashboardScreen(
                                                            project: p)));
                                          },
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    width: 12,
                                                    height: 12,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: p.isActive
                                                          ? AppTheme.green
                                                          : Colors.grey,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(p.name,
                                                        style: const TextStyle(
                                                            fontSize: 18,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                  ),
                                                  projectStatusPill(p.status),
                                                ],
                                              ),
                                              const SizedBox(height: 14),
                                              Row(
                                                children: [
                                                  const Icon(Icons.place,
                                                      size: 16,
                                                      color: AppTheme.muted),
                                                  const SizedBox(width: 6),
                                                  Text(p.region,
                                                      style: const TextStyle(
                                                          color:
                                                              AppTheme.muted)),
                                                  const SizedBox(width: 20),
                                                  const Icon(Icons.storage,
                                                      size: 16,
                                                      color: AppTheme.muted),
                                                  const SizedBox(width: 6),
                                                  const Text('Postgres',
                                                      style: TextStyle(
                                                          color:
                                                              AppTheme.muted)),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: StatColumn(
                                                      label: 'Database size',
                                                      value: s?.diskSize ??
                                                          '—',
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: StatColumn(
                                                      label: 'API requests',
                                                      value: s?.apiRequests ==
                                                              null
                                                          ? '—'
                                                          : '${formatCompact(s!.apiRequests!)} today',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
