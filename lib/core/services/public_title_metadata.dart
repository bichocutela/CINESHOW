import 'dart:convert';
import 'source_html.dart';

String normalizedTitle(String value) => plain(value)
    .toLowerCase()
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'[^a-z0-9\u00c0-\u024f]'), '');

List<String> mergeCast(Iterable<dynamic> values) {
  final names = <String, String>{};
  for (final value in values) {
    if (value is! String) continue;
    final name = plain(value).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isNotEmpty) names.putIfAbsent(name.toLowerCase(), () => name);
  }
  return names.values.toList();
}

double? ratingNumber(dynamic raw, double maximum) {
  final number =
      double.tryParse('$raw'.replaceAll('%', '').replaceAll(',', '.').trim());
  return number != null && number.isFinite && number >= 0 && number <= maximum
      ? number
      : null;
}

/// Only the field explicitly labelled IMDb by the source, never its user/TMDb score.
double? publishedImdbRating(String html) {
  final block =
      RegExp(r'''<b\b[^>]*id=["']repimdb["'][^>]*>(.*?)</b>''', dotAll: true)
          .firstMatch(html)?[1];
  if (block == null) return null;
  final score = RegExp(r'<strong\b[^>]*>(.*?)</strong>', dotAll: true)
      .firstMatch(block)?[1];
  return score == null ? null : ratingNumber(plain(score), 10);
}

Map<String, dynamic> publishedCredits(String html) {
  // The source places its actual credits before related-title sidebars.
  final body = html
      .split(RegExp(r'<aside\b|class=["\x27]srelacionados|id=["\x27]related'))
      .first;
  final people =
      RegExp(r'''<(?:div|li)\b[^>]*itemprop=["'](actor|director)["'][^>]*>''')
          .allMatches(body)
          .toList();
  final cast = <String>[];
  final directors = <String>[];
  final details = <Map<String, String>>[];
  for (var n = 0; n < people.length; n++) {
    final block = body.substring(people[n].end,
        n + 1 < people.length ? people[n + 1].start : body.length);
    String? name;
    for (final tag in RegExp(r'<meta\b[^>]*>').allMatches(block)) {
      final a = attributes(tag[0]!);
      if (a['itemprop'] == 'name') {
        name = a['content'];
        break;
      }
    }
    if (name == null || name.trim().isEmpty) continue;
    if (people[n][1] == 'director') {
      directors.add(plain(name));
      continue;
    }
    cast.add(plain(name));
    final role = RegExp(r'''<div[^>]+class=["']caracter["'][^>]*>(.*?)</div>''',
            dotAll: true)
        .firstMatch(block)?[1];
    String? archive;
    for (final link in RegExp(r'<a\b([^>]*)>(.*?)</a>', dotAll: true).allMatches(block)) {
      if (normalizedTitle(link[2]!) == normalizedTitle(name)) {
        archive = attributes(link[1]!)['href'];
        if (archive != null) break;
      }
    }
    details.add({'name': plain(name), 'role': plain(role ?? ''), if (archive != null) 'archive_url': archive});
  }
  return {
    'cast': mergeCast(cast),
    'castDetails': details,
    if (directors.isNotEmpty) 'director': mergeCast(directors).join(', ')
  };
}

Iterable<Map> structuredTitles(String html) sync* {
  for (final script in RegExp(r'<script\b([^>]*)>(.*?)</script>', dotAll: true)
      .allMatches(html)) {
    if (attributes(script[1]!)['type'] != 'application/ld+json') continue;
    try {
      final raw = jsonDecode(script[2]!);
      final nodes = raw is List
          ? raw
          : raw is Map && raw['@graph'] is List
              ? raw['@graph'] as List
              : [raw];
      for (final node in nodes) {
        if (node is Map &&
            ['Movie', 'TVSeries', 'TVMiniSeries'].contains(node['@type'])) {
          yield node;
        }
      }
    } catch (_) {/* A malformed metadata block must not hide other blocks. */}
  }
}

List<String> schemaActors(Map node) => mergeCast(
    ((node['actor'] is List ? node['actor'] : [node['actor']]) as List)
        .whereType<Map>()
        .map((v) => v['name']));

Map<String, dynamic> publicImdbTitle(String html, String imdbId,
    {required bool movie}) {
  for (final node in structuredTitles(html)) {
    final url = Uri.tryParse('${node['url'] ?? node['@id']}');
    if (url == null ||
        !['www.imdb.com', 'imdb.com'].contains(url.host) ||
        !url.path.startsWith('/title/$imdbId/') ||
        (node['@type'] == 'Movie') != movie) {
      continue;
    }
    final aggregate = node['aggregateRating'];
    final score = aggregate is Map &&
            ratingNumber(aggregate['bestRating'] ?? 10, 10) == 10
        ? ratingNumber(aggregate['ratingValue'], 10)
        : null;
    return {
      'cast': schemaActors(node),
      if (score != null) 'imdbRating': score,
      if (score != null) 'imdbRatingSource': 'IMDb',
      if (node['director'] is List)
        'director': mergeCast((node['director'] as List)
            .whereType<Map>()
            .map((v) => v['name'])).join(', ')
    };
  }
  return {};
}

