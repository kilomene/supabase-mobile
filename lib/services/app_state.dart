import 'package:flutter/foundation.dart';
import 'package:supabase_mobile/models/models.dart';

/// App-level shared state (no new dependencies).
/// The selected project lives here, not in any one screen, so every tab
/// sees the same project. HomeShell listens and passes it down;
/// ProjectsScreen sets it on tap. Cleared on sign-out.
class AppState {
  AppState._();
  static final AppState instance = AppState._();

  final ValueNotifier<SupabaseProject?> selectedProject =
      ValueNotifier<SupabaseProject?>(null);

  void selectProject(SupabaseProject project) {
    selectedProject.value = project;
  }

  void clearProject() {
    selectedProject.value = null;
  }
}
