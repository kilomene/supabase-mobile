import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/project_client_registry.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Auth — Users (preview 5). Live: GoTrue Admin
/// GET /auth/v1/admin/users — SECRET key only (publishable = 401).
/// Providers / SMTP / MFA config live in Management PATCH /config/auth.
class AuthUsersScreen extends StatefulWidget {
  final SupabaseProject? project;
  const AuthUsersScreen({this.project, super.key});
  @override
  State<AuthUsersScreen> createState() => _AuthUsersScreenState();
}

class _AuthUsersScreenState extends State<AuthUsersScreen> {
  List<AuthUser> _users = [];
  bool _loading = false;
  String? _error;

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      final users = await api.listAuthUsers();
      setState(() => _users = users);
    } catch (e) {
      setState(() => _error = '$e');
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
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first, then manage its Auth users.'));
    }
    return Scaffold(
      appBar: const SupaAppBar('Authentication — Users'),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : _users.isEmpty
                  ? const EmptyView('No users yet.')
                  : ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (context, i) {
                        final u = _users[i];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                                child: Text(u.email.isNotEmpty
                                    ? u.email[0].toUpperCase()
                                    : '?')),
                            title: Text(u.email),
                            subtitle: Text(
                                '${u.provider ?? 'Email'} • ${u.emailConfirmed ? 'Confirmed' : 'Unconfirmed'} • Last sign-in: ${u.lastSignInAt ?? 'never'}'),
                          ),
                        );
                      },
                    ),
    );
  }
}
