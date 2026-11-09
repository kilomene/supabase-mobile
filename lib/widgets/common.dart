import 'package:flutter/material.dart';
import 'package:supabase_mobile/theme/app_theme.dart';

/// Shared loading / empty / error states — every screen uses these,
/// never a silent blank screen and never mock rows.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(color: AppTheme.green));
}

class EmptyView extends StatelessWidget {
  final String message;
  const EmptyView(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted)),
        ),
      );
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView(this.message, {this.onRetry, super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ]),
        ),
      );
}

/// Honest banner for dashboard-only features (NO_ENDPOINT, report §4).
class DashboardOnlyBanner extends StatelessWidget {
  final String feature;
  final VoidCallback onOpenDashboard;
  const DashboardOnlyBanner(
      {required this.feature, required this.onOpenDashboard, super.key});
  @override
  Widget build(BuildContext context) => Card(
        color: Colors.amber.withValues(alpha: 0.12),
        child: ListTile(
          leading: const Icon(Icons.open_in_browser, color: Colors.amber),
          title: Text('$feature is dashboard-only'),
          subtitle: const Text(
              'Supabase has no public API for this. It opens in your browser — nothing is faked here.'),
          trailing: TextButton(
              onPressed: onOpenDashboard, child: const Text('Open')),
        ),
      );
}

class SupaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  const SupaAppBar(this.title, {this.actions, super.key});
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) =>
      AppBar(title: Text(title), actions: actions);
}
