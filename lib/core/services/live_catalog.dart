import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

const apiBase = String.fromEnvironment('CINESHOW_API_URL');
const origins = {
  'rtfilmes': 'https://rtfilmes.com',
  'tontons': 'https://tontonsfilmeurs.com',
  'xonados': 'https://www.xonados.com'
};
const providerOrigins = {
  'rtfilmes': {'https://rtfilmes.com', 'https://assistirfilmeshdonline.com'},
  'tontons': {'https://tontonsfilmeurs.com'},
  'xonados': {'https://www.xonados.com'},
};
bool providerPage(String provider, String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.scheme == 'https' &&
      (providerOrigins[provider]?.contains(uri.origin) ?? false);
}

String plain(String s) => s
    .replaceAll(RegExp('<[^>]+>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&#8211;', '–')
    .trim();
Map<String, String> attributes(String s) => {
      for (final m in RegExp(r'''([\w-]+)\s*=\s*(["'])(.*?)\2''', dotAll: true)
          .allMatches(s))
        m[1]!: m[3]!.replaceAll('&amp;', '&')
    };

class SourceSession {
  SourceSession(this.origin);
  final String origin;
  final _client = http.Client();
  final Map<String, String> _cookies = {};
  Future<String> get(String path, {String? body}) async {
    final uri = Uri.parse(path.startsWith('https://') ? path : '$origin$path');
    if (uri.origin != origin) throw StateError('Origem inválida');
    final headers = <String, String>{
      if (_cookies.isNotEmpty)
        'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ')
    };
    final response = await (body == null
            ? _client.get(uri, headers: headers)
            : _client.post(uri,
                headers: {
                  ...headers,
                  'Content-Type': 'application/x-www-form-urlencoded'
                },
                body: body))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError('Fonte indisponível');
    final cookie = response.headers['set-cookie'];
    if (cookie != null) {
      for (final m
          in RegExp(r'(?:^|,\s*)([\w-]+)=([^;,]*)').allMatches(cookie)) {
        _cookies[m[1]!] = m[2]!;
      }
    }
    return utf8.decode(response.bodyBytes);
  }

  void close() => _client.close();
}

class CatalogResult {
  const CatalogResult(this.items, this.errors);
  final List<MediaItem> items;
  final List<String> errors;
}

