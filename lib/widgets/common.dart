import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:supabase_mobile/theme/app_theme.dart';

/// Pretty-print any JSON value (maps/lists) for display in dialogs.
String prettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

/// Edit a JSON object in a dialog. Returns the parsed map, or null when
/// cancelled. Used by the config screens (Auth, PostgREST, pooler, …) —
/// the server is the source of truth, the app never invents keys.
Future<Map<String, dynamic>?> showJsonEditor(BuildContext context,
    {required String title, required Map<String, dynamic> initial}) async {
  final controller = TextEditingController(text: prettyJson(initial));
  String? error;
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: controller,
                maxLines: 12,
                style: const TextStyle(fontSize: 12)),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              try {
                final parsed = jsonDecode(controller.text);
                if (parsed is! Map<String, dynamic>) {
                  throw const FormatException(
                      'Top level must be a JSON object');
                }
                Navigator.of(context).pop(parsed);
              } catch (e) {
                setDialogState(() => error = '$e');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

/// Show any JSON value in a scrollable dialog.
Future<void> showJsonDialog(BuildContext context,
    {required String title, required Object? value}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
            child: SelectableText(prettyJson(value),
                style: const TextStyle(fontSize: 12))),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
      ],
    ),
  );
}

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

// ------------------------------------------------------------------
// Preview design system — shared by every screen so the app matches
// the approved mockups (rich cards, pills, stat rows, search bars).
// All values here are layout/styling only; every number shown on a
// screen must still come from a live endpoint (see each screen).
// ------------------------------------------------------------------

/// Extra colours from the previews (syntax + status colours).
class PreviewColors {
  static const keywordPurple = Color(0xFFC792EA);
  static const numberOrange = Color(0xFFD19A66);
  static const stringGreen = Color(0xFF98C379);
  static const warnYellow = Color(0xFFE5C07B);
  static const dangerRed = Color(0xFFF26D6D);
  static const methodOrange = Color(0xFFF0A35E);
  static const avatarBlue = Color(0xFF4A7CFF);
  static const avatarPurple = Color(0xFF8B5CF6);
  static const avatarGrey = Color(0xFF6B7280);
}

/// Supabase lightning-bolt mark, drawn in the brand green.
class SupaBolt extends StatelessWidget {
  final double size;
  const SupaBolt({this.size = 40, super.key});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _BoltPainter());
}

class _BoltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.66, 0)
      ..lineTo(size.width * 0.24, size.height * 0.58)
      ..lineTo(size.width * 0.46, size.height * 0.58)
      ..lineTo(size.width * 0.32, size.height)
      ..lineTo(size.width * 0.76, size.height * 0.40)
      ..lineTo(size.width * 0.54, size.height * 0.40)
      ..close();
    canvas.drawPath(path, Paint()..color = AppTheme.green);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Centred logo row from the previews: bolt + "supabase".
class SupaLogoRow extends StatelessWidget {
  final double size;
  const SupaLogoRow({this.size = 32, super.key});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SupaBolt(size: size + 8),
        const SizedBox(width: 12),
        Text('supabase',
            style: TextStyle(fontSize: size, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

/// Small rounded pill (status, method, level, provider, public/private).
class Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final Color? border;
  final IconData? icon;
  const Pill(this.text,
      {required this.bg, required this.fg, this.border, this.icon, super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
        ],
        Text(text,
            style: TextStyle(
                color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );
  }
}

/// Project status pill: Active (green) / Paused (grey) / anything else.
Pill projectStatusPill(String status) {
  final active = status == 'ACTIVE_HEALTHY';
  final paused = status.contains('PAUSED') || status.contains('PAUSE');
  if (active) {
    return const Pill('Active',
        bg: AppTheme.green, fg: Colors.black);
  }
  if (paused) {
    return Pill('Paused',
        bg: Colors.grey.withValues(alpha: 0.35), fg: Colors.white);
  }
  return Pill(status,
      bg: Colors.grey.withValues(alpha: 0.2), fg: AppTheme.muted);
}

/// Muted small-caps section label ("PROJECT DETAILS", "ENDPOINTS").
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(
          color: AppTheme.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2));
}

/// Muted label over a bold value (Projects card stats).
class StatColumn extends StatelessWidget {
  final String label;
  final String value;
  const StatColumn({required this.label, required this.value, super.key});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
      const SizedBox(height: 4),
      Text(value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    ]);
  }
}

/// Rounded dark search field with a magnifier, as in the previews.
class PreviewSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  const PreviewSearchBar(
      {required this.controller, required this.hint, this.onChanged, super.key});
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.muted),
        prefixIcon: const Icon(Icons.search, color: AppTheme.muted),
        filled: true,
        fillColor: AppTheme.surface2,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

