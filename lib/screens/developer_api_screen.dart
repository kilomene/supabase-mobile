import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_mobile/models/models.dart';
import 'package:supabase_mobile/services/management_api_client.dart';
import 'package:supabase_mobile/services/project_client_registry.dart';
import 'package:supabase_mobile/theme/app_theme.dart';
import 'package:supabase_mobile/widgets/common.dart';

/// Developer — API Docs (preview 5). Live: PostgREST + GraphQL against
/// the selected project. Docs themselves are fetched as data
/// (supabase.com/llms.txt / per-page .md) — never a dashboard WebView.
/// The code examples are built from the REAL project URL and the REAL
/// publishable key (GET /v1/projects/{ref}/api-keys, type/name
/// "publishable"); the key is truncated to its first 20 chars + "..."
/// in the display exactly like the preview, and {{SUPABASE_KEY}} is
/// used as the placeholder when no key is available.
class DeveloperApiScreen extends StatefulWidget {
  final SupabaseProject project;
  const DeveloperApiScreen({required this.project, super.key});
  @override
  State<DeveloperApiScreen> createState() => _DeveloperApiScreenState();
}

class _DeveloperApiScreenState extends State<DeveloperApiScreen> {
  final _gql = TextEditingController(text: '{ __schema { types { name } } }');
  String? _gqlResult;
  bool _busy = false;
  String? _error;
  int _tab = 0; // 0 REST, 1 GraphQL, 2 Realtime
  String? _publishableKey;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    try {
      final keys =
          await ManagementApiClient().listApiKeys(widget.project.ref);
      for (final k in keys) {
        final hay = '${k.name} ${k.type ?? ''}'.toLowerCase();
        if (hay.contains('publishable') &&
            k.apiKey != null &&
            k.apiKey!.isNotEmpty) {
          if (mounted) setState(() => _publishableKey = k.apiKey);
          return;
        }
      }
    } catch (_) {
      // No key available — the examples fall back to {{SUPABASE_KEY}}.
    }
  }

  /// Display form of the publishable key: first 20 chars + "...",
  /// or the {{SUPABASE_KEY}} placeholder when none is available.
  String get _displayKey {
    final k = _publishableKey;
    if (k == null || k.isEmpty) return '{{SUPABASE_KEY}}';
    if (k.length > 20) return '${k.substring(0, 20)}...';
    return k;
  }

  String get _restExample =>
      'fetch("${widget.project.url}/rest/v1/users", {\n'
      "  method: 'GET',\n"
      '  headers: {\n'
      "    apikey: '$_displayKey',\n"
      "    Authorization: 'Bearer {{SUPABASE_KEY}}'\n"
      '  }\n'
      '})\n'
      '.then(res => res.json())\n'
      '.then(data => console.log(data));';

  String get _realtimeExample =>
      "const supabase = createClient('${widget.project.url}', '$_displayKey');\n"
      'supabase\n'
      "  .channel('public:users')\n"
      "  .on('postgres_changes', {\n"
      "    event: '*',\n"
      "    schema: 'public',\n"
      "    table: 'users'\n"
      '  }, (payload) => {\n'
      '    console.log(payload);\n'
      '  })\n'
      '  .subscribe();';

  static const _graphqlExample = '{\n'
      '  users {\n'
      '    id\n'
      '    email\n'
      '  }\n'
      '}';

  String get _exampleCode {
    return switch (_tab) {
      1 => _graphqlExample,
      2 => _realtimeExample,
      _ => _restExample,
    };
  }

  String get _exampleLanguage {
    return switch (_tab) {
      1 => 'GraphQL',
      _ => 'JavaScript',
    };
  }

  Future<void> _runGraphql() async {
    setState(() => _busy = true);
    try {
      final api = await ProjectClientRegistry().apiClient(widget.project);
      final r = await api.graphql(_gql.text);
      if (mounted) setState(() => _gqlResult = '$r');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied to clipboard')));
    }
  }

  static const _jsKeywords = {
    'fetch', 'method', 'headers', 'apikey', 'Authorization', 'then',
    'console', 'log', 'const', 'createClient', 'channel', 'on',
    'subscribe', 'return', 'event', 'schema', 'table', 'payload',
  };

  /// Simple JS/GraphQL highlighting: strings green, keywords purple,
  /// numbers orange, everything else white.
  List<TextSpan> _highlightCode(String code) {
    final spans = <TextSpan>[];
    final token = RegExp(
        r'''('[^']*'|"[^"]*"|`[^`]*`|\b\d+(?:\.\d+)?\b|\b[A-Za-z_][A-Za-z0-9_]*\b|\s+|.)''');
    for (final m in token.allMatches(code)) {
      final t = m.group(0)!;
      Color? color;
      if (t.startsWith("'") || t.startsWith('"') || t.startsWith('`')) {
        color = PreviewColors.stringGreen;
      } else if (RegExp(r'^\d').hasMatch(t)) {
        color = PreviewColors.numberOrange;
      } else if (_jsKeywords.contains(t)) {
        color = PreviewColors.keywordPurple;
      }
      spans.add(TextSpan(
          text: t,
          style: TextStyle(
              color: color ?? Colors.white,
              fontFamily: 'monospace',
              fontSize: 13)));
    }
    return spans;
  }

  Widget _tabButton(String label, int index) {
    final active = _tab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                  color: active ? AppTheme.green : Colors.transparent,
                  width: 3),
            ),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: active ? AppTheme.green : AppTheme.muted,
                  fontWeight:
                      active ? FontWeight.bold : FontWeight.normal,
                  fontSize: 16)),
        ),
      ),
    );
  }

  Widget _endpointRow(String method, String path) {
    final fullUrl = '${widget.project.url}$path';
    return RichCard(
      child: Row(
        children: [
          methodPill(method),
          const SizedBox(width: 12),
          Expanded(
            child: Text(path,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          CopyButton(fullUrl),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(
            children: [
              const SupaBolt(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Supabase',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    Text(widget.project.name,
                        style: const TextStyle(color: AppTheme.muted)),
                  ],
                ),
              ),
              const CircleAvatar(
                backgroundColor: PreviewColors.avatarGrey,
                child: Text('?',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.more_horiz),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Developer — API Docs',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _tabButton('REST', 0),
                _tabButton('GraphQL', 1),
                _tabButton('Realtime', 2),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionLabel('Code Example'),
          const SizedBox(height: 8),
          RichCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_exampleLanguage,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _copy(_exampleCode),
                      icon: const Icon(Icons.copy,
                          size: 18, color: AppTheme.green),
                      label: const Text('Copy',
                          style: TextStyle(color: AppTheme.green)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText.rich(
                  TextSpan(children: _highlightCode(_exampleCode)),
                ),
              ],
            ),
          ),
          if (_tab == 1) ...[
            const SizedBox(height: 20),
            const SectionLabel('GraphQL Runner'),
            const SizedBox(height: 8),
            TextField(
              controller: _gql,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration:
                  const InputDecoration(labelText: 'GraphQL query'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: _busy ? null : _runGraphql,
                  child: const Text('Run GraphQL')),
            ),
            if (_busy) const LoadingView(),
            if (_error != null) ErrorView(_error!),
            if (_gqlResult != null) ...[
              const SizedBox(height: 12),
              RichCard(
                child: SelectableText(_gqlResult!,
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ],
          const SizedBox(height: 24),
          const SectionLabel('Endpoints'),
          const SizedBox(height: 12),
          _endpointRow('GET', '/rest/v1/users'),
          const SizedBox(height: 12),
          _endpointRow('POST', '/auth/v1/signup'),
          const SizedBox(height: 12),
          _endpointRow('GET', '/storage/v1/bucket'),
        ]),
      ),
    );
  }
}
