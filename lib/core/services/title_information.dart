import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import 'source_html.dart';
import 'source_origins.dart';
import 'actor_catalog.dart';
import 'public_title_metadata.dart';

const metadataApiBase = String.fromEnvironment('CINESHOW_API_URL');

String? sourceImdbId(String html) {
  final central =
      html.split(RegExp(r'<aside\b|class=["\x27]srelacionados')).first;
  final ids = <String>{};
  for (final tag in RegExp(r'<(?:a|iframe)\b[^>]*>').allMatches(central)) {
    final a = attributes(tag[0]!);
    for (final url in [a['href'], a['src']].whereType<String>()) {
      for (final match in RegExp(r'\btt\d{7,10}\b').allMatches(url)) {
        ids.add(match[0]!);
      }
    }
  }
  return ids.length == 1 ? ids.single : null;
}

String sourceSynopsis(String html) {
  final block =
      RegExp(r'''<div[^>]+class=["'][^"']*\bwp-content\b[^"']*["'][^>]*>(.*?)</div>''',
                  dotAll: true)
              .firstMatch(html)?[1] ??
          '';
  final paragraphs = <String>[];
  for (final p
      in RegExp(r'<p\b[^>]*>(.*?)</p>', dotAll: true).allMatches(block)) {
    final text = plain(p[1]!);
    if (text.length < 30 ||
        p[1]!.contains('<img') ||
        RegExp(r'^(Onde|Assistir|Que ano|Foi lançado|Confira)\b',
                caseSensitive: false)
            .hasMatch(text)) {
      continue;
    }
    paragraphs.add(text);
    if (paragraphs.length == 3) break;
  }
  if (paragraphs.isEmpty) {
    for (final tag in RegExp(r'<meta\b[^>]*>').allMatches(html)) {
      final a = attributes(tag[0]!);
      if (a['name'] != 'description') continue;
      final text = plain(a['content'] ?? '');
      if (text.length > 40 &&
          !RegExp(r'^(Assistir|Assista|SuperFlix)', caseSensitive: false)
              .hasMatch(text)) {
        paragraphs.add(text);
      }
    }
  }
  return paragraphs.join('\n\n');
}

Map<String, dynamic> sourceFacts(String html) {
  final facts = <String, String>{};
  for (final row
      in RegExp(r'<dt\b[^>]*>(.*?)</dt>\s*<dd\b[^>]*>(.*?)</dd>', dotAll: true)
          .allMatches(html)) {
    facts[plain(row[1]!).toLowerCase().replaceAll(':', '').trim()] =
        plain(row[2]!);
  }
  final cast = (facts['elenco'] ?? '')
      .split(',')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();
  return {
    if (cast.isNotEmpty) 'cast': cast,
    if ((facts['direção'] ?? '').isNotEmpty) 'director': facts['direção'],
    if ((facts['lançamento'] ?? '').isNotEmpty) 'released': facts['lançamento'],
    if ((facts['ano'] ?? '').isNotEmpty) 'sourceYear': facts['ano']
  };
}

class TitleInformationService {
  TitleInformationService(
      {http.Client Function()? clientFactory, String? apiBase})
      : clientFactory = clientFactory ?? http.Client.new,
        apiBase = apiBase ?? metadataApiBase;
  final http.Client Function() clientFactory;
  final String apiBase;
  static final instance = TitleInformationService();
  final pending = <String, Future<Map<String, dynamic>>>{};

  Future<Map<String, dynamic>> load(MediaItem item, MediaSource? source,
      {bool force = false}) {
    final key =
        'cineshow.titleinfo.v2:${source?.provider}:${source?.sourceId}:${item.id}';
    return pending.putIfAbsent(key, () async {
      try {
        return await _load(key, item, source, force);
      } finally {
        pending.remove(key);
      }
    });
  }

