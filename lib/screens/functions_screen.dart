import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/services/project_client_registry.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Edge Functions (preview 1). Live: Management GET
/// /v1/projects/{ref}/functions, GET .../functions/{slug}/body,
/// DELETE .../functions/{slug}, multipart POST .../functions/deploy
/// (server-side bundling — no Deno on-device). Invoke is project-host
/// POST /functions/v1/<slug>. Per-function logs come from the
/// Management ClickHouse logs endpoint (edge_logs).
/// Honest omissions — no endpoint provides them, so they are left out,
/// never invented: an "updated … ago" time (EdgeFunction has no
/// updated-at) and per-function invocation counts (log lines are not
/// invocations). Region is the project's real region.
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
  bool _busy = false;
  String _query = '';
  bool _showSearch = false;
  bool _showDeploy = false;
  String? _expanded;
  final Map<String, List<LogEvent>> _fnLogs = {};
  final Set<String> _logsLoading = {};
  final _slug = TextEditingController();
  final _code = TextEditingController(
      text: 'Deno.serve(async (req) => {\n'
          '  return new Response(\n'
          '    JSON.stringify({ message: "hello" }),\n'
          '    { headers: { "Content-Type": "application/json" } },\n'
          '  );\n'
          '});');
  final _invokeBody = TextEditingController(text: '{}');
  final _search = TextEditingController();
  final _scroll = ScrollController();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final fns =
          await ManagementApiClient().listFunctions(widget.project.ref);
      if (mounted) setState(() => _fns = fns);
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
    _slug.dispose();
    _code.dispose();
    _invokeBody.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _openDeployForm() {
    setState(() => _showDeploy = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _deploy() async {
    final slug = _slug.text.trim();
    final code = _code.text;
    if (slug.isEmpty || code.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ManagementApiClient()
          .deployFunction(widget.project.ref, slug, code);
      _snack('Function deployed');
      _slug.clear();
      setState(() => _showDeploy = false);
      await _load();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showBody(String slug) async {
    try {
      final body =
          await ManagementApiClient().getFunctionBody(widget.project.ref, slug);
      if (!mounted) return;
      await showJsonDialog(context,
          title: '$slug — body', value: {'body': body});
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _invoke(String slug) async {
    setState(() => _busy = true);
    try {
      final api =
          await ProjectClientRegistry().apiClient(widget.project);
      final result = await api.invokeFunction(slug, _invokeBody.text);
      if (!mounted) return;
      await showJsonDialog(context, title: '$slug — invoke result', value: result);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String slug) async {
    setState(() => _busy = true);
    try {
      await ManagementApiClient().deleteFunction(widget.project.ref, slug);
      _snack('Function deleted');
      await _load();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadFnLogs(String slug) async {
    if (_fnLogs.containsKey(slug) || _logsLoading.contains(slug)) return;
    setState(() => _logsLoading.add(slug));
    try {
      final logs = await ManagementApiClient().queryLogs(
        widget.project.ref,
        "SELECT * FROM edge_logs "
        "WHERE event_message LIKE '%$slug%' LIMIT 4",
      );
      if (mounted) setState(() => _fnLogs[slug] = logs);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _logsLoading.remove(slug));
    }
  }

  Color _levelColor(String level) {
    final l = level.toUpperCase();
    if (l.contains('ERR')) return PreviewColors.dangerRed;
    if (l.contains('WRN') || l.contains('WARN')) {
      return PreviewColors.warnYellow;
    }
    return Colors.white;
  }

  Widget _logsCard(String slug) {
    final logs = _fnLogs[slug];
    final loading = _logsLoading.contains(slug);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
            left: BorderSide(color: AppTheme.green, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('> Logs (latest 4)',
              style: TextStyle(
                  color: AppTheme.green,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
          const SizedBox(height: 10),
          if (loading) const LoadingView(),
          if (!loading && (logs == null || logs.isEmpty))
            const Text('No recent logs for this function.',
                style: TextStyle(color: AppTheme.muted)),
          if (logs != null)
            ...logs.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RichText(
                    text: TextSpan(children: [
                      TextSpan(
                          text: '[${l.timestamp}] ',
                          style: const TextStyle(
                              color: AppTheme.muted,
                              fontFamily: 'monospace',
                              fontSize: 12)),
                      TextSpan(
                          text: '${l.level}: ',
                          style: TextStyle(
                              color: _levelColor(l.level),
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              fontSize: 12)),
                      TextSpan(
                          text: l.message,
                          style: TextStyle(
                              color: _levelColor(l.level),
                              fontFamily: 'monospace',
                              fontSize: 12)),
                    ]),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _functionCard(EdgeFunction f) {
    final expanded = _expanded == f.slug;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RichCard(
          onTap: () {
            setState(() {
              _expanded = expanded ? null : f.slug;
            });
            if (!expanded) _loadFnLogs(f.slug);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle,
                        size: 12, color: AppTheme.green),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(f.slug,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Pill(f.status.isEmpty ? 'Deployed' : f.status,
                          bg: AppTheme.green, fg: Colors.black),
                      if (f.version != null) ...[
                        const SizedBox(height: 6),
                        Text('v${f.version}',
                            style:
                                const TextStyle(color: AppTheme.muted)),
                      ],
                    ],
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.location_on,
                      size: 18, color: AppTheme.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Region: ${widget.project.region}',
                        style: const TextStyle(color: AppTheme.muted)),
                  ),
                  Icon(expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.chevron_right),
                ],
              ),
              if (expanded) ...[
                _logsCard(f.slug),
                const SizedBox(height: 12),
                TextField(
                  controller: _invokeBody,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                      labelText: 'Invoke body (JSON text)'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _busy ? null : () => _invoke(f.slug),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Invoke'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _showBody(f.slug),
                      icon: const Icon(Icons.visibility, size: 18),
                      label: const Text('View body'),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _busy ? null : () => _delete(f.slug),
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _query.isEmpty
        ? _fns
        : _fns
            .where(
                (f) => f.slug.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const LoadingView()
            : _error != null
                ? ErrorView(_error!, onRetry: _load)
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.surface2,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const SupaBolt(size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(widget.project.name,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.search),
                              tooltip: 'Search functions',
                              onPressed: () => setState(
                                  () => _showSearch = !_showSearch),
                            ),
                            IconButton(
                              icon: const Icon(Icons.more_horiz),
                              tooltip: 'Deploy a function',
                              onPressed: _openDeployForm,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('Edge Functions',
                          style: TextStyle(
                              fontSize: 32, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(
                          'Serverless functions for ${widget.project.name} • Powered by Supabase',
                          style: const TextStyle(color: AppTheme.muted)),
                      const SizedBox(height: 20),
                      if (_showSearch) ...[
                        PreviewSearchBar(
                          controller: _search,
                          hint: 'Search functions',
                          onChanged: (v) => setState(() => _query = v),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (visible.isEmpty)
                        const EmptyView('No Edge Functions deployed yet.'),
                      ...visible.map((f) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _functionCard(f),
                          )),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _openDeployForm,
                          icon: const Icon(Icons.add),
                          label: const Text('Deploy new function',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      if (_showDeploy) ...[
                        const SizedBox(height: 16),
                        RichCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Deploy a function',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _slug,
                                decoration: const InputDecoration(
                                    labelText: 'Slug'),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _code,
                                maxLines: 8,
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                    labelText: 'index.ts source'),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _busy ? null : _deploy,
                                  child: const Text('Deploy'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }
}
