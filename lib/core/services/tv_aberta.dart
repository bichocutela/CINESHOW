import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import 'source_session.dart';
import 'audio_metadata.dart';

const tvAbertaOrigin = 'https://tvabertaonline.bbroot.com';
const tvNovelasOrigin = 'https://nexustvnovelas.nexustvnovas.workers.dev';

String novelaName(String value) => cleanAudioTitle(value)
    .replaceFirst(RegExp(r'^Assistir\s+', caseSensitive: false), '')
    .replaceFirst(
        RegExp(r'\s+(?:Dublad[ao]|Legendad[ao])(?:\s+Gr[aá]tis)?$',
            caseSensitive: false),
        '')
    .replaceFirst(RegExp(r'\s+Gr[aá]tis$', caseSensitive: false), '')
    .trim();

List<MediaItem> parseTvNovelas(String body) {
  final raw = jsonDecode(body) as List;
  return raw
      .whereType<Map>()
      .where((v) => v['id'] is String && v['name'] is String)
      .map((v) {
    final id = v['id'] as String;
    return MediaItem(
        id: 'tvaberta:$id',
        title: novelaName(v['name'] as String),
        description: v['plot'] as String? ?? '',
        genre: v['genre'] as String? ?? 'Novela',
        year: int.tryParse('${v['year']}') ?? 0,
        durationMinutes: 0,
        audio: audioLabel(v['name'] as String),
        kind: 'novela',
        posterUrl: v['cover'] as String?,
        sources: [
          MediaSource(
              provider: 'tvaberta',
              sourceId: id,
              pageUrl: '$tvAbertaOrigin/',
              posterUrl: v['cover'] as String?)
        ]);
  }).toList();
}

List<Map<String, dynamic>> parseTvEpisodes(Map data,
    {String base = tvNovelasOrigin}) {
  final seasons = data['temporadas'];
  if (seasons is! Map) return [];
  final rows = <Map<String, dynamic>>[];
  for (final entry in seasons.entries) {
    final season = int.tryParse('${entry.key}');
    if (season == null || entry.value is! List) continue;
    for (final episode in (entry.value as List).whereType<Map>()) {
      final id = episode['sp'];
      final number = int.tryParse('${episode['e']}');
      if (id is! String || id.isEmpty || number == null) continue;
      final url = Uri.parse(base).replace(path: '/play/$id').toString();
      rows.add({
        'id': '$season:$id',
        'page_url': url,
        'season': season,
        'number': number,
        'title': episode['t'] as String? ?? 'Capítulo $number'
      });
    }
  }
  return rows
    ..sort((a, b) {
      final season = (a['season'] as int).compareTo(b['season'] as int);
      return season != 0
          ? season
          : (a['number'] as int).compareTo(b['number'] as int);
    });
}

class TvAbertaService {
  TvAbertaService({SourceSession Function(String)? sessionFactory})
      : sessionFactory = sessionFactory ?? SourceSession.new;
  final SourceSession Function(String) sessionFactory;
  static String? _novels;
  static DateTime? _at;
  static Future<String>? _pending;
  Future<String> _get(String path) async {
    final session = sessionFactory(tvAbertaOrigin);
    try {
      return await session.get(path);
    } finally {
      session.close();
    }
  }

  Future<String> novelData() async {
    if (_novels != null &&
        _at != null &&
        DateTime.now().difference(_at!) < const Duration(minutes: 30))
      return _novels!;
    return _pending ??= (() async {
      final prefs = await SharedPreferences.getInstance();
      try {
        final body = await _get('/json/novelas.json');
        if (jsonDecode(body) is! List)
          throw const FormatException('Novelas inválidas');
        _novels = body;
        _at = DateTime.now();
        await prefs.setString('cineshow.tvaberta.novelas.v1', body);
        return body;
      } catch (_) {
        final saved = prefs.getString('cineshow.tvaberta.novelas.v1');
        if (saved != null) return saved;
        rethrow;
      } finally {
        _pending = null;
      }
    })();
  }

  Future<List<MediaItem>> novelas({String? query}) async {
    final rows = await compute(parseTvNovelas, await novelData());
    return query == null
        ? rows
        : rows
            .where((v) => v.title.toLowerCase().contains(query.toLowerCase()))
            .toList();
  }