  Future<Map<String, dynamic>> _load(
      String key, MediaItem item, MediaSource? source, bool force) async {
    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      try {
        final cached = jsonDecode(prefs.getString(key) ?? '{}') as Map;
        final at = DateTime.parse(cached['at'] as String);
        if (DateTime.now().difference(at) < const Duration(hours: 6)) {
          return Map<String, dynamic>.from(cached['data'] as Map);
        }
      } catch (_) {}
    }
    final result = <String, dynamic>{
      'plot': item.description,
      'plotSource': 'Catálogo',
      'title': item.title,
      'year': item.year
    };
    final client = clientFactory();
    Future<String> read(Uri uri) async {
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw StateError('Endereço de metadados inválido.');
      }
      final request = http.Request('GET', uri)
        ..headers['User-Agent'] = 'CINESHOW-Metadata/0.6.1';
      final response =
          await client.send(request).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw StateError('Metadados indisponíveis.');
      }
      final bytes = <int>[];
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > 2000000) throw StateError('Resposta muito grande.');
      }
      return utf8.decode(bytes, allowMalformed: true);
    }

    try {
      final sources = <MediaSource>[
        if (source != null) source,
        ...item.sources.where((v) => v.provider != source?.provider || v.sourceId != source?.sourceId)
      ];
      final pages = await Future.wait(sources.map((entry) async {
        if (entry.provider == 'superflix' || entry.provider == 'tvaberta') return null;
        try {
          final uri = Uri.parse(canonicalSourceUrl(entry.pageUrl));
          if (uri.origin != origins[entry.provider]) return null;
          return (source: entry, html: await read(uri));
        } catch (_) { return null; }
      }));
      final ids = pages.whereType<({MediaSource source, String html})>()
          .map((v) => sourceImdbId(v.html)).whereType<String>().toSet();
      final selectedId = pages.whereType<({MediaSource source, String html})>()
          .where((v) => v.source == source).map((v) => sourceImdbId(v.html)).whereType<String>().firstOrNull;
      final confirmedId = selectedId ?? (ids.length == 1 ? ids.single : null);
      result['imdbId'] = confirmedId;
      for (final page in pages.whereType<({MediaSource source, String html})>()) {
        final pageId = sourceImdbId(page.html);
        if (confirmedId != null && pageId != null && pageId != confirmedId) continue;
        final plot = sourceSynopsis(page.html);
        if (plot.isNotEmpty && (result['plotSource'] == 'Catálogo' || (result['plot'] as String).isEmpty)) {
          result['plot'] = plot;
          result['plotSource'] = page.source.label;
        }
        final facts = sourceFacts(page.html);
        final people = publishedCredits(page.html);
        result['cast'] = mergeCast([...(result['cast'] as List? ?? []), ...(facts['cast'] as List? ?? []), ...(people['cast'] as List? ?? [])]);
        result['castDetails'] = [...(result['castDetails'] as List? ?? []), ...(people['castDetails'] as List? ?? [])];
        for (final values in [facts, people]) {
          for (final field in ['director', 'released', 'sourceYear']) {
            if (result[field] == null && values[field] != null) result[field] = values[field];
          }
        }
        final score = publishedImdbRating(page.html);
        if (score != null && confirmedId != null && pageId == confirmedId && result['imdbRating'] == null) {
          result['imdbRating'] = score;
          result['imdbRatingSource'] = 'IMDb informado por ${page.source.label}';
        }
      }
      final id = result['imdbId'] as String?;
      if (id != null) {
        await Future.wait([
          (() async {
            try {
              final raw = jsonDecode(await read(Uri.https(
                  'v2.sg.media-imdb.com', '/suggestion/t/$id.json'))) as Map;
              for (final row in ((raw['d'] as List?) ?? []).whereType<Map>()) {
                if (row['id'] != id) continue;
                final qid = '${row['qid']}'.toLowerCase();
                if (qid.contains('episode') || qid == 'name') continue;
                if (item.kind == 'movie' && qid.contains('series')) continue;
                if (item.kind != 'movie' && qid == 'movie') continue;
                result['title'] = row['l'];
                result['year'] = row['y'];
                result['identitySource'] = 'IMDb';
                if (row['s'] is String) {
                  result['cast'] = mergeCast([...(result['cast'] as List? ?? []), ...(row['s'] as String).split(',')]);
                }
              }
            } catch (_) {}
          })(),
          (() async {
            if (apiBase.isEmpty) return;
            try {
              final uri = Uri.parse(apiBase)
                  .resolve('/v1/metadata')
                  .replace(queryParameters: {'imdb_id': id});
              final data = jsonDecode(await read(uri)) as Map;
              if (data['imdbId'] != id || data['verified'] != true) return;
              final type = data['type'];
              if (type != (item.kind == 'movie' ? 'movie' : 'series')) return;
              result['title'] = data['title'];
              result['year'] = data['year'];
              for (final field in [
                'cast',
                'director',
                'released',
                'runtime',
                'genres'
              ]) {
                if (data[field] != null && data[field] != '') {
                  result[field] = field == 'cast' ? mergeCast([...(result['cast'] as List? ?? []), ...(data['cast'] as List? ?? [])]) : data[field];
                }
              }
              if ((data['plot'] as String? ?? '').isNotEmpty) {
                result['plot'] = data['plot'];
                result['plotSource'] = 'OMDb · ID IMDb confirmado';
              }
              final imdb = double.tryParse('${data['imdbRating']}');
              if (imdb != null && imdb >= 0 && imdb <= 10) {
                result['imdbRating'] = imdb;
                result['imdbRatingSource'] = 'IMDb via OMDb';
                result['imdbVotes'] = data['imdbVotes'];
              }
              final rt = int.tryParse('${data['rtRating']}');
              final rtUri = Uri.tryParse('${data['rtUrl']}');
              if (rt != null &&
                  rt >= 0 &&
                  rt <= 100 &&
                  rtUri != null &&
                  rtUri.scheme == 'https' &&
                  rtUri.host == 'www.rottentomatoes.com' &&
                  RegExp(r'^/(?:m|tv)/[a-zA-Z0-9_./-]+$')
                      .hasMatch(rtUri.path)) {
                result['rtRating'] = rt;
                result['rtUrl'] = rtUri.toString();
              }
            } catch (_) {}
          })()
        ]);
        try {
          final html = await read(Uri.https('www.imdb.com', '/title/$id/'));
          final public = publicImdbTitle(html, id, movie: item.kind == 'movie');
          result['cast'] = mergeCast([...(result['cast'] as List? ?? []), ...(public['cast'] as List? ?? [])]);
          for (final field in ['imdbRating', 'imdbRatingSource', 'director']) {
            if (public[field] != null && public[field] != '') result[field] = public[field];
          }
        } catch (_) { /* Public access may be refused. Keep attributed source data. */ }
      }
      try {
        final public = await fetchPublicRotten(read, '${result['title']}',
            (result['year'] as num? ?? item.year).toInt(), movie: item.kind == 'movie');
        result['cast'] = mergeCast([...(result['cast'] as List? ?? []), ...(public['cast'] as List? ?? [])]);
        result['castDetails'] = [...(result['castDetails'] as List? ?? []), ...(public['castDetails'] as List? ?? [])];
        for (final field in ['rtUrl', 'rtRating', 'rtAudienceRating']) {
          if (public[field] != null) result[field] = public[field];
        }
      } catch (_) { /* No invented scores when the public page cannot be read. */ }
    } finally {
      client.close();
    }
    try {
      await ActorCatalog().record(
          item, ((result['cast'] as List?) ?? []).whereType<String>().toList());
      await prefs.setString(key,
          jsonEncode({'at': DateTime.now().toIso8601String(), 'data': result}));
    } catch (_) {
      // Metadata must remain readable if local persistence is unavailable.
    }
    return result;
  }
}
