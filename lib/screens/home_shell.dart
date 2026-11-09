import 'package:flutter/material.dart';
import 'package:supabase_mobile/services/app_state.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/screens/projects_screen.dart';
import 'package:supabase_mobile/screens/dashboard_screen.dart';
import 'package:supabase_mobile/screens/table_editor_screen.dart';
import 'package:supabase_mobile/screens/auth_users_screen.dart';
import 'package:supabase_mobile/screens/storage_screen.dart';
import 'package:supabase_mobile/screens/more_screen.dart';

/// Bottom navigation: Projects, Database, Auth, Storage, More — as in
/// the approved previews (icon above label, active tab green with a
/// subtle green-tinted rounded tile behind the active icon).
/// The selected project lives in AppState and is shared by every tab:
/// pick a project once (Projects tab shows the project list until one
/// is picked) and every tab works on it. Screens that need a project
/// show an honest "pick a project first" empty state when none is set.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  Widget _navItem({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: active
                      ? AppTheme.green.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    color: active ? AppTheme.green : AppTheme.muted,
                    size: 24),
              ),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          active ? FontWeight.w600 : FontWeight.normal,
                      color: active ? AppTheme.green : AppTheme.muted)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: AppState.instance.selectedProject,
      builder: (context, project, _) {
        final pages = [
          project == null
              ? const ProjectsScreen()
              : DashboardScreen(project: project),
          TableEditorScreen(project: project),
          AuthUsersScreen(project: project),
          StorageScreen(project: project),
          MoreScreen(project: project),
        ];
        return Scaffold(
          body: pages[_index],
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border(
                top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  _navItem(
                      icon: Icons.grid_view,
                      label: 'Projects',
                      active: _index == 0,
                      onTap: () => setState(() => _index = 0)),
                  _navItem(
                      icon: Icons.storage,
                      label: 'Database',
                      active: _index == 1,
                      onTap: () => setState(() => _index = 1)),
                  _navItem(
                      icon: Icons.shield,
                      label: 'Auth',
                      active: _index == 2,
                      onTap: () => setState(() => _index = 2)),
                  _navItem(
                      icon: Icons.cloud,
                      label: 'Storage',
                      active: _index == 3,
                      onTap: () => setState(() => _index = 3)),
                  _navItem(
                      icon: Icons.more_horiz,
                      label: 'More',
                      active: _index == 4,
                      onTap: () => setState(() => _index = 4)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
