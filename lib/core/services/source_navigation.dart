import 'source_origins.dart';

/// Embedded players may use a third-party frame, but must not replace the movie
/// page with an unrelated top-level destination (e.g. an advertising redirect).
class SourceNavigationPolicy {
  SourceNavigationPolicy(String initialUrl)
      : retryUrl = initialUrl,
        allowedOrigins = {Uri.parse(initialUrl).origin} {
    final initial = Uri.parse(initialUrl);
    final provider = sourceHostAliases[initial.host];
    if (provider != null) {
      allowedOrigins.add(origins[provider]!);
      for (final alias in sourceHostAliases.entries) {
        if (alias.value == provider) {
          allowedOrigins.add('https://${alias.key}');
        }
      }
    }
  }
  final Set<String> allowedOrigins;
  String retryUrl;

  bool allows(String url, {required bool isMainFrame}) {
    if (!isMainFrame && url == 'about:blank') return true;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    if (!isMainFrame) return true;
    if (!allowedOrigins.contains(uri.origin)) return false;
    retryUrl = uri.toString();
    return true;
  }
}