class LiveCatalog {
  final _key = 'cineshow.catalog.v1';
  Future<List<MediaItem>> cached() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    try {
      final raw = stored ?? await rootBundle.loadString('assets/catalog.json');
      return (jsonDecode(raw) as List)
          .map((j) => MediaItem.fromJson(Map<String, dynamic>.from(j as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<CatalogResult> refresh({String? query}) async {
    final previous = await cached();
    if (apiBase.isNotEmpty) {
      final client = http.Client();
      try {
        final endpoint = query == null
            ? '/v1/catalog'
            : '/v1/search?q=${Uri.encodeQueryComponent(query)}';
        final r = await client
            .get(Uri.parse('$apiBase$endpoint'))
            .timeout(const Duration(seconds: 25));
        if (r.statusCode != 200) throw StateError('API indisponível');
        final j = jsonDecode(r.body) as Map;
        final items = (j['items'] as List)
            .map((v) => MediaItem.fromJson(Map<String, dynamic>.from(v as Map)))
            .toList();
        if (query == null) await _save(items);
        return CatalogResult(items, []);
      } finally {
        client.close();
      }
    }
    final errors = <String>[];
    final batches = await Future.wait(origins.entries.map((entry) async {
      final session = SourceSession(entry.value);
      try {
        if (entry.key == 'xonados') {
          final novels = await _xonados(session);
          return query == null
              ? novels
              : novels
                  .where((i) =>
                      i.title.toLowerCase().contains(query.toLowerCase()))
                  .toList();
        }
        if (query != null) return await _search(session, entry.key, query);
        return _cards(await session.get('/'), entry.key);
      } catch (_) {
        errors.add(entry.key);
        return query == null
            ? previous
                .where((i) => i.sources.any((s) => s.provider == entry.key))
                .toList()
            : <MediaItem>[];
      } finally {
        session.close();
      }
    }));
    final merged = _merge(batches.expand((i) => i).toList());
    final filtered = merged;
    if (query == null && merged.isNotEmpty) await _save(merged);
    return CatalogResult(filtered, errors);
  }

  Future<void> _save(List<MediaItem> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(items.map((i) => i.toJson()).toList()));
  }

  List<MediaItem> _cards(String html, String provider) {
    final result = <MediaItem>[];
    for (final m
        in RegExp(r'<article\b.*?</article>', dotAll: true).allMatches(html)) {
      final block = m[0]!;
      final a = attributes(block.split('>').first);
      final id = RegExp(r'(\d+)$').firstMatch(a['id'] ?? '')?[1];
      final title = RegExp(r'<h3[^>]*>\s*<a([^>]*)>(.*?)</a>', dotAll: true)
          .firstMatch(block);
      if (id == null || title == null) continue;
      final link = attributes(title[1]!)['href'] ?? '';
      if (!providerPage(provider, link) ||
          !(Uri.parse(link).path.startsWith('/filme/') ||
              Uri.parse(link).path.startsWith('/serie/'))) {
        continue;
      }
      final img = RegExp(r'<img\b[^>]*>').firstMatch(block);
      final ia = attributes(img?[0] ?? '');
      final date =
          RegExp(r'<span[^>]*>(.*?)</span>', dotAll: true).firstMatch(block);
      final years =
          RegExp(r'\b(?:19|20)\d{2}\b').allMatches(date?[1] ?? '').toList();
      final kind = link.contains('/serie/') ? 'series' : 'movie';
      result.add(MediaItem(
          id: '$provider:$id',
          title: plain(title[2]!),
          description: '',
          genre: '',
          year: years.isEmpty ? 0 : int.parse(years.last[0]!),
          durationMinutes: 0,
          posterUrl: ia['data-src'] ?? ia['src'],
          kind: kind,
          isSeries: kind == 'series',
          sources: [
            MediaSource(provider: provider, sourceId: id, pageUrl: link)
          ]));
    }
    if (result.isEmpty) throw StateError('Catálogo vazio');
    return result;
  }

  Future<List<MediaItem>> _search(
      SourceSession session, String provider, String query) async {
    final html = await session.get('/');
    final config = RegExp(r'var dtGonza=(\{.*?\});').firstMatch(html);
    if (config == null) throw StateError('Busca indisponível');
    final nonce = (jsonDecode(config[1]!) as Map)['nonce'];
    final response = jsonDecode(await session.get(
        '/wp-json/dooplay/search/?keyword=${Uri.encodeQueryComponent(query)}&nonce=$nonce'));
    if (response is! Map || response.containsKey('error')) {
      throw StateError('Busca indisponível');
    }
    return response.entries
        .where((e) =>
            RegExp(r'^\d+$').hasMatch(e.key.toString()) && e.value is Map)
        .map((e) {
      final j = e.value as Map;
      final link = j['url'] as String;
      final kind = link.contains('/serie/') ? 'series' : 'movie';
      return MediaItem(
          id: '$provider:${e.key}',
          title: plain(j['title'] as String),
          description: '',
          genre: '',
          year: int.tryParse('${(j['extra'] as Map?)?['date']}') ?? 0,
          durationMinutes: 0,
          posterUrl: j['img'] as String?,
          kind: kind,
          isSeries: kind == 'series',
          sources: [
            MediaSource(
                provider: provider, sourceId: e.key.toString(), pageUrl: link)
          ]);
    }).toList();
  }

  Future<List<MediaItem>> _xonados(SourceSession session) async {
    final root = await session.get('/');
    final script =
        RegExp(r'''<script[^>]+src=["']([^"']*WTyNK[^"']*)''').firstMatch(root);
    if (script == null) throw StateError('Catálogo indisponível');
    final js = await session.get(script[1]!.replaceAll('&amp;', '&'));
    final endpoint = RegExp(r"fetch\('([^']*ZXDSX[^']*)'").firstMatch(js);
    if (endpoint == null) throw StateError('Catálogo indisponível');
    final cards = await session.get(endpoint[1]!, body: '"nuZ", nuZ');
    final ids = RegExp(r'''data-wheel=["'](\d+)''')
        .allMatches(cards)
        .map((m) => m[1])
        .toSet();
    const names = {
      '1': ('Além do Tempo', ''),
      '2': ('Avenida Brasil', 'avenida-brasil-1'),
      '3': ('A Nobreza do Amor', 'a-nobreza-do-amor'),
      '4': ('Por Você', 'por-voce'),
      '5': ('Quem Ama Cuida', 'quem-ama-cuida'),
      '6': ('A Fazenda 18', 'a-fazenda-18')
    };
    final items = [
      for (final e in names.entries)
        if (ids.contains(e.key))
          MediaItem(
              id: 'xonados:${e.key}',
              title: e.value.$1,
              description: '',
              genre: '',
              year: 0,
              durationMinutes: 0,
              kind: e.key == '6' ? 'reality' : 'novela',
              sources: [
                MediaSource(
                    provider: 'xonados',
                    sourceId: e.key,
                    pageUrl: e.value.$2.isEmpty
                        ? 'https://www.xonados.com/'
                        : 'https://www.xonados.com/@novela/${e.value.$2}/')
              ])
    ];
    if (items.isEmpty) throw StateError('Catálogo vazio');
    return items;
  }

  List<MediaItem> _merge(List<MediaItem> items) {
    final groups = <String, MediaItem>{};
    for (final i in items) {
      final key = '${i.kind}:${i.title.toLowerCase().trim()}:${i.year}';
      final existing = groups[key];
      if (existing == null) {
        groups[key] = i;
      } else {
        final sources = [...existing.sources];
        for (final s in i.sources) {
          if (!sources.any(
              (v) => v.provider == s.provider && v.sourceId == s.sourceId)) {
            sources.add(s);
          }
        }
        groups[key] = MediaItem(
            id: existing.id,
            title: existing.title,
            description: existing.description,
            genre: existing.genre,
            year: existing.year,
            durationMinutes: existing.durationMinutes,
            posterUrl: existing.posterUrl ?? i.posterUrl,
            kind: existing.kind,
            isSeries: existing.isSeries,
            sources: sources);
      }
    }
    return groups.entries.map((e) {
      final i = e.value;
      return MediaItem(
          id: e.key,
          title: i.title,
          description: i.description,
          genre: i.genre,
          year: i.year,
          durationMinutes: i.durationMinutes,
          posterUrl: i.posterUrl,
          kind: i.kind,
          isSeries: i.isSeries,
          sources: i.sources);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> episodes(MediaSource source) async {
    if (apiBase.isNotEmpty) {
      final client = http.Client();
      try {
        final r = await client
            .get(Uri.parse(
                '$apiBase/v1/details?provider=${source.provider}&id=${source.sourceId}'))
            .timeout(const Duration(seconds: 30));
        if (r.statusCode != 200) throw StateError('Detalhes indisponíveis');
        return ((jsonDecode(r.body) as Map)['episodes'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } finally {
        client.close();
      }
    }
    if (!providerPage(source.provider, source.pageUrl)) {
      throw StateError('Fonte inválida');
    }
    final session = SourceSession(Uri.parse(source.pageUrl).origin);
    try {
      if (source.provider != 'xonados') {
        final page = await session.get(source.pageUrl);
        final seen = <String>{};
        final episodes = <Map<String, dynamic>>[];
        for (final m in RegExp(r'''href=["']([^"']+/episodio/[^"']+)["']''')
            .allMatches(page)) {
          final link = m[1]!.replaceAll('&amp;', '&');
          final n = RegExp(r'-(\d+)x(\d+)/?$').firstMatch(link);
          if (n != null &&
              seen.add(link) &&
              Uri.parse(link).origin == session.origin) {
            episodes.add({
              'id': link,
              'title': 'Temporada ${n[1]} · Episódio ${n[2]}',
              'page_url': link
            });
          }
        }
        return episodes;
      }
      await session.get('/');
      await session.get('/RTRT', body: source.sourceId);
      final page = await session.get('/');
      final script =
          RegExp(r'''<script[^>]+src=["']([^"']*YwZ[^"']*)''').firstMatch(page);
      if (script == null) throw StateError('Player indisponível');
      final js = await session.get(script[1]!.replaceAll('&amp;', '&'));
      final frame = RegExp(r"iframe.src\s*=\s*'([^']+)'").firstMatch(js);
      if (frame == null) throw StateError('Player indisponível');
      var markup = await session.get(frame[1]!.replaceAll('&amp;', '&'));
      final dates = RegExp(r'date=(\d{8})')
          .allMatches(markup)
          .map((m) => m[1]!)
          .toList()
        ..sort();
      if (dates.isNotEmpty) {
        final token = (await session.get('/G_sTw', body: '')).trim();
        if (RegExp(r'^[a-zA-Z0-9]{1,128}$').hasMatch(token)) {
          markup += await session.get('/Y_sTw?y=$token&zy=${source.sourceId}',
              body: 'vlum=${dates.first}');
        }
      }
      final seen = <String>{};
      final result = <Map<String, dynamic>>[];
      for (final m in RegExp(r'<iframe\b[^>]*>').allMatches(markup)) {
        final path = attributes(m[0]!)['src'];
        if (path == null) continue;
        final d = RegExp(r'date=(\d{8})(_\d+)?(?:&|$)').firstMatch(path);
        if (d == null) continue;
        final id = '${d[1]}${d[2] ?? ''}';
        if (seen.add(id)) {
          final date = d[1]!;
          result.add({
            'id': id,
            'title':
                '${date.substring(6)}/${date.substring(4, 6)}/${date.substring(0, 4)}${d[2] == null ? '' : ' · Variante ${d[2]!.substring(1)}'}',
            'page_url': '${session.origin}$path'
          });
        }
      }
      return result;
    } finally {
      session.close();
    }
  }
}
