import 'dart:convert';
import '../models/media_item.dart';
import 'source_html.dart';
import 'source_session.dart';
import 'audio_metadata.dart';

const superflixOrigin = 'https://superflixapi.fun';
bool hasCatalogNextPage(String html, int page) =>
    RegExp('(?:[?&]|&amp;)(?:page|paged)=${page + 1}(?:&|["\x27<>\\s])')
        .hasMatch(html);

List<MediaItem> parseSuperflixCards(String html,
    {String? kind, bool dorama = false}) {
  final cards =
      html.split(RegExp(r'''<div\s+x-data=["']\{\s*open:\s*false\s*\}["']'''));
  final result = <String, MediaItem>{};
  for (final block in cards.skip(1)) {
    final button = RegExp(r'<button\b[^>]*data-embed=[^>]+>').firstMatch(block);
    if (button == null) continue;
    final a = attributes(button[0]!);
    try {
      final uri = Uri.parse(utf8.decode(base64Decode(a['data-embed']!)));
      if (uri.origin != superflixOrigin ||
          !RegExp(r'^/(?:filme|serie)/(?:tt\d{7,10}|\d+)/?$')
              .hasMatch(uri.path)) {
continue;
}
      final title = utf8.decode(base64Decode(a['data-title']!));
      final image = attributes(
          RegExp(r'<img\b[^>]*>').firstMatch(block)?[0] ?? '')['src'];
      final year = RegExp(r'<span[^>]*>\s*((?:19|20)\d{2})\s*</span>')
          .firstMatch(block)?[1];
      final heading = block.indexOf('<h3');
      final audio =
          audioLabel(plain(heading < 0 ? '' : block.substring(0, heading)));
      final resolvedKind =
          uri.path.startsWith('/filme/') ? 'movie' : kind ?? 'series';
      result[uri.toString()] = MediaItem(
          id: 'superflix:${uri.path}',
          title: title,
          description: '',
          genre: dorama ? 'Dorama' : '',
          year: int.tryParse(year ?? '') ?? 0,
          durationMinutes: 0,
          kind: resolvedKind,
          isSeries: resolvedKind != 'movie',
          audio: audio,
          posterUrl: image,
          sources: [
            MediaSource(
                provider: 'superflix',
                sourceId: uri.pathSegments.lastWhere((v) => v.isNotEmpty),
                pageUrl: uri.toString(),
                posterUrl: image)
          ]);
    } catch (_) {}
  }
  return result.values.toList();
}

class SuperflixService {
  Future<({List<MediaItem> items, bool more})> titles(
      {String kind = 'movie',
      int page = 1,
      String query = '',
      bool dorama = false}) async {
    final session = SourceSession(superflixOrigin);
    try {
      final type = kind == 'movie'
          ? '1'
          : kind == 'anime'
              ? '3'
              : dorama
                  ? '5'
                  : '2';
      final path = query.trim().isNotEmpty
          ? '/pesquisar?s=${Uri.encodeQueryComponent(query.trim())}&paged=$page&type=$type'
          : '/${kind == 'movie' ? 'filmes' : kind == 'anime' ? 'animes' : dorama ? 'doramas' : 'series'}?page=$page';
      final html = await session.get(path);
      final items = parseSuperflixCards(html, kind: kind, dorama: dorama);
      return (items: items, more: hasCatalogNextPage(html, page));
    } finally {
      session.close();
    }
  }

  Future<List<Map<String, dynamic>>> live({bool events = false}) async {
    final session = SourceSession(superflixOrigin);
    try {
      final raw = jsonDecode(await session.get(
              '/lista?category=${events ? 'eventos' : 'canais'}&format=json&limit=500'))
          as Map;
      if (raw['success'] != true)
        {
throw StateError('A fonte não retornou a lista.');
}
      return ((raw['data'] as List?) ?? [])
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .where((v) =>
              v['is_active'] != false &&
              v['is_nsfw'] != true &&
              !['adulto', 'adultos', 'xxx']
                  .contains('${v['category']}'.toLowerCase()))
          .toList();
    } finally {
      session.close();
    }
  }
}
