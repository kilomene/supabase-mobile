import 'package:url_launcher/url_launcher.dart';

/// NO_ENDPOINT features (research report §4) — dashboard-only.
/// The app must deep-link to the system browser for these, never fake
/// data and never wrap supabase.com in a WebView.
class DashboardLinks {
  static Future<void> open(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open $uri');
    }
  }

  static Future<void> signUp() => open(Uri.parse('https://supabase.com'));
  static Future<void> signIn() =>
      open(Uri.parse('https://supabase.com/dashboard/sign-in'));
  static Future<void> signUpPage() =>
      open(Uri.parse('https://supabase.com/dashboard/sign-up'));
  static Future<void> dashboard() =>
      open(Uri.parse('https://supabase.com/dashboard'));
  static Future<void> accessTokens() => open(
      Uri.parse('https://supabase.com/dashboard/account/tokens'));
  static Future<void> orgBilling(String orgSlug) => open(Uri.parse(
      'https://supabase.com/dashboard/org/$orgSlug/billing'));
  static Future<void> orgUsage(String orgSlug) => open(Uri.parse(
      'https://supabase.com/dashboard/org/$orgSlug/usage'));
  static Future<void> projectBilling(String ref) => open(Uri.parse(
      'https://supabase.com/dashboard/project/$ref/settings/billing'));
  static Future<void> support() =>
      open(Uri.parse('https://supabase.com/support'));
  static Future<void> status() =>
      open(Uri.parse('https://status.supabase.com'));
}