/// Rich dark card used across the previews (rounded 16, subtle border).
class RichCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  const RichCard(
      {required this.child,
      this.onTap,
      this.padding = const EdgeInsets.all(16),
      super.key});
  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: card,
    );
  }
}

/// Rounded square icon tile (bucket icons, More entries).
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final double size;
  const IconTile(
      {required this.icon,
      this.color = AppTheme.green,
      this.bg = AppTheme.green,
      this.size = 52,
      super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg == AppTheme.green
            ? AppTheme.green
            : bg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: bg == AppTheme.green
            ? null
            : Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Icon(icon,
          color: bg == AppTheme.green ? Colors.black : color, size: 26),
    );
  }
}

/// Compact count: 1240 -> "1.2k", 3200 -> "3.2k".
String formatCompact(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final v = n / 1000;
    return '${v.toStringAsFixed(v < 10 ? 1 : 0)}k';
  }
  final v = n / 1000000;
  return '${v.toStringAsFixed(1)}M';
}

/// Byte size: 128 MB, 1.2 GB, 243 KB, 98 B.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(bytes < 10240 ? 1 : 0)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// Relative time from an ISO timestamp: "just now", "3s ago",
/// "2 hours ago", "Yesterday, 14:32", "3 days ago". Null/empty -> "—".
String relativeTime(String? iso, {DateTime? now}) {
  if (iso == null || iso.isEmpty) return '—';
  final t = DateTime.tryParse(iso);
  if (t == null) return iso;
  final ref = now ?? DateTime.now();
  final d = ref.difference(t.toLocal());
  if (d.inSeconds < 5) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) {
    return d.inMinutes == 1 ? '1 minute ago' : '${d.inMinutes} minutes ago';
  }
  if (d.inHours < 24) {
    return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
  }
  if (d.inDays == 1) {
    final lt = t.toLocal();
    return 'Yesterday, ${lt.hour.toString().padLeft(2, '0')}:${lt.minute.toString().padLeft(2, '0')}';
  }
  if (d.inDays < 7) return '${d.inDays} days ago';
  final lt = t.toLocal();
  return '${lt.year}-${lt.month.toString().padLeft(2, '0')}-${lt.day.toString().padLeft(2, '0')}';
}

/// "JS" initials from an email's local part.
String initialsOf(String email) {
  final local = email.split('@').first;
  final parts = local.split(RegExp(r'[._\-+]'));
  final letters = parts.where((p) => p.isNotEmpty).map((p) => p[0]).toList();
  if (letters.isEmpty) return '?';
  if (letters.length == 1) return letters.first.toUpperCase();
  return (letters[0] + letters[1]).toUpperCase();
}

/// Deterministic avatar colour from a string (green/blue/purple/grey).
Color avatarColorOf(String value) {
  const palette = [
    AppTheme.green,
    PreviewColors.avatarBlue,
    PreviewColors.avatarPurple,
    PreviewColors.avatarGrey,
  ];
  var h = 0;
  for (final c in value.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// Mask a key: "sb_publishable_••••••••a7k2" (first 4 + last 4).
String maskKey(String key) {
  if (key.isEmpty) return '—';
  if (key.length <= 8) return '•' * key.length;
  return '${key.substring(0, 4)}${'•' * 8}${key.substring(key.length - 4)}';
}

/// Copy-to-clipboard icon button with a confirmation snackbar.
class CopyButton extends StatelessWidget {
  final String text;
  const CopyButton(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.copy, color: AppTheme.green, size: 20),
      tooltip: 'Copy',
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied to clipboard')));
        }
      },
    );
  }
}

/// Log level pill: INF green, WRN yellow, ERR red, else grey.
Pill levelPill(String level) {
  final l = level.toUpperCase();
  if (l.contains('ERR')) {
    return const Pill('ERR',
        bg: PreviewColors.dangerRed, fg: Colors.black);
  }
  if (l.contains('WRN') || l.contains('WARN')) {
    return const Pill('WRN',
        bg: PreviewColors.warnYellow, fg: Colors.black);
  }
  return const Pill('INF', bg: AppTheme.green, fg: Colors.black);
}

/// HTTP method pill: GET green, POST orange, DELETE red, else grey.
Pill methodPill(String method) {
  final m = method.toUpperCase();
  if (m == 'POST') {
    return const Pill('POST',
        bg: PreviewColors.methodOrange, fg: Colors.black);
  }
  if (m == 'DELETE') {
    return const Pill('DELETE',
        bg: PreviewColors.dangerRed, fg: Colors.black);
  }
  if (m == 'PUT' || m == 'PATCH') {
    return const Pill('PUT',
        bg: PreviewColors.warnYellow, fg: Colors.black);
  }
  return const Pill('GET', bg: AppTheme.green, fg: Colors.black);
}

