import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import 'source_html.dart';
import 'source_session.dart';
import 'superflix_catalog.dart';
import 'audio_metadata.dart';

const animeOrigin = 'https://animesonlinecc.to';

String animeTitle(String value) => plain(value)
    .replaceFirst(
        RegExp(r'\s+Todos os Epis[oó]dios Online.*$', caseSensitive: false), '')
    .trim();

List<MediaItem> parseAnimeCards(String html, {bool episodes = false}) {
  final found = <String, MediaItem>{};
  for (final block
      in RegExp(r'<article\b.*?</article>', dotAll: true).allMatches(html)) {
    final text = block[0]!;
    final link = RegExp(r'<a\b[^>]*>').firstMatch(text);
    final attrs = attributes(link?[0] ?? '');
    final raw = attrs['href'];
    if (raw == null) continue;
    final uri = Uri.parse('$animeOrigin/').resolve(raw);
    final prefix = episodes ? '/episodio/' : '/anime/';
    if (uri.origin != animeOrigin ||
        !uri.path.startsWith(prefix) ||
        uri.path == prefix) {
      continue;
    }
    final img = attributes(RegExp(r'<img\b[^>]*>').firstMatch(text)?[0] ?? '');
    final picture = img['data-src'] ?? img['src'];
    final heading =
        RegExp(r'<h3[^>]*>(.*?)</h3>', dotAll: true).firstMatch(text)?[1];
    final title = animeTitle(heading ?? img['alt'] ?? '');
    if (title.isEmpty) continue;
    final source = MediaSource(
        provider: 'animesonlinecc',
        sourceId: uri.pathSegments.where((v) => v.isNotEmpty).last,
        pageUrl: uri.toString(),
        audio: audioLabel('${catalogAudio(text)} $title'),
        quality: catalogQuality(text),
        posterUrl: picture == null
            ? null
            : Uri.parse('$animeOrigin/').resolve(picture).toString());
    final audio = catalogAudio(text);
    found[uri.toString()] = MediaItem(
        id: 'anime:$title:0',
        title: title,
        description: '',
        genre: 'Anime',
        year: 0,
        durationMinutes: 0,
        kind: 'anime',
        isSeries: true,
        audio: audio.isNotEmpty ? audio : audioLabel(title),
        posterUrl: source.posterUrl,
        sources: [source]);
  }
  return found.values.toList();
}

List<Map<String, dynamic>> parseAnimeEpisodes(String html) {
  final found = <String, Map<String, dynamic>>{};
  for (final list in RegExp(
          r'''<ul[^>]+class=["'][^"']*\bepisodios\b[^"']*["'][^>]*>(.*?)</ul>''',
          dotAll: true)
      .allMatches(html)) {
    for (final row
        in RegExp(r'<li\b.*?</li>', dotAll: true).allMatches(list[1]!)) {
      final title = RegExp(
              r'''<div[^>]+class=["']episodiotitle["'][^>]*>\s*<a([^>]*)>(.*?)</a>''',
              dotAll: true)
          .firstMatch(row[0]!);
      if (title == null) continue;
      final raw = attributes(title[1]!)['href'];
      if (raw == null) continue;
      final uri = Uri.parse('$animeOrigin/').resolve(raw);
      if (uri.origin != animeOrigin || !uri.path.startsWith('/episodio/')) {
        continue;
      }
      final number = RegExp(r'Ep\s*-\s*(\d+)', caseSensitive: false)
          .firstMatch(plain(row[0]!));
      found[uri.toString()] = {
        'id': uri.toString(),
        'page_url': uri.toString(),
        'title': plain(title[2]!),
        'season': 1,
        if (number != null) 'number': int.parse(number[1]!)
      };
    }
  }
  return found.values.toList()
    ..sort((a, b) {
      final x = a['number'] as int? ?? 0, y = b['number'] as int? ?? 0;
      return x != y
          ? x.compareTo(y)
          : (a['title'] as String).compareTo(b['title'] as String);
    });
}

List<T> episodeBlock<T>(List<T> items, int page) {
  if (page < 0) return [];
  return items.skip(page * 100).take(100).toList();
}

String animeSection(String html, String heading) {
  for (final h
      in RegExp(r'<h2\b[^>]*>(.*?)</h2>', dotAll: true).allMatches(html)) {
    if (plain(h[1]!).toLowerCase() != heading.toLowerCase()) continue;
    final end = html.indexOf('<h2', h.end);
    return html.substring(h.end, end < 0 ? html.length : end);
  }
  return '';
}

