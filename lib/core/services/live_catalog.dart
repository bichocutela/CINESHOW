import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import 'poster_sources.dart';
import 'source_origins.dart';
import 'source_html.dart';
import 'novelasflix.dart';
import 'catalog_categories.dart';
import 'audio_metadata.dart';
import 'source_session.dart';
import 'anime_catalog.dart';
import 'mega_catalog.dart';
import 'superflix_catalog.dart';
import 'tv_aberta.dart';
import 'package:flutter/foundation.dart';
export 'source_session.dart' show SourceSession;
export 'source_html.dart' show plain, attributes;
export 'source_origins.dart' show origins;

const apiBase = String.fromEnvironment('CINESHOW_API_URL');

class CatalogResult {
  const CatalogResult(this.items, this.errors);
  final List<MediaItem> items;
  final List<String> errors;
}

class CatalogPage {
  const CatalogPage(this.items, this.hasMore, this.errors);
  final List<MediaItem> items;
  final bool hasMore;
  final List<String> errors;
}

class _CatalogFeed {
  final items = <MediaItem>[];
  final pages = <String, int>{};
  final ended = <String>{};
}

class LiveCatalog {
  LiveCatalog({SourceSession Function(String)? sessionFactory})
      : sessionFactory = sessionFactory ?? SourceSession.new;
  final SourceSession Function(String) sessionFactory;
  final feeds = <String, _CatalogFeed>{};
  final amyThemedIds = <String>{};
  final _key = 'cineshow.catalog.v1';
  final categoryCache = <String, CatalogResult>{};
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
        var items = (j['items'] as List)
            .map((v) => MediaItem.fromJson(Map<String, dynamic>.from(v as Map)))
            .toList();
        try {
          items = _merge([...items, ...await _novelasflix(query: query)]);
        } catch (_) {
          // Keep the backend catalog when this additional source is unavailable.
        }
        try {
          items = _merge([...items, ...await _amyflix(query: query)]);
        } catch (_) {
          // Keep available sources if Amyflix is temporarily unavailable.
        }
        for (final extra in [_mega, _superflix, _tvAberta]) {
          try {
            items = _merge([...items, ...await extra(query: query)]);
          } catch (_) {}
        }
        if (query == null) await _save(items);
        return CatalogResult(items, []);
      } finally {
        client.close();
      }
    }
    final errors = <String>[];
    final batches = await Future.wait(origins.entries
        .where((e) => e.key != 'animesonlinecc')
        .map((entry) async {
      final session = sessionFactory(entry.value);
      try {
        if (entry.key == 'tvaberta') return await _tvAberta(query: query);
        if (entry.key == 'megafilmes') return await _mega(query: query);
        if (entry.key == 'superflix') return await _superflix(query: query);
        if (entry.key == 'amyflix' && query == null) {
          return await _amyflix();
        }
        if (entry.key == 'novelasflix') {
          return await _novelasflix(query: query);
        }
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

  Future<List<MediaItem>> _tvAberta({String? query}) =>
      TvAbertaService().novelas(query: query);

  Future<List<MediaItem>> _mega({String? query}) async {
    final session = sessionFactory(megaOrigin);
    try {
      final html = await session.get(
          query == null ? '/' : '/search?q=${Uri.encodeQueryComponent(query)}');
      return parseMegaCards(html).where((v) => v.kind != 'anime').toList();
    } finally {
      session.close();
    }
  }

  Future<List<MediaItem>> _superflix({String? query}) async {
    final batches = await Future.wait([
      SuperflixService().titles(kind: 'movie', query: query ?? ''),
      SuperflixService().titles(kind: 'series', query: query ?? ''),
      SuperflixService()
          .titles(kind: 'series', dorama: true, query: query ?? '')
    ]);
    return batches
        .expand((v) => v.items)
        .where((v) => v.kind != 'anime')
        .toList();
  }

  Future<List<MediaItem>> _amyflix({String? query}) async {
    final session = sessionFactory(origins['amyflix']!);
    final items = <MediaItem>[];
    try {
      if (query != null) return await _search(session, 'amyflix', query);
      items.addAll(_cards(await session.get('/'), 'amyflix'));
      final collections = await Future.wait([
        '/genero/filmes-saficos-atualizados/',
        '/genero/em-lancamento/',
        '/genero/completo/'
      ].map((path) async {
        try {
          return _cards(await session.get(path), 'amyflix', thematic: true);
        } catch (_) {
          return <MediaItem>[];
        }
      }));
      for (final batch in collections) {
        amyThemedIds
            .addAll(batch.expand((i) => i.sources.map((s) => s.sourceId)));
        items.addAll(batch);
      }
      return items;
    } finally {
      session.close();
    }
  }

  Future<List<MediaItem>> _novelasflix({String? query}) async {
    Future<List<MediaItem>> search(String text) async {
      final session = sessionFactory(novelasflixOrigin);
      try {
        return parseNovelasflixSearch(await session
            .get('/api/search?search=${Uri.encodeQueryComponent(text)}'));
      } finally {
        session.close();
      }
    }

    if (query != null) return search(query);
    final session = sessionFactory(novelasflixOrigin);
    final items = <MediaItem>[];
    try {
      items.addAll(parseNovelasflixCards(await session.get('/')));
    } finally {
      session.close();
    }
    final related = await Future.wait([
      'Além do Tempo',
      'Avenida Brasil',
      'A Nobreza do Amor',
      'Por Você',
      'Quem Ama Cuida',
      'A Fazenda 18'
    ].map((title) async {
      try {
        return await search(title);
      } catch (_) {
        return <MediaItem>[];
      }
    }));
    items.addAll(related.expand((batch) => batch));
    return items;
  }

  Future<CatalogResult> category(CatalogCategory category,
      {String? kind, bool force = false}) async {
    final key = '${kind ?? 'all'}:${category.slug}';
    if (!force && categoryCache.containsKey(key)) return categoryCache[key]!;
    final page = await more(kind: kind, category: category, reset: force);
    final result = CatalogResult(page.items, page.errors);
    if (page.errors.isEmpty) categoryCache[key] = result;
    return result;
  }

  List<MediaItem> mergeItems(List<MediaItem> items) => _merge(items);

  Future<CatalogPage> more(
      {String? kind, CatalogCategory? category, bool reset = false}) async {
    final slug = category?.slug;
    if (slug != null && !RegExp(r'^[a-z0-9-]+$').hasMatch(slug)) {
      throw StateError('Categoria inválida.');
    }
    final key = '${kind ?? 'all'}:${slug ?? 'all'}';
    if (reset) feeds.remove(key);
    final feed = feeds.putIfAbsent(key, _CatalogFeed.new);
    final paths = <String, String>{};
    for (final provider in [
      'rtfilmes',
      'tontons',
      'amyflix',
      'megafilmes',
      'superflix'
    ]) {
      if (slug == 'amy-gl') {
        if (provider == 'amyflix') {
          if (kind != 'series') {
            paths['amyflix:gl-movie'] = '/genero/filmes-saficos-atualizados/';
          }
          if (kind != 'movie') {
            paths['amyflix:gl-current'] = '/genero/em-lancamento/';
            paths['amyflix:gl-complete'] = '/genero/completo/';
          }
        }
      } else if (slug != null) {
        if (provider == 'amyflix' || provider == 'superflix') continue;
        if (provider == 'megafilmes') {
          paths['$provider:category'] =
              '/categoria/${slug == 'thriller' ? 'suspense' : slug}';
        } else {
          paths['$provider:category'] = '/melhores/$slug/';
        }
      } else {
        if (kind != 'series') {
          paths['$provider:movie'] =
              provider == 'megafilmes' || provider == 'superflix'
                  ? '/filmes'
                  : '/filme/';
        }
        if (kind != 'movie') {
          paths['$provider:series'] =
              provider == 'megafilmes' || provider == 'superflix'
                  ? '/series'
                  : '/serie/';
        }
        if (kind != 'movie' && provider == 'superflix') {
          paths['superflix:dorama'] = '/doramas';
        }
      }
    }
    final errors = <String>[];
    final batches = await Future.wait(paths.entries.map((entry) async {
      if (feed.ended.contains(entry.key)) return <MediaItem>[];
      final provider = entry.key.split(':').first;
      final page = feed.pages[entry.key] ?? 1;
      final pagination = page == 1 ? '' : 'page/$page/';
      final type = kind == 'series'
          ? 'tvshows'
          : kind == 'movie'
              ? 'movies'
              : null;
      final query = slug != null && type != null ? '?post_type=$type' : '';
      final session = sessionFactory(origins[provider]!);
      try {
        final special = provider == 'megafilmes' || provider == 'superflix';
        final path = special
            ? '${entry.value}?page=$page&sort=recent'
            : '${entry.value}$pagination$query';
        final html = await session.get(path);
        final parsed = provider == 'megafilmes'
            ? parseMegaCards(html)
            : provider == 'superflix'
                ? parseSuperflixCards(html,
                    kind: kind, dorama: entry.key.endsWith(':dorama'))
                : _cards(html, provider, thematic: slug == 'amy-gl');
        final items = parsed
            .where((i) => i.kind != 'anime' && (kind == null || i.kind == kind))
            .toList();
        feed.pages[entry.key] = page + 1;
        final next = special
            ? hasCatalogNextPage(html, page)
            : html.contains('/page/${page + 1}/');
        if (!next) feed.ended.add(entry.key);
        return items;
      } catch (_) {
        errors.add(provider);
        return <MediaItem>[];
      } finally {
        session.close();
      }
    }));
    feed.items.addAll(batches.expand((v) => v));
    final merged = _merge(feed.items);
    feed.items
      ..clear()
      ..addAll(merged);
    return CatalogPage(
        merged, feed.ended.length < paths.length, errors.toSet().toList());
  }

  Future<void> _save(List<MediaItem> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(items.map((i) => i.toJson()).toList()));
  }

  List<MediaItem> _cards(String html, String provider,
      {bool thematic = false}) {
    final result = <MediaItem>[];
    for (final m
        in RegExp(r'<article\b.*?</article>', dotAll: true).allMatches(html)) {
      final block = m[0]!;
      final a = attributes(block.split('>').first);
      final id = RegExp(r'(\d+)$').firstMatch(a['id'] ?? '')?[1];
      final title = RegExp(r'<h3[^>]*>\s*<a([^>]*)>(.*?)</a>', dotAll: true)
          .firstMatch(block);
      final heading =
          RegExp(r'<h3[^>]*>(.*?)</h3>', dotAll: true).firstMatch(block)?[1];
      if (id == null || heading == null) continue;
      final firstLink = RegExp(r'<a\b[^>]*>').firstMatch(block)?[0] ?? '';
      final link = attributes(title?[1] ?? firstLink)['href'] ?? '';
      if (!link.startsWith('${origins[provider]}/filme/') &&
          !link.startsWith('${origins[provider]}/serie/')) {
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
          title: cleanAudioTitle(plain(title?[2] ?? heading)),
          description: '',
          genre: '',
          audio: audioLabel(
              '${catalogAudio(block)} ${provider == 'amyflix' ? audioLabel(plain(heading)) : ''}'),
          tags: provider == 'amyflix' && (thematic || amyThemedIds.contains(id))
              ? const ['LGBT+', 'GL / Sáfico']
              : const [],
          year: years.isEmpty ? 0 : int.parse(years.last[0]!),
          durationMinutes: 0,
          posterUrl: catalogPoster(ia, origins[provider]!),
          kind: kind,
          isSeries: kind == 'series',
          sources: [
            MediaSource(
                provider: provider,
                sourceId: id,
                pageUrl: link,
                posterUrl: catalogPoster(ia, origins[provider]!))
          ]));
    }
    if (result.isEmpty) throw StateError('Catálogo vazio');
    return result;
  }

  Future<List<MediaItem>> _search(
      SourceSession session, String provider, String query) async {
    final html = await session.get('/');
    final config = RegExp(r'var\s+dtGonza\s*=\s*(\{.*?\});').firstMatch(html);
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
          title: cleanAudioTitle(plain(j['title'] as String)),
          audio: provider == 'amyflix'
              ? audioLabel(plain(j['title'] as String))
              : '',
          tags: provider == 'amyflix' && amyThemedIds.contains(e.key.toString())
              ? const ['LGBT+', 'GL / Sáfico']
              : const [],
          description: '',
          genre: '',
          year: int.tryParse('${(j['extra'] as Map?)?['date']}') ?? 0,
          durationMinutes: 0,
          posterUrl: j['img'] as String?,
          kind: kind,
          isSeries: kind == 'series',
          sources: [
            MediaSource(
                provider: provider,
                sourceId: e.key.toString(),
                pageUrl: link,
                posterUrl: j['img'] as String?)
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
            description: existing.description.isNotEmpty
                ? existing.description
                : i.description,
            genre: existing.genre,
            audio: audioLabel('${existing.audio} ${i.audio}'),
            tags: {...existing.tags, ...i.tags}.toList(),
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
          audio: i.audio,
          tags: i.tags,
          year: i.year,
          durationMinutes: i.durationMinutes,
          posterUrl: i.posterUrl,
          kind: i.kind,
          isSeries: i.isSeries,
          sources: i.sources);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> episodes(MediaSource source) async {
    if (source.provider == 'tvaberta')
      {
return TvAbertaService().episodes(source.sourceId);
}
    if (source.provider == 'superflix') return [];
    if (source.provider == 'animesonlinecc' ||
        source.provider == 'megafilmes') {
      final session = sessionFactory(origins[source.provider]!);
      try {
        final html = await session.get(source.pageUrl);
        return source.provider == 'animesonlinecc'
            ? await compute(parseAnimeEpisodes, html)
            : parseMegaEpisodes(html);
      } finally {
        session.close();
      }
    }
    if (source.provider == 'novelasflix') {
      final session = sessionFactory(novelasflixOrigin);
      try {
        return parseNovelasflixEpisodes(await session.get(source.pageUrl));
      } finally {
        session.close();
      }
    }
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
    final session = sessionFactory(origins[source.provider]!);
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
