import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/app_state.dart';

void main() {
  test('AppState selects and clears the shared project', () {
    final state = AppState.instance;
    state.clearProject();
    expect(state.selectedProject.value, isNull);
    final p = SupabaseProject(
        ref: 'abc',
        name: 'Demo',
        organizationSlug: 'org',
        region: 'us-east-1',
        status: 'ACTIVE_HEALTHY');
    state.selectProject(p);
    expect(state.selectedProject.value?.ref, 'abc');
    expect(state.selectedProject.value?.name, 'Demo');
    state.clearProject();
    expect(state.selectedProject.value, isNull);
  });
}
