import 'dart:convert';
import 'public_title_metadata.dart';
import 'source_html.dart';

String? originalSourceTitle(String html) {
  for (final field in RegExp(
          r'''<div[^>]+class=["'][^"']*custom_fields[^"']*["'][^>]*>(.*?)</div>''',
          dotAll: true)
      .allMatches(html)) {
    final label = RegExp(r'<b\b[^>]*>(.*?)</b>', dotAll: true)
            .firstMatch(field[1]!)?[1] ??
        '';
    if (!['titulooriginal', 'originaltitle']
        .contains(normalizedTitle(label).replaceAll('í', 'i'))) continue;
    final value = RegExp(r'<span\b[^>]*>(.*?)</span>', dotAll: true)
        .firstMatch(field[1]!)?[1];
    if (value == null) continue;
    var title = plain(value);
    final seo =
        RegExp(r'^(?:Watch|Assistir)\s+(.+?)\s+Online$', caseSensitive: false)
            .firstMatch(title);
    if (seo != null) title = seo[1]!;
    if (title.isNotEmpty) return title;
  }
  return null;
}

Map<String, dynamic>? matchImdbSuggestion(
    Map raw, Iterable<String> aliases, int year,
    {required bool movie, String? expectedId}) {
  final names = aliases.map(normalizedTitle).where((v) => v.isNotEmpty).toSet();
  final found = <String, Map<String, dynamic>>{};
  for (final row in (raw['d'] as List? ?? []).whereType<Map>()) {
    final id = row['id'];
    if (id is! String || !RegExp(r'^tt\d{7,10}$').hasMatch(id)) continue;
    final type = '${row['qid']}'.toLowerCase();
    if (movie ? type != 'movie' : !['tvseries', 'tvminiseries'].contains(type))
      continue;
    if (expectedId != null) {
      if (id != expectedId) continue;
    } else {
      if (year > 0 && row['y'] != year) continue;
      if (!names.contains(normalizedTitle('${row['l']}'))) continue;
    }
    found[id] = Map<String, dynamic>.from(row);
  }
  return found.length == 1 ? found.values.single : null;
}

Future<Map<String, dynamic>?> findTitleIdentity(
    Future<String> Function(Uri) read, Iterable<String> aliases, int year,
    {required bool movie}) async {
  for (final alias
      in aliases.where((v) => v.trim().isNotEmpty).toSet().take(2)) {
    final query = alias
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\u00c0-\uffff\s-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (query.isEmpty) continue;
    try {
      final raw = jsonDecode(await read(Uri.https(
              'v2.sg.media-imdb.com', '/suggestion/${query[0]}/$query.json')))
          as Map;
      final match = matchImdbSuggestion(raw, aliases, year, movie: movie);
      if (match != null) return match;
    } catch (_) {/* An unavailable lookup must not attach a different movie. */}
  }
  return null;
}
