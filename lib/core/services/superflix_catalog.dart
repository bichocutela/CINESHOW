import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
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
      final imdbIds = RegExp(r'''data-copy=["'](tt\d{7,10})["']''').allMatches(block).map((v) => v[1]!).toSet();
      final imdbId = imdbIds.length == 1 ? imdbIds.single : null;
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
                imdbId: imdbId,
                pageUrl: uri.toString(),
                posterUrl: image)
          ]);
    } catch (_) {}
  }
  return result.values.toList();
}

List<Map<String, dynamic>> parseSuperflixLive(String body,
    {bool events = false, bool snapshot = false}) {
  final raw = jsonDecode(body.replaceFirst('\ufeff', '').trim());
  if (raw is! Map ||
      (!snapshot && raw['success'] != true) ||
      (snapshot && raw['source'] != superflixOrigin)) {
    throw const FormatException('Invalid live directory');
  }
  final data = raw[snapshot ? 'items' : 'data'];
  if (data is! List) throw const FormatException('Missing live items');
  final rows = <Map<String, dynamic>>[];
  for (final item in data.whereType<Map>()) {
    final v = Map<String, dynamic>.from(item);
    if ([false, 0, '0'].contains(v['is_active']) ||
        [true, 1, '1'].contains(v['is_nsfw']) ||
        ['adulto', 'adultos', 'xxx']
            .contains('${v['category']}'.toLowerCase())) {
      continue;
    }
    final uri = Uri.tryParse('${v[events ? 'play_event_url' : 'embed_url']}');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.origin != superflixOrigin ||
        uri.userInfo.isNotEmpty ||
        !uri.path.startsWith(events ? '/eventos/' : '/canal/')) {
      continue;
    }
    final name = v[events ? 'title' : 'name'];
    if (name is! String || name.trim().isEmpty) continue;
    rows.add(v);
  }
  return rows;
}

class SuperflixService {
  SuperflixService(
      {SourceSession Function(String)? sessionFactory,
      this.snapshotLoader,
      http.Client Function()? clientFactory})
      : sessionFactory = sessionFactory ?? SourceSession.new,
        clientFactory = clientFactory ?? http.Client.new;
  final SourceSession Function(String) sessionFactory;
  final Future<String> Function(bool)? snapshotLoader;
  final http.Client Function() clientFactory;
  bool usingSnapshot = false;
  DateTime? lastUpdatedAt;
  String? lastError;

  Future<List<Map<String, dynamic>>> cachedLive({bool events = false}) async {
    try {
      final body = snapshotLoader != null
          ? await snapshotLoader!(events)
          : await rootBundle.loadString(
              'assets/superflix_${events ? 'events' : 'channels'}.json');
      return _readSnapshot(body, events);
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> _readSnapshot(String body, bool events) {
    final rows = parseSuperflixLive(body, events: events, snapshot: true);
    final raw = jsonDecode(body) as Map;
    lastUpdatedAt = DateTime.tryParse('${raw['fetchedAt']}');
    usingSnapshot = true;
    return rows;
  }

  Future<List<Map<String, dynamic>>> _snapshot(bool events) async {
    if (snapshotLoader != null) {
      return _readSnapshot(await snapshotLoader!(events), events);
    }
    final client = clientFactory();
    try {
      final response = await client
          .get(Uri.parse(
              'https://raw.githubusercontent.com/bichocutela/CINESHOW/live-data/superflix_${events ? 'events' : 'channels'}.json'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        return _readSnapshot(utf8.decode(response.bodyBytes), events);
      }
    } catch (_) {
      /* A verified bundled directory remains the last fallback. */
    } finally {
      client.close();
    }
    final bundled = await cachedLive(events: events);
    if (bundled.isEmpty) {
      throw StateError('Não foi possível carregar a lista de reserva.');
    }
    return bundled;
  }

  Future<({List<MediaItem> items, bool more})> titles(
      {String kind = 'movie',
      int page = 1,
      String query = '',
      bool dorama = false}) async {
    final session = sessionFactory(superflixOrigin);
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
    final session = sessionFactory(superflixOrigin);
    lastError = null;
    try {
      final body = await session.get(
          '/lista?category=${events ? 'eventos' : 'canais'}&format=json&limit=500');
      final rows = parseSuperflixLive(body, events: events);
      usingSnapshot = false;
      lastUpdatedAt = DateTime.now().toUtc();
      return rows;
    } catch (error) {
      lastError = error is SourceHttpException
          ? 'A fonte respondeu HTTP ${error.status}.'
          : error is TimeoutException
              ? 'A consulta à fonte demorou a responder.'
              : error is FormatException
                  ? 'A fonte retornou uma resposta incompatível.'
                  : 'Não foi possível conectar à fonte nesta rede.';
      return await _snapshot(events);
    } finally {
      session.close();
    }
  }
}
