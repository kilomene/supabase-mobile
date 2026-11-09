import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Create New Project (preview 4). Live: POST /v1/projects.
/// db_pass is required and never retrievable later. Poll health until
/// ACTIVE_HEALTHY before configuring Auth etc. (see README).
/// Organisations come from GET /v1/organizations and regions from
/// GET /v1/projects/available-regions; both fall back to the previous
/// manual inputs if the endpoint fails.
/// PLAN HONESTY: createProject has NO plan parameter — the plan is the
/// selected organisation's plan (Organization.plan). The Free/Pro cards
/// only DISPLAY that plan: the matching card is marked selected and the
/// other is greyed. No plan is ever sent to the endpoint and the cards
/// never claim the choice changes the plan.
class CreateProjectScreen extends StatefulWidget {
  const CreateProjectScreen({super.key});
  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _RegionGroup {
  final String label;
  final String code;
  const _RegionGroup(this.label, this.code);
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _name = TextEditingController();
  final _org = TextEditingController();
  final _pass = TextEditingController();
  String _region = 'eu-west-1';
  bool _busy = false;
  String? _error;
  bool _showPass = false;

  List<Organization>? _orgs;
  bool _orgsFailed = false;
  String? _orgSlug;

  List<_RegionGroup>? _regionGroups;
  bool _regionsFailed = false;

  @override
  void initState() {
    super.initState();
    _loadOrgs();
    _loadRegions();
  }

  @override
  void dispose() {
    _name.dispose();
    _org.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _loadOrgs() async {
    try {
      final orgs = await ManagementApiClient().listOrganizations();
      if (!mounted) return;
      setState(() {
        _orgs = orgs;
        if (orgs.isNotEmpty) {
          _orgSlug = orgs.first.slug;
          _org.text = orgs.first.slug;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _orgsFailed = true);
    }
  }

  Future<void> _loadRegions() async {
    try {
      final codes = await ManagementApiClient().availableRegions();
      final groups = <_RegionGroup>[];
      for (final entry in [
        ('US East', 'us-'),
        ('EU West', 'eu-'),
        ('Asia Pacific', 'ap-'),
      ]) {
        final match = codes.where((c) => c.startsWith(entry.$2)).toList();
        if (match.isNotEmpty) {
          groups.add(_RegionGroup(entry.$1, match.first));
        }
      }
      if (!mounted) return;
      setState(() {
        _regionGroups = groups;
        if (groups.isNotEmpty &&
            !groups.any((g) => g.code == _region)) {
          _region = groups.first.code;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _regionsFailed = true);
    }
  }

  Organization? get _selectedOrg {
    if (_orgs == null || _orgSlug == null) return null;
    for (final o in _orgs!) {
      if (o.slug == _orgSlug) return o;
    }
    return null;
  }

  String _generatePassword() {
    const chars =
        'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789!@#\$%^&*';
    final r = Random.secure();
    return List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _create() async {
    final orgSlug = _orgSlug ?? _org.text.trim();
    if (_name.text.trim().isEmpty ||
        orgSlug.isEmpty ||
        _pass.text.isEmpty) {
      setState(() => _error =
          'Fill in the project name, organization and database password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await ManagementApiClient().createProject(
        name: _name.text.trim(),
        organizationSlug: orgSlug,
        dbPass: _pass.text,
        region: _region,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Creating ${p.name} — wait for ACTIVE_HEALTHY')));
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _planCard({
    required String title,
    required String details,
    required bool selected,
    required bool greyed,
    String? badge,
    Color? badgeColor,
  }) {
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? AppTheme.green
              : Colors.white.withValues(alpha: 0.15),
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(details,
              style: TextStyle(
                  color: greyed ? AppTheme.muted : AppTheme.text)),
        ],
      ),
    );
    return Opacity(
      opacity: greyed ? 0.5 : 1,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          if (selected)
            const Positioned(
              top: -10,
              right: -6,
              child: Icon(Icons.check_circle, color: AppTheme.green),
            ),
          if (badge != null)
            Positioned(
              top: -12,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor ?? PreviewColors.avatarPurple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(badge,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orgPlan = _selectedOrg?.plan?.toLowerCase();
    final isFree = orgPlan != null && orgPlan.contains('free');
    final isPro = orgPlan != null && orgPlan.contains('pro');
    final planKnown = isFree || isPro;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const Expanded(
                child: Text('New Project',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 20),
          const SectionLabel('Project Details'),
          const SizedBox(height: 16),
          const Text('Project name',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration:
                const InputDecoration(hintText: 'my-new-app'),
          ),
          const SizedBox(height: 20),
          const Text('Organization',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_orgs != null && _orgs!.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _orgSlug,
              decoration: const InputDecoration(
                  border: OutlineInputBorder()),
              items: _orgs!
                  .map((o) => DropdownMenuItem(
                      value: o.slug, child: Text(o.name)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _orgSlug = v;
                  _org.text = v;
                });
              },
            )
          else
            TextField(
              controller: _org,
              decoration: InputDecoration(
                  labelText: 'Organization slug',
                  hintText: _orgsFailed
                      ? 'Could not load organizations — type the slug'
                      : null),
            ),
          const SizedBox(height: 24),
          const SectionLabel('Database Password'),
          const SizedBox(height: 16),
          TextField(
            controller: _pass,
            obscureText: !_showPass,
            decoration: InputDecoration(
              hintText: 'Database password (never retrievable later)',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.auto_fix_high,
                        color: AppTheme.green),
                    tooltip: 'Generate a strong password',
                    onPressed: () {
                      _pass.text = _generatePassword();
                      setState(() => _showPass = true);
                    },
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _showPass = !_showPass),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.green,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Generate',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                        _showPass ? Icons.visibility_off : Icons.visibility,
                        color: AppTheme.muted),
                    tooltip: _showPass ? 'Hide password' : 'Show password',
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Region',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_regionGroups != null && _regionGroups!.isNotEmpty)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _regionGroups!.map((g) {
                final selected = _region == g.code;
                return GestureDetector(
                  onTap: () => setState(() => _region = g.code),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppTheme.green
                            : Colors.white.withValues(alpha: 0.25),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(g.label,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? AppTheme.green
                                  : AppTheme.text)),
                      if (selected) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.check_circle,
                            color: AppTheme.green, size: 22),
                      ],
                    ]),
                  ),
                );
              }).toList(),
            )
          else
            DropdownButton<String>(
              value: _region,
              items: const ['eu-west-1', 'us-east-1', 'ap-southeast-1']
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) => setState(() => _region = v ?? _region),
            ),
          if (_regionsFailed)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                  'Could not load regions — showing the standard list.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            ),
          const SizedBox(height: 24),
          const SectionLabel('Pricing Plan'),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _snackPlanNote(),
                  child: _planCard(
                    title: 'Free',
                    details: 'Free • 500 MB storage • Shared resources',
                    selected: isFree,
                    greyed: planKnown && !isFree,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => _snackPlanNote(),
                  child: _planCard(
                    title: 'Pro',
                    details: '\$25/mo • 8 GB storage • Dedicated',
                    selected: isPro,
                    greyed: planKnown && !isPro,
                    badge: 'Recommended',
                    badgeColor: PreviewColors.avatarPurple,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            planKnown
                ? 'Plan is set on your organization'
                : "New projects inherit your organization's plan",
            style: const TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          const Row(children: [
            Icon(Icons.info_outline, size: 18, color: AppTheme.muted),
            SizedBox(width: 6),
            Text('Project takes about 2 minutes to provision.',
                style: TextStyle(color: AppTheme.muted)),
          ]),
          const SizedBox(height: 20),
          if (_error != null) ErrorView(_error!),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _create,
              child: const Text('Create project',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }

  void _snackPlanNote() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'The plan is set on your organization — new projects inherit it.')));
  }
}
