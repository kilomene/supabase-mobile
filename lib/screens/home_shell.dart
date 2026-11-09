import 'package:flutter/material.dart';
import 'package:supabase_mobile/services/app_state.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/screens/projects_screen.dart';
import 'package:supabase_mobile/screens/dashboard_screen.dart';
import 'package:supabase_mobile/screens/table_editor_screen.dart';
import 'package:supabase_mobile/screens/auth_users_screen.dart';
import 'package:supabase_mobile/screens/storage_screen.dart';
import 'package:supabase_mobile/screens/more_screen.dart';

/// Bottom navigation: Dashboard, Database, Auth, Storage, More.
/// The selected project lives in AppState and is shared by every tab:
/// pick a project once (Dashboard tab shows the project list until one
/// is picked) and every tab works on it. Screens that need a project
/// show an honest "pick a project first" empty state when none is set.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
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
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            type: BottomNavigationBarType.fixed,
            backgroundColor: AppTheme.surface,
            selectedItemColor: AppTheme.green,
            unselectedItemColor: AppTheme.muted,
            items: const [
              BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard), label: 'Dashboard'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.storage), label: 'Database'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.shield), label: 'Auth'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.cloud), label: 'Storage'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.more_horiz), label: 'More'),
            ],
          ),
        );
      },
    );
  }
}