/// Postgres change pill: INSERT green, UPDATE orange, DELETE red.
Pill eventPill(String eventType) {
  final e = eventType.toUpperCase();
  if (e == 'UPDATE') {
    return const Pill('UPDATE',
        bg: PreviewColors.methodOrange, fg: Colors.black);
  }
  if (e == 'DELETE') {
    return const Pill('DELETE',
        bg: PreviewColors.dangerRed, fg: Colors.black);
  }
  return const Pill('INSERT', bg: AppTheme.green, fg: Colors.black);
}

/// Provider chip for Auth users: Email (green dot), Google, GitHub.
Widget providerChip(String? provider) {
  final p = (provider ?? 'email').toLowerCase();
  if (p.contains('google')) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(SimpleIcons.google, size: 14),
        SizedBox(width: 6),
        Text('Google', style: TextStyle(fontSize: 13)),
      ]),
    );
  }
  if (p.contains('github')) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(SimpleIcons.github, size: 14),
        SizedBox(width: 6),
        Text('GitHub', style: TextStyle(fontSize: 13)),
      ]),
    );
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.circle, size: 8, color: AppTheme.green),
      SizedBox(width: 6),
      Text('Email', style: TextStyle(fontSize: 13)),
    ]),
  );
}

/// Confirmed chip: green check when confirmed, amber dot when not.
Widget confirmedChip(bool confirmed) {
  return Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(confirmed ? Icons.check_circle : Icons.circle,
        size: 16,
        color: confirmed ? AppTheme.green : PreviewColors.warnYellow),
    const SizedBox(width: 4),
    Text(confirmed ? 'Confirmed' : 'Unconfirmed',
        style: TextStyle(
            color: confirmed ? AppTheme.green : PreviewColors.warnYellow,
            fontWeight: FontWeight.w600,
            fontSize: 13)),
  ]);
}

const _sqlKeywords = {
  'SELECT', 'FROM', 'WHERE', 'ORDER', 'GROUP', 'BY', 'LIMIT', 'OFFSET',
  'DESC', 'ASC', 'AND', 'OR', 'NOT', 'IN', 'IS', 'NULL', 'INSERT', 'INTO',
  'VALUES', 'UPDATE', 'SET', 'DELETE', 'CREATE', 'TABLE', 'ALTER', 'DROP',
  'JOIN', 'LEFT', 'RIGHT', 'INNER', 'OUTER', 'ON', 'AS', 'DISTINCT', 'COUNT',
  'SUM', 'AVG', 'MIN', 'MAX', 'RETURNING', 'HAVING', 'UNION', 'ALL', 'CASE',
  'WHEN', 'THEN', 'ELSE', 'END', 'BEGIN', 'COMMIT', 'ROLLBACK', 'GRANT',
  'REVOKE', 'PRIMARY', 'KEY', 'FOREIGN', 'REFERENCES', 'UNIQUE', 'DEFAULT',
  'WITH', 'EXISTS', 'BETWEEN', 'LIKE', 'ILIKE',
};

/// Syntax-highlight one SQL line: keywords purple, numbers orange,
/// quoted strings green, everything else white.
List<TextSpan> highlightSqlLine(String line) {
  final spans = <TextSpan>[];
  final token = RegExp(
      "('(?:[^']|'')*'|\"(?:[^\"]|\"\")*\"|\\b\\d+(?:\\.\\d+)?\\b|\\b[A-Za-z_][A-Za-z0-9_]*\\b|\\s+|.)");
  for (final m in token.allMatches(line)) {
    final t = m.group(0)!;
    Color? color;
    if (t.startsWith("'") || t.startsWith('"')) {
      color = PreviewColors.stringGreen;
    } else if (RegExp(r'^\d').hasMatch(t)) {
      color = PreviewColors.numberOrange;
    } else if (_sqlKeywords.contains(t.toUpperCase())) {
      color = PreviewColors.keywordPurple;
    }
    spans.add(TextSpan(
        text: t,
        style: TextStyle(
            color: color ?? Colors.white,
            fontFamily: 'monospace',
            fontSize: 14)));
  }
  return spans;
}

/// Read-only SQL view with line numbers, as in the SQL Editor preview.
class SqlCodeView extends StatelessWidget {
  final String code;
  const SqlCodeView(this.code, {super.key});
  @override
  Widget build(BuildContext context) {
    final lines = code.split('\n');
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: lines.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 2),
              child: Text('${e.key + 1}',
                  style: const TextStyle(
                      color: AppTheme.muted,
                      fontFamily: 'monospace',
                      fontSize: 14)),
            )).toList(),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines
              .map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: RichText(
                        text: TextSpan(children: highlightSqlLine(l))),
                  ))
              .toList(),
        ),
      ),
    ]);
  }
}