List<Uri> rottenCandidates(String html, String title, int year,
    {required bool movie}) {
  final found = <String, Uri>{};
  if (year <= 0) return [];
  for (final row in RegExp(
          r'<search-page-media-row\b([^>]*)>(.*?)</search-page-media-row>',
          dotAll: true)
      .allMatches(html)) {
    final a = attributes(row[1]!);
    final rowYear = int.tryParse(
        a[movie ? 'release-year' : 'start-year'] ?? a['release-year'] ?? '');
    if (rowYear != year) continue;
    for (final link
        in RegExp(r'<a\b([^>]*)>(.*?)</a>', dotAll: true).allMatches(row[2]!)) {
      final attr = attributes(link[1]!);
      if (attr['data-qa'] != 'info-name' ||
          normalizedTitle(link[2]!) != normalizedTitle(title)) {
        continue;
      }
      final uri = Uri.parse('https://www.rottentomatoes.com/')
          .resolve(attr['href'] ?? '');
      if (uri.scheme != 'https' ||
          uri.host != 'www.rottentomatoes.com' ||
          uri.userInfo.isNotEmpty ||
          !RegExp(movie ? r'^/m/[a-zA-Z0-9_-]+$' : r'^/tv/[a-zA-Z0-9_-]+$')
              .hasMatch(uri.path)) {
        continue;
      }
      found[uri.toString()] = uri;
    }
  }
  // Remakes or conflicting matches must not borrow another title's percentages.
  return found.length == 1 ? found.values.toList() : [];
}

bool matchesRottenTitle(String html, Uri uri, String title, int year,
    {required bool movie}) {
  String? canonical;
  for (final link in RegExp(r'<link\b[^>]*>').allMatches(html)) {
    final a = attributes(link[0]!);
    if (a['rel'] == 'canonical') canonical = a['href'];
  }
  if (canonical != uri.toString()) return false;
  for (final node in structuredTitles(html)) {
    if ((node['@type'] == 'Movie') != movie ||
        normalizedTitle('${node['name']}') != normalizedTitle(title) ||
        node['url'] != canonical) {
      continue;
    }
    final released = int.tryParse(
        '${node['dateCreated'] ?? node['datePublished'] ?? ''}'
            .split('-')
            .first);
    if (released != null && released != year) continue;
    return true;
  }
  return false;
}

Map<String, dynamic> publicRottenTitle(
    String html, Uri uri, String title, int year,
    {required bool movie}) {
  if (!matchesRottenTitle(html, uri, title, year, movie: movie)) return {};
  final result = <String, dynamic>{'rtUrl': uri.toString()};
  for (final script in RegExp(r'<script\b([^>]*)>(.*?)</script>', dotAll: true)
      .allMatches(html)) {
    if (attributes(script[1]!)['id'] != 'media-scorecard-json') continue;
    try {
      final data = jsonDecode(script[2]!) as Map;
      for (final entry in {
        'criticsScore': 'rtRating',
        'audienceScore': 'rtAudienceRating'
      }.entries) {
        final raw = data[entry.key];
        if (raw is! Map ||
            (entry.key == 'audienceScore' &&
                data['hideAudienceScore'] == true)) {
          continue;
        }
        final score = ratingNumber(raw['scorePercent'], 100);
        if (score != null) result[entry.value] = score.toInt();
      }
    } catch (_) {/* No score is preferable to an unrelated score. */}
  }
  result['cast'] = mergeCast(structuredTitles(html).expand(schemaActors));
  return result;
}

List<Map<String, String>> rottenCredits(String html) {
  final found = <String, Map<String, String>>{};
  for (final card in RegExp(
          r'<cast-and-crew-card\b([^>]*)>(.*?)</cast-and-crew-card>',
          dotAll: true)
      .allMatches(html)) {
    if (!(attributes(card[1]!)['data-role'] ?? '')
        .split(',')
        .contains('cast')) {
      continue;
    }
    final slots = <String, String>{};
    for (final text
        in RegExp(r'<rt-text\b([^>]*)>(.*?)</rt-text>', dotAll: true)
            .allMatches(card[2]!)) {
      slots[attributes(text[1]!)['slot'] ?? ''] = plain(text[2]!);
    }
    final name = slots['title'] ?? '';
    if (name.isNotEmpty) {
      found[name.toLowerCase()] = {
        'name': name,
        'role': slots['characters'] ?? ''
      };
    }
  }
  return found.values.toList();
}

Future<Map<String, dynamic>> fetchPublicRotten(
    Future<String> Function(Uri) read, String title, int year,
    {required bool movie}) async {
  final search = await read(
      Uri.https('www.rottentomatoes.com', '/search', {'search': title}));
  final candidates = rottenCandidates(search, title, year, movie: movie);
  if (candidates.isEmpty) return {};
  final uri = candidates.single;
  final html = await read(uri);
  final data = publicRottenTitle(html, uri, title, year, movie: movie);
  if (data.isEmpty) return {};
  try {
    final full = await read(uri.replace(path: '${uri.path}/cast-and-crew'));
    if (matchesRottenTitle(full, uri, title, year, movie: movie)) {
      final credits = rottenCredits(full);
      data['castDetails'] = credits;
      data['cast'] = mergeCast(
          [...(data['cast'] as List? ?? []), ...credits.map((v) => v['name'])]);
    }
  } catch (_) {/* Main-page credits remain available. */}
  return data;
}