  Future<List<Map<String, dynamic>>> episodes(String sourceId) async {
    final rows = jsonDecode(await novelData()) as List;
    final data =
        rows.whereType<Map>().where((v) => v['id'] == sourceId).firstOrNull;
    if (data == null) return [];
    var base = tvNovelasOrigin;
    try {
      final html = await _get('/');
      final declared =
          RegExp(r'''const\s+BASE_NOVELAS\s*=\s*["'](https://[^"']+)["']''')
              .firstMatch(html)?[1];
      final uri = Uri.tryParse(declared ?? '');
      if (uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty) base = uri.origin;
    } catch (_) {/* Retain the last published player origin. */}
    return parseTvEpisodes(data, base: base);
  }

  Future<List<Map<String, dynamic>>> channels({bool cached = false}) async {
    final prefs = await SharedPreferences.getInstance();
    String? body =
        cached ? prefs.getString('cineshow.tvaberta.channels.v1') : null;
    if (cached && body == null) return [];
    if (body == null) {
      body = await _get('/json/canais.json');
      if (jsonDecode(body) is! List)
        throw const FormatException('Canais inválidos');
      await prefs.setString('cineshow.tvaberta.channels.v1', body);
    }
    return (jsonDecode(body) as List)
        .whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .where((v) =>
            v['name'] is String &&
            v['slug'] is String &&
            !['adulto', 'adultos', 'xxx']
                .contains('${v['category']}'.toLowerCase()))
        .toList();
  }

  Future<List<Map<String, dynamic>>> streams(Map channel) async {
    final urls = <String, Map<String, dynamic>>{};
    void add(dynamic raw, {String? referer, bool native = true}) {
      final uri = Uri.tryParse('$raw');
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) return;
      urls.putIfAbsent(
          uri.toString(),
          () => {
                'url': uri.toString(),
                'referrer': referer ?? '$tvAbertaOrigin/',
                'user_agent': 'CINESHOW/0.6.1',
                'native': native
              });
    }

    try {
      final path = channel['is_vercel_api'] == true
          ? '/api/get-embed?id=${Uri.encodeQueryComponent('${channel['api_id']}')}'
          : '/api/get-stream?slug=${Uri.encodeQueryComponent('${channel['slug']}')}';
      final data = jsonDecode(await _get(path)) as Map;
      if (channel['is_vercel_api'] == true) {
        final raw = data['link'];
        if (raw is String) {
          final probe =
              await _probe(raw, '${data['referer'] ?? '$tvAbertaOrigin/'}');
          if (probe != null)
            add(probe.$1,
                referer: '${data['referer'] ?? '$tvAbertaOrigin/'}',
                native: probe.$2);
        }
      } else {
        for (final url in (data['urls'] as List? ?? [data['url']])) {
          add(url);
        }
      }
    } catch (_) {
      /* Published static servers and fallback remain valid candidates. */
    }
    for (final server in (channel['servers'] as List? ?? []).whereType<Map>()) {
      add(server['url']);
    }
    add(channel['stream']);
    try {
      final fallback = jsonDecode(await _get('/json/fallback.json')) as List;
      for (final row in fallback.whereType<Map>().where((v) =>
          v['slug'] == channel['slug'] ||
          '${v['nome']}'.toLowerCase() == '${channel['name']}'.toLowerCase())) {
        final raw = row['src'];
        if (raw is! String) continue;
        final probe = await _probe(raw, '$tvAbertaOrigin/');
        if (probe != null) add(probe.$1, native: probe.$2);
      }
    } catch (_) {/* One missing backup must not discard primary servers. */}
    return urls.values.toList();
  }

  Future<(String, bool)?> _probe(String url, String referer) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) return null;
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..headers.addAll({'Range': 'bytes=0-2047', 'Referer': referer});
      final response =
          await client.send(request).timeout(const Duration(seconds: 12));
      if (![200, 206].contains(response.statusCode)) {
        await response.stream.listen((_) {}).cancel();
        return null;
      }
      final bytes = <int>[];
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 12))) {
        bytes.addAll(chunk.take(2048 - bytes.length));
        if (bytes.length >= 2048) break;
      }
      final prefix = latin1.decode(bytes);
      if (prefix.startsWith('#EXTM3U') ||
          (bytes.length >= 8 && prefix.substring(4, 8) == 'ftyp'))
        return (url, true);
      final hls = RegExp(r'''https?://[^\s"'<>]+\.m3u8[^\s"'<>]*''')
          .firstMatch(prefix)?[0];
      if (hls != null) return (hls, true);
      if (prefix.toLowerCase().contains('<iframe') ||
          prefix.toLowerCase().contains('<video')) return (url, false);
      return null;
    } finally {
      client.close();
    }
  }
}
