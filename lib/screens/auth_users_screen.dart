import 'package:flutter/material.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/app_state.dart';
import 'package:supabase_mobile/services/project_client_registry.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/widgets/common.dart';
import 'package:supabase_mobile/screens/auth_config_screen.dart';
import 'package:supabase_mobile/screens/database_screen.dart';

/// Auth — Users (preview). Live: GoTrue Admin
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
  final _search = TextEditingController();
  final _inviteEmail = TextEditingController();

  Future<void> _load() async {
    final p = widget.project;
    if (p == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      final users = await api.listAuthUsers();
      if (mounted) setState(() => _users = users);
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
  void didUpdateWidget(AuthUsersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.project?.ref != oldWidget.project?.ref) _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _inviteEmail.dispose();
    super.dispose();
  }

  List<AuthUser> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) => u.email.toLowerCase().contains(q)).toList();
  }

  Future<void> _invite() async {
    _inviteEmail.clear();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite user'),
        content: TextField(
          controller: _inviteEmail,
          keyboardType: TextInputType.emailAddress,
          decoration:
              const InputDecoration(labelText: 'Email', hintText: 'user@example.com'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(_inviteEmail.text.trim()),
              child: const Text('Invite')),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    final p = widget.project;
    if (p == null) return;
    try {
      final api = await ProjectClientRegistry().apiClient(p);
      await api.inviteAuthUser(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Invite sent to $email')));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: selected ? AppTheme.green : Colors.transparent,
                  width: 3),
            ),
          ),
          child: Column(children: [
            Text(label,
                style: TextStyle(
                    color: selected ? AppTheme.green : AppTheme.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 16)),
            const SizedBox(height: 10),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    if (p == null) {
      return const Scaffold(
          body: EmptyView('Pick a project first, then manage its Auth users.'));
    }
    final users = _filtered;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SupaLogoRow(size: 20),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => AppState.instance.clearProject(),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Row(children: [
                        Text(p.name,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const Icon(Icons.keyboard_arrow_down,
                            color: AppTheme.muted),
                      ]),
                    ),
                  ),
                  const Spacer(),
                  // Decorative icons only — not wired to anything.
                  const Icon(Icons.notifications_outlined,
                      color: AppTheme.muted),
                  const SizedBox(width: 16),
                  const Icon(Icons.account_circle,
                      size: 28, color: AppTheme.muted),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Authentication — Users',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  _tab('Users', true, () {}),
                  _tab(
                      'Providers',
                      false,
                      () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => AuthConfigScreen(project: p)))),
                  _tab(
                      'Policies',
                      false,
                      () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => DatabaseScreen(project: p)))),
                ]),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: PreviewSearchBar(
                      controller: _search,
                      hint: 'Search users by email…',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: _invite,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.green,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min,
                          children: [
                        Icon(Icons.add, size: 18, color: Colors.black),
                        SizedBox(width: 4),
                        Text('+ Invite user',
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const LoadingView()
                    : _error != null
                        ? ErrorView(_error!, onRetry: _load)
                        : _users.isEmpty
                            ? const EmptyView('No users yet.')
                            : users.isEmpty
                                ? const EmptyView(
                                    'No users match that search.')
                                : ListView.separated(
                                    itemCount: users.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(
                                            height: 1, color: Colors.white12),
                                    itemBuilder: (context, i) {
                                      final u = users[i];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            CircleAvatar(
                                              radius: 26,
                                              backgroundColor:
                                                  avatarColorOf(u.email),
                                              child: Text(initialsOf(u.email),
                                                  style: const TextStyle(
                                                      color: Colors.black,
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(u.email,
                                                      maxLines: 1,
                                                      overflow: TextOverflow
                                                          .ellipsis,
                                                      style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                  const SizedBox(height: 6),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 6,
                                                    children: [
                                                      providerChip(
                                                          u.provider),
                                                      confirmedChip(
                                                          u.emailConfirmed),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                      'Last sign-in: ${u.lastSignInAt == null ? 'never' : relativeTime(u.lastSignInAt)}',
                                                      style: const TextStyle(
                                                          color:
                                                              AppTheme.muted,
                                                          fontSize: 13)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
