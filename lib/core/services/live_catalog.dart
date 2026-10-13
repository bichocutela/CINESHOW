import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
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
  'tontons': {'https://tontonsfilmeurs.com', 'https://alfandega-filmes.com'},
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

String encodeCatalogJson(List<Map<String, dynamic>> data) => jsonEncode(data);

class FullCatalogBatch {
  const FullCatalogBatch(this.items, this.pages, this.complete, this.failed);
  final List<MediaItem> items;
  final int pages;
  final bool complete;
  final List<String> failed;
}

class LiveCatalog {
  LiveCatalog({SourceSession Function(String)? sessionFactory})
      : _sessionFactory = sessionFactory ?? SourceSession.new;
  final SourceSession Function(String) _sessionFactory;
  int _fullGeneration = 0;
  void cancelFullSync() {
    _fullGeneration++;
  }

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
        final combined = _merge([
          ...previous.where((item) =>
              query == null ||
              item.title.toLowerCase().contains(query.toLowerCase())),
          ...items
        ]);
        if (query == null) await _save(combined);
        return CatalogResult(combined, []);
      } finally {
        client.close();
      }
    }
    final errors = <String>[];
    final batches = await Future.wait(origins.entries.map((entry) async {
      final session = _sessionFactory(entry.value);
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
    final merged = _merge([
      ...previous.where((item) =>
          query == null ||
          item.title.toLowerCase().contains(query.toLowerCase())),
      ...batches.expand((i) => i)
    ]);
    final filtered = merged;
    if (query == null && merged.isNotEmpty) await _save(merged);
    return CatalogResult(filtered, errors);
  }

  Future<void> _save(List<MediaItem> items) async {
    final p = await SharedPreferences.getInstance();
    final encoded = await compute(
        encodeCatalogJson, items.map((item) => item.toJson()).toList());
    await p.setString(_key, encoded);
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
    const names = {
      '1': ('Além do Tempo', ''),
      '2': ('Avenida Brasil', 'avenida-brasil-1'),
      '3': ('A Nobreza do Amor', 'a-nobreza-do-amor'),
      '4': ('Por Você', 'por-voce'),
      '5': ('Quem Ama Cuida', 'quem-ama-cuida'),
      '6': ('A Fazenda 18', 'a-fazenda-18')
    };
    final tags = RegExp(r'''<[^>]+\bdata-wheel=["'](\d+)["'][^>]*>''')
        .allMatches(cards)
        .toList();
    final items = <MediaItem>[];
    final seen = <String>{};
    for (var index = 0; index < tags.length; index++) {
      final tag = tags[index];
      final id = tag[1]!;
      if (!seen.add(id)) continue;
      final a = attributes(tag[0]!);
      final block = cards.substring(tag.start,
          index + 1 < tags.length ? tags[index + 1].start : cards.length);
      final imageTag = RegExp(r'<img\b[^>]*>').firstMatch(block);
      final image = attributes(imageTag?[0] ?? '');
      final heading = RegExp(r'<h[1-6][^>]*>(.*?)</h[1-6]>', dotAll: true)
          .firstMatch(block)?[1];
      String? published;
      for (final candidate in [
        a['data-title'],
        a['title'],
        a['alt'],
        heading,
        image['alt']
      ]) {
        if (candidate != null &&
            plain(candidate).isNotEmpty &&
            !RegExp(r'^(?:clique|assistir|capa|imagem)$', caseSensitive: false)
                .hasMatch(plain(candidate))) {
          published = plain(candidate);
          break;
        }
      }
      final known = names[id];
      final title = published ?? known?.$1 ?? 'Programa $id';
      final poster = image['data-src'] ?? image['src'];
      final path = known?.$2;
      items.add(MediaItem(
        id: 'xonados:$id',
        title: title,
        description: '',
        genre: '',
        year: 0,
        durationMinutes: 0,
        posterUrl: poster != null &&
                Uri.parse('https://www.xonados.com').resolve(poster).scheme ==
                    'https'
            ? Uri.parse('https://www.xonados.com').resolve(poster).toString()
            : null,
        kind: id == '6'
            ? 'reality'
            : known == null
                ? 'program'
                : 'novela',
        sources: [
          MediaSource(
              provider: 'xonados',
              sourceId: id,
              pageUrl: path == null || path.isEmpty
                  ? 'https://www.xonados.com/'
                  : 'https://www.xonados.com/@novela/$path/')
        ],
      ));
    }
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

  Stream<FullCatalogBatch> syncFull() async* {
    final generation = ++_fullGeneration;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('cineshow.full-catalog.cursor.v1');
    Map<String, dynamic> progress;
    try {
      progress = jsonDecode(stored ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      progress = {};
    }
    final completedAt = progress['completed_at'] as int? ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - completedAt >
            const Duration(days: 1).inMilliseconds &&
        completedAt > 0) {
      progress = {};
    }
    final cursors = <String, String?>{};
    for (final provider in ['rtfilmes', 'tontons']) {
      for (final type in ['filme', 'serie']) {
        final key = '$provider:$type';
        cursors[key] = progress.containsKey(key)
            ? progress[key] as String?
            : '${origins[provider]}/$type/';
      }
    }
    var all = await cached();
    var pages = 0;
    final failed = <String>{};
    final visited = <String>{};
    Future<void> checkpoint() async {
      await _save(all);
      await prefs.setString(
          'cineshow.full-catalog.cursor.v1',
          jsonEncode({
            ...cursors,
            if (cursors.values.every((url) => url == null))
              'completed_at': DateTime.now().millisecondsSinceEpoch,
          }));
    }

    while (true) {
      final pending = cursors.entries
          .where((entry) => entry.value != null && !failed.contains(entry.key))
          .take(2)
          .toList();
      if (pending.isEmpty) break;
      final responses = await Future.wait(pending.map((entry) async {
        final provider = entry.key.split(':').first;
        final url = entry.value!;
        if (!providerPage(provider, url) || !visited.add('${entry.key}:$url')) {
          return (entry.key, <MediaItem>[], null, true);
        }
        final session = _sessionFactory(Uri.parse(url).origin);
        try {
          final html = await session.get(url);
          final expected = int.tryParse(RegExp(r'/page/(\d+)/?')
                      .firstMatch(Uri.parse(url).path)?[1] ??
                  '') ??
              1;
          final actual = int.tryParse(
              RegExp(r'''<span[^>]*class=["'][^"']*\bcurrent\b[^"']*["'][^>]*>\s*(\d+)''')
                      .firstMatch(html)?[1] ??
                  '');
          if (actual != null && actual != expected) {
            throw StateError('Página redirecionada');
          }
          final items = _cards(html, provider);
          return (
            entry.key,
            items,
            nextArchivePage(html, url, provider),
            false
          );
        } catch (_) {
          return (entry.key, <MediaItem>[], url, true);
        } finally {
          session.close();
        }
      }));
      if (generation != _fullGeneration) return;
      for (final response in responses) {
        if (response.$4) {
          failed.add(response.$1);
          continue;
        }
        all = _merge([...all, ...response.$2]);
        cursors.remove(response.$1);
        cursors[response.$1] = response.$3;
        pages++;
      }
      if (pages % 10 == 0) await checkpoint();
      yield FullCatalogBatch(all, pages, false, failed.toList());
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (generation != _fullGeneration) return;
    await checkpoint();
    yield FullCatalogBatch(all, pages,
        cursors.values.every((url) => url == null), failed.toList());
  }

  static String? nextArchivePage(
      String html, String currentUrl, String provider) {
    final current = Uri.parse(currentUrl);
    final archive = RegExp(r'^/(filme|serie)/').firstMatch(current.path)?[1];
    if (archive == null) return null;
    final number = int.tryParse(
            RegExp(r'/page/(\d+)/?').firstMatch(current.path)?[1] ?? '') ??
        1;
    String? best;
    var bestNumber = 0;
    for (final tag in RegExp(r'<a\b[^>]*>').allMatches(html)) {
      final href = attributes(tag[0]!)['href'];
      if (href == null) continue;
      final url = current.resolve(href).toString();
      if (!providerPage(provider, url)) continue;
      final match =
          RegExp('^/$archive/page/(\\d+)/?\$').firstMatch(Uri.parse(url).path);
      final next = int.tryParse(match?[1] ?? '');
      if (next != null &&
          next > number &&
          (best == null || next < bestNumber)) {
        best = url;
        bestNumber = next;
      }
    }
    return best;
  }

  Future<List<Map<String, dynamic>>> episodes(MediaSource source,
      {void Function(List<Map<String, dynamic>>)? onBatch}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'cineshow.episodes.v2.${source.provider}.${source.sourceId}';
    final known = <String, Map<String, dynamic>>{};
    try {
      final cached = jsonDecode(prefs.getString(key) ?? '[]') as List;
      for (final raw in cached) {
        final item = Map<String, dynamic>.from(raw as Map);
        known[item['id'].toString()] = item;
      }
      if (known.isNotEmpty) onBatch?.call(known.values.toList());
    } catch (_) {}
    var batches = 0;
    Future<void> writes = Future.value();
    void receive(List<Map<String, dynamic>> partial) {
      for (final item in partial) {
        known[item['id'].toString()] = item;
      }
      onBatch?.call(known.values.toList());
      if (++batches % 5 == 0) {
        final data = jsonEncode(known.values.toList());
        writes = writes.then((_) => prefs.setString(key, data)).then((_) {});
      }
    }

    try {
      final result = await _allEpisodes(source, onBatch: receive);
      await writes;
      await prefs.setString(key, jsonEncode(result));
      return result;
    } catch (_) {
      await writes;
      if (known.isNotEmpty) {
        await prefs.setString(key, jsonEncode(known.values.toList()));
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _allEpisodes(MediaSource source,
      {void Function(List<Map<String, dynamic>>)? onBatch}) async {
    if (!providerPage(source.provider, source.pageUrl)) {
      throw StateError('Fonte inválida');
    }
    final session = _sessionFactory(Uri.parse(source.pageUrl).origin);
    try {
      if (source.provider != 'xonados') {
        final pending = <String>[source.pageUrl];
        final visited = <String>{};
        final result = <String, Map<String, dynamic>>{};
        while (pending.isNotEmpty) {
          final url = pending.removeAt(0);
          if (!visited.add(url)) continue;
          final pageSession = _sessionFactory(Uri.parse(url).origin);
          late String page;
          try {
            page = await pageSession.get(url);
          } finally {
            pageSession.close();
          }
          final titleSection = episodeScope(page);
          final blocks = RegExp(
                  r'''<ul\b[^>]*class=["'][^"']*\bepisodios\b[^"']*["'][^>]*>(.*?)</ul>''',
                  dotAll: true)
              .allMatches(titleSection)
              .map((m) => m[1]!)
              .toList();
          final scope = blocks.isEmpty ? titleSection : blocks.join('\n');
          for (final match in RegExp(
                  r'''<a\b[^>]*href=["']([^"']*/episodio/[^"']+)["'][^>]*>(.*?)</a>''',
                  dotAll: true)
              .allMatches(scope)) {
            final link = Uri.parse(url)
                .resolve(match[1]!.replaceAll('&amp;', '&'))
                .toString();
            if (!providerPage(source.provider, link)) continue;
            final number = RegExp(r'-(\d+)x(\d+)/?$').firstMatch(link);
            final label = plain(match[2]!);
            result[link] = {
              'id': link,
              'title': number == null
                  ? label.isEmpty
                      ? 'Episódio'
                      : label
                  : 'Temporada ${number[1]} · Episódio ${number[2]}',
              'page_url': link
            };
          }
          onBatch?.call(result.values.toList());
          for (final tag in RegExp(r'<a\b[^>]*>').allMatches(page)) {
            final href = attributes(tag[0]!)['href'];
            if (href == null) continue;
            final link = Uri.parse(url).resolve(href).toString();
            if (!providerPage(source.provider, link) ||
                visited.contains(link)) {
              continue;
            }
            final path = Uri.parse(link).path;
            final isSeason = path.startsWith('/temporada/');
            final rootPath = Uri.parse(url)
                .path
                .replaceFirst(RegExp(r'/page/\d+/?$'), '')
                .replaceFirst(RegExp(r'/$'), '');
            final isNextPage =
                RegExp('^${RegExp.escape(rootPath)}/page/\\d+/?\$')
                    .hasMatch(path);
            if ((isSeason && titleSection.contains(href) || isNextPage) &&
                !pending.contains(link)) {
              pending.add(link);
            }
          }
        }
        return result.values.toList()
          ..sort((a, b) {
            final left =
                RegExp(r'-(\d+)x(\d+)/?$').firstMatch(a['page_url'] as String);
            final right =
                RegExp(r'-(\d+)x(\d+)/?$').firstMatch(b['page_url'] as String);
            if (left == null || right == null) {
              return a['title'].toString().compareTo(b['title'].toString());
            }
            final season = int.parse(left[1]!).compareTo(int.parse(right[1]!));
            return season != 0
                ? season
                : int.parse(left[2]!).compareTo(int.parse(right[2]!));
          });
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
      final result = <String, Map<String, dynamic>>{};
      String? oldest;
      while (true) {
        for (final chapter in xonadosChapters(markup, session.origin)) {
          result[chapter['id'] as String] = chapter;
        }
        onBatch?.call(result.values.toList());
        final dates = result.keys.map((id) => id.substring(0, 8)).toList()
          ..sort();
        if (dates.isEmpty || dates.first == oldest) break;
        oldest = dates.first;
        final token = (await session.get('/G_sTw', body: '')).trim();
        if (!RegExp(r'^[a-zA-Z0-9]{1,128}$').hasMatch(token)) {
          throw StateError('Histórico indisponível');
        }
        markup = await session.get('/Y_sTw?y=$token&zy=${source.sourceId}',
            body: 'vlum=$oldest');
        if (xonadosChapters(markup, session.origin).isEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      return result.values.toList()
        ..sort((a, b) => b['id'].toString().compareTo(a['id'].toString()));
    } finally {
      session.close();
    }
  }

  static String episodeScope(String page) {
    final opening =
        RegExp(r'''<div\b[^>]*id=["'](?:seasons|episodes)["'][^>]*>''')
            .firstMatch(page);
    if (opening == null) return page;
    var depth = 1;
    for (final tag
        in RegExp(r'<(/?)div\b[^>]*>').allMatches(page, opening.end)) {
      depth += tag[1] == '/' ? -1 : 1;
      if (depth == 0) return page.substring(opening.end, tag.start);
    }
    return page.substring(opening.end);
  }

  static List<Map<String, dynamic>> xonadosChapters(
      String markup, String origin) {
    final result = <String, Map<String, dynamic>>{};
    for (final frame in RegExp(r'<iframe\b[^>]*>').allMatches(markup)) {
      final path = attributes(frame[0]!)['src'];
      if (path == null) continue;
      final date = RegExp(r'date=(\d{8})(_\d+)?(?:&|$)').firstMatch(path);
      if (date == null) continue;
      final value = date[1]!, variant = date[2] ?? '';
      final id = '$value$variant';
      result[id] = {
        'id': id,
        'title':
            '${value.substring(6)}/${value.substring(4, 6)}/${value.substring(0, 4)}${variant.isEmpty ? '' : ' · Variante ${variant.substring(1)}'}',
        'page_url': Uri.parse(origin).resolve(path).toString()
      };
    }
    return result.values.toList();
  }
}
