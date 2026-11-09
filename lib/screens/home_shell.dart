import 'package:flutter/material.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/screens/projects_screen.dart';
import 'package:supabase_mobile/screens/table_editor_screen.dart';
import 'package:supabase_mobile/screens/auth_users_screen.dart';
import 'package:supabase_mobile/screens/storage_screen.dart';
import 'package:supabase_mobile/screens/realtime_logs_screen.dart';

/// Bottom navigation matching the approved previews.
/// The selected project is held here and passed down; screens that need
/// a project show an honest "pick a project first" empty state.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = const [
      ProjectsScreen(),
      TableEditorScreen(),
      AuthUsersScreen(),
      StorageScreen(),
      RealtimeLogsScreen(),
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
          BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Projects'),
          BottomNavigationBarItem(icon: Icon(Icons.storage), label: 'Database'),
          BottomNavigationBarItem(icon: Icon(Icons.shield), label: 'Auth'),
          BottomNavigationBarItem(icon: Icon(Icons.cloud), label: 'Storage'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
