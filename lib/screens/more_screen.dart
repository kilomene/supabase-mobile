import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/app_state.dart';
import 'package:supabase_mobile/services/secure_token_storage.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/widgets/common.dart';
import 'package:supabase_mobile/screens/auth_screen.dart';
import 'package:supabase_mobile/screens/dashboard_screen.dart';
import 'package:supabase_mobile/screens/sql_editor_screen.dart';
import 'package:supabase_mobile/screens/functions_screen.dart';
import 'package:supabase_mobile/screens/settings_api_screen.dart';
import 'package:supabase_mobile/screens/developer_api_screen.dart';
import 'package:supabase_mobile/screens/realtime_logs_screen.dart';
import 'package:supabase_mobile/screens/table_editor_screen.dart';
import 'package:supabase_mobile/screens/organizations_screen.dart';
import 'package:supabase_mobile/screens/database_screen.dart';
import 'package:supabase_mobile/screens/auth_config_screen.dart';
import 'package:supabase_mobile/screens/branches_screen.dart';
import 'package:supabase_mobile/screens/backups_screen.dart';
import 'package:supabase_mobile/screens/billing_screen.dart';
import 'package:supabase_mobile/screens/advisors_screen.dart';
import 'package:supabase_mobile/screens/secrets_screen.dart';
import 'package:supabase_mobile/screens/log_drains_screen.dart';
import 'package:supabase_mobile/screens/webhooks_screen.dart';
import 'package:supabase_mobile/screens/domains_screen.dart';
import 'package:supabase_mobile/screens/network_screen.dart';
import 'package:supabase_mobile/screens/graphql_screen.dart';

/// "More" hub — every screen the bottom tabs do not show.
/// All of them receive the shared selected project; entries that need a
/// project refuse with a SnackBar when none is selected, never a fake.
class MoreScreen extends StatelessWidget {
  final SupabaseProject? project;
  const MoreScreen({this.project, super.key});

  void _open(BuildContext context, Widget Function() build, bool needsProject) {
    if (needsProject && project == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pick a project first — open the Dashboard tab.')));
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => build()));
  }

  Widget _row(BuildContext context, _Entry e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichCard(
        onTap: () => _open(context, e.build, e.needsProject),
        child: Row(children: [
          IconTile(icon: e.icon, color: AppTheme.green, bg: AppTheme.green, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text(e.subtitle,
                    style: const TextStyle(color: AppTheme.muted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppTheme.muted),
        ]),
      ),
    );
  }

  Widget _group(BuildContext context, String label, List<_Entry> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label),
        const SizedBox(height: 8),
        ...entries.map((e) => _row(context, e)),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = project;
    final projectEntries = <_Entry>[
      _Entry('Dashboard', 'Health, usage, logs, quick actions', Icons.dashboard,
          () => DashboardScreen(project: p), false),
      _Entry('SQL Editor', 'Run SQL, DDL, RLS, pgvector, Cron', Icons.terminal,
          () => SqlEditorScreen(project: p!), true),
      _Entry('Table Editor', 'Browse tables & rows', Icons.table_chart,
          () => TableEditorScreen(project: p), false),
      _Entry('Realtime & Logs', 'Live events, Logs Explorer', Icons.bolt,
          () => RealtimeLogsScreen(project: p), false),
    ];
    final buildEntries = <_Entry>[
      _Entry('Edge Functions', 'List, deploy, invoke, delete', Icons.bolt,
          () => FunctionsScreen(project: p!), true),
      _Entry('Function secrets', 'Create & delete (values never shown)',
          Icons.key, () => SecretsScreen(project: p), false),
      _Entry('GraphQL playground', 'Run queries on /graphql/v1',
          Icons.hub, () => GraphqlScreen(project: p), false),
      _Entry('Developer / API', 'REST, GraphQL, docs', Icons.code,
          () => DeveloperApiScreen(project: p!), true),
    ];
    final manageEntries = <_Entry>[
      _Entry('Organizations', 'List, create, members', Icons.business,
          () => const OrganizationsScreen(), false),
      _Entry('Database admin', 'Migrations, snippets, config, upgrades',
          Icons.storage, () => DatabaseScreen(project: p), false),
      _Entry('Auth config', 'Providers, SMTP, MFA, SSO, keys', Icons.shield,
          () => AuthConfigScreen(project: p), false),
      _Entry('Branches', 'Create, merge, push, diff', Icons.account_tree,
          () => BranchesScreen(project: p), false),
      _Entry('Backups', 'List, restore, PITR, schedule', Icons.backup,
          () => BackupsScreen(project: p), false),
      _Entry('Billing & usage', 'Addons, egress, invoices link',
          Icons.receipt, () => BillingScreen(project: p), false),
      _Entry('Advisors', 'Security & performance findings',
          Icons.warning_amber, () => AdvisorsScreen(project: p), false),
      _Entry('Log drains', 'Forward logs to a sink', Icons.plumbing,
          () => LogDrainsScreen(project: p), false),
      _Entry('Webhooks', 'Endpoints, deliveries, test', Icons.webhook,
          () => WebhooksScreen(project: p), false),
      _Entry('Domains', 'Custom hostname & vanity subdomain',
          Icons.language, () => DomainsScreen(project: p), false),
      _Entry('Network & security', 'Restrictions, bans, SSL, pgsodium',
          Icons.security, () => NetworkScreen(project: p), false),
      _Entry('Settings & API keys', 'Keys, connect, billing link', Icons.settings,
          () => SettingsApiScreen(project: p!), true),
    ];
    return Scaffold(
      appBar: SupaAppBar(p == null
          ? 'More'
          : 'More — ${p.name}'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (p != null) ...[
          RichCard(
            child: Row(children: [
              Icon(Icons.circle,
                  color: p.isActive ? AppTheme.green : Colors.grey,
                  size: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Selected: ${p.name}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text('${p.ref} • ${p.region}',
                        style: const TextStyle(color: AppTheme.muted)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => AppState.instance.clearProject(),
                child: const Text('Switch'),
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],
        _group(context, 'Project', projectEntries),
        _group(context, 'Build', buildEntries),
        _group(context, 'Manage', manageEntries),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.logout, color: PreviewColors.dangerRed),
            label: const Text('Sign out',
                style: TextStyle(color: PreviewColors.dangerRed)),
            onPressed: () async {
              await SecureTokenStorage().clearManagementToken();
              AppState.instance.clearProject();
              if (context.mounted) {
                await Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                    (route) => false);
              }
            },
          ),
        ),
      ]),
    );
  }
}

class _Entry {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget Function() build;
  final bool needsProject;
  const _Entry(this.title, this.subtitle, this.icon, this.build, this.needsProject);
}
