import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/dashboard_links.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Backups. Live: GET /v1/projects/{ref}/database/backups,
/// POST .../backups/restore, .../restore-pitr, .../restore-point,
/// GET/PATCH .../backups/schedule, POST .../backups/undo.
/// DISPUTED (report §4): the PAT table lists these endpoints, but a
/// third-party guide says backups are dashboard-only. The app calls the
/// real endpoints; a 404/402 surfaces as a dashboard-only error with a
/// link — nothing is faked.
class BackupsScreen extends StatefulWidget {
  final SupabaseProject? project;
  const BackupsScreen({this.project, super.key});
  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  final _api = ManagementApiClient();
  List<Map<String, dynamic>> _backups = [];
  Map<String, dynamic>? _schedule;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  final _pitr = TextEditingController();
  final _scheduleJson = TextEditingController();

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final rows = await _api.listBackups(p.ref);
      Map<String, dynamic>? schedule;
      try {
        schedule = await _api.getBackupSchedule(p.ref);
      } catch (_) {
        schedule = null;
      }
      if (!mounted) return;
      setState(() {
        _backups = rows;
        _schedule = schedule;
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
  void dispose() {
    _pitr.dispose();
    _scheduleJson.dispose();
    super.dispose();
  }

  bool get _looksDashboardOnly =>
      _error != null &&
      (_error!.contains('404') ||
          _error!.contains('402') ||
          _error!.contains('Not Found'));

  Future<void> _act(String done, Future<void> Function() call) async {
    setState(() => _busy = true);
    try {
      await call();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first to see its backups.'));
    }
    final p = widget.project!;
    return Scaffold(
      appBar: SupaAppBar('Backups — ${p.name}'),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ListView(padding: const EdgeInsets.all(16), children: [
                  ErrorView(_error!, onRetry: _load),
                  if (_looksDashboardOnly) ...[
                    const SizedBox(height: 12),
                    DashboardOnlyBanner(
                        feature: 'Backups',
                        onOpenDashboard: () =>
                            DashboardLinks.projectBilling(p.ref)),
                    const Text(
                        'The backup endpoints returned 404/402 for this project — the dashboard is the fallback.',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ])
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('Backup schedule',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText(prettyJson(_schedule),
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _scheduleJson,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'New schedule as JSON (optional)',
                        hintText: '{"retention_days": 7}'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            try {
                              final patch = jsonDecode(
                                      _scheduleJson.text.trim())
                                  as Map<String, dynamic>;
                              await _act('Schedule updated',
                                  () => _api.updateBackupSchedule(p.ref, patch));
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$e')));
                              }
                            }
                          },
                    child: const Text('Save schedule'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Point-in-time recovery',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextField(
                    controller: _pitr,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Recovery time (unix seconds)'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    ElevatedButton(
                      onPressed: _busy
                          ? null
                          : () {
                              final v =
                                  int.tryParse(_pitr.text.trim());
                              if (v == null) return;
                              _act('PITR restore requested',
                                  () => _api.restorePitr(p.ref, v));
                            },
                      child: const Text('Restore to time'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _act('Restore undone',
                              () => _api.undoRestore(p.ref)),
                      child: const Text('Undo restore'),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  const Text('Backups',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_backups.isEmpty)
                    const Text(
                        'No backups returned (free plans keep none; Pro keeps 7 days).',
                        style: TextStyle(color: Colors.grey)),
                  ..._backups.map((b) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.backup),
                          title: Text(
                              '${b['id'] ?? b['name'] ?? 'backup'}'),
                          subtitle: Text(
                              '${b['created_at'] ?? ''} ${b['status'] ?? ''}'
                                  .trim()),
                          trailing: TextButton(
                            onPressed: _busy
                                ? null
                                : () => _act(
                                    'Restore requested',
                                    () => _api.restoreBackup(p.ref,
                                        '${b['id'] ?? ''}')),
                            child: const Text('Restore'),
                          ),
                        ),
                      )),
                ]),
    );
  }
}
