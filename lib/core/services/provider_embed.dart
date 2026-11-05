import 'dart:convert';
import 'player_migrations.dart';

String providerEmbedHtml(String url) {
  url = canonicalPlayerUrl(url);
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw ArgumentError('Player inválido');
  }
  final escaped = const HtmlEscape().convert(url);
  return '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">'
      '<style>html,body{margin:0;width:100%;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style>'
      '</head><body><iframe src="$escaped" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen></iframe></body></html>';
}

String providerEmbedBase(String url, Map<String, String> headers) {
  url = canonicalPlayerUrl(url);
  final referer = Uri.tryParse(canonicalPlayerUrl(headers['Referer'] ?? ''));
  return referer != null &&
          referer.scheme == 'https' &&
          referer.host.isNotEmpty &&
          referer.userInfo.isEmpty
      ? referer.toString()
      : '${Uri.parse(url).origin}/';
}