class AnimeCatalogService {
  AnimeCatalogService({this.provider = 'animesonlinecc'});
  final String provider;
  Future<Map<String, List<MediaItem>>> cached() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final data = jsonDecode(
          prefs.getString('cineshow.anime.home.v1.$provider') ?? '{}') as Map;
      List<MediaItem> parse(String key) => ((data[key] as List?) ?? [])
          .map((v) => MediaItem.fromJson(Map<String, dynamic>.from(v as Map)))
          .toList();
      return {'titles': parse('titles'), 'episodes': parse('episodes')};
    } catch (_) {
      return {'titles': [], 'episodes': []};
    }
  }

  Future<Map<String, List<MediaItem>>> refresh() async {
    if (provider == 'superflix') {
      final result = await SuperflixService().titles(kind: 'anime');
      final data = <String, List<MediaItem>>{
        'titles': result.items,
        'episodes': []
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'cineshow.anime.home.v1.$provider',
          jsonEncode(data
              .map((k, v) => MapEntry(k, v.map((i) => i.toJson()).toList()))));
      await _record(data);
      return data;
    }
    final session = SourceSession(animeOrigin);
    try {
      final html = await session.get('/');
      final data = {
        'titles': parseAnimeCards(animeSection(html, 'Animes Recentes')),
        'episodes': parseAnimeCards(animeSection(html, 'Últimos Episódios'),
            episodes: true)
      };
      if (data.values.every((v) => v.isEmpty)) {
        throw StateError('Catálogo anime indisponível.');
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'cineshow.anime.home.v1.$provider',
          jsonEncode(data
              .map((k, v) => MapEntry(k, v.map((i) => i.toJson()).toList()))));
      await _record(data);
      return data;
    } finally {
      session.close();
    }
  }

  Future<({List<MediaItem> items, bool more})> list(
      {String? letter, String query = '', int page = 1}) async {
    if (letter != null && !RegExp(r'^[A-Z]$').hasMatch(letter)) {
      throw StateError('Letra inválida.');
    }
    if (page < 1) throw StateError('Página inválida.');
    if (provider == 'superflix') {
      final result = await SuperflixService().titles(
          kind: 'anime',
          query: query.isNotEmpty ? query : letter ?? '',
          page: page);
      return (
        items: result.items
            .where((v) =>
                letter == null || v.title.toUpperCase().startsWith(letter))
            .toList(),
        more: result.more
      );
    }
    final session = SourceSession(animeOrigin);
    try {
      final pagination = page == 1 ? '' : 'page/$page/';
      final path = query.trim().isNotEmpty
          ? '/?s=${Uri.encodeQueryComponent(query.trim())}&post_type=tvshows&paged=$page'
          : letter == null
              ? '/anime/$pagination'
              : '/genero/letra-${letter.toLowerCase()}/$pagination';
      final html = await session.get(path);
      final items = parseAnimeCards(html);
      items.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      return (
        items: items,
        more: html.contains('/page/${page + 1}/') ||
            html.contains('paged=${page + 1}')
      );
    } finally {
      session.close();
    }
  }

  Future<({MediaItem item, String? episode})> contextFor(
      MediaItem preview) async {
    final source = preview.sources.first;
    if (source.provider != 'animesonlinecc') {
      return (item: preview, episode: null);
    }
    if (!Uri.parse(source.pageUrl).path.startsWith('/episodio/')) {
      return (item: preview, episode: null);
    }
    final session = SourceSession(animeOrigin);
    try {
      final html = await session.get(source.pageUrl);
      final link = RegExp(
              r'''<a[^>]+href=["']([^"']+/anime/[^"']+)["'][^>]*>\s*<i[^>]*class=["']icon-bars''')
          .firstMatch(html)?[1];
      if (link == null) return (item: preview, episode: source.pageUrl);
      final uri = Uri.parse(link);
      if (uri.origin != animeOrigin) throw StateError('Origem inválida.');
      final page = await session.get(link);
      final title =
          RegExp(r'<h1[^>]*>(.*?)</h1>', dotAll: true).firstMatch(page)?[1] ??
              preview.title;
      String? poster;
      for (final tag in RegExp(r'<meta\b[^>]*>').allMatches(page)) {
        final a = attributes(tag[0]!);
        if (a['property'] == 'og:image') poster = a['content'];
      }
      final parent = MediaItem(
          id: 'anime:${animeTitle(title).toLowerCase()}:0',
          title: animeTitle(title),
          description: '',
          genre: 'Anime',
          year: 0,
          durationMinutes: 0,
          kind: 'anime',
          isSeries: true,
          posterUrl: poster ?? preview.posterUrl,
          sources: [
            MediaSource(
                provider: 'animesonlinecc',
                sourceId: uri.pathSegments.where((v) => v.isNotEmpty).last,
                pageUrl: link,
                posterUrl: poster)
          ]);
      return (item: parent, episode: source.pageUrl);
    } finally {
      session.close();
    }
  }

  Future<List<Map<String, dynamic>>> notices({bool markRead = false}) async {
    final p = await SharedPreferences.getInstance();
    final rows =
        ((jsonDecode(p.getString('cineshow.anime.notices.v1') ?? '[]')) as List)
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList();
    if (markRead) {
      for (final row in rows) {
        row['read'] = true;
      }
      await p.setString('cineshow.anime.notices.v1', jsonEncode(rows));
    }
    return rows;
  }

  Future<void> _record(Map<String, List<MediaItem>> data) async {
    final p = await SharedPreferences.getInstance();
    final events = await notices();
    for (final type in data.keys) {
      final key = 'cineshow.anime.seen.$provider.$type';
      final before = p.getStringList(key);
      final seen = (before ?? []).toSet();
      for (final item in data[type]!) {
        final id = item.sources.first.pageUrl;
        if (before != null && !seen.contains(id)) {
          events.insert(0, {
            'title': item.title,
            'body': type == 'episodes'
                ? 'Novo episódio na fonte'
                : 'Anime adicionado à fonte',
            'item': item.toJson(),
            'read': false
          });
        }
        seen.add(id);
      }
      await p.setStringList(key, seen.toList());
    }
    await p.setString(
        'cineshow.anime.notices.v1', jsonEncode(events.take(100).toList()));
  }
}
