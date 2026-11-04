import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/media_item.dart';
import 'live_catalog.dart' show attributes, plain;
import 'source_origins.dart';

class ProviderPlaybackOption {
  const ProviderPlaybackOption(
      {required this.url,
      required this.label,
      required this.direct,
      required this.id,
      this.headers = const {}});
  final String url, label, id;
  final bool direct;
  final Map<String, String> headers;
  MediaItem media(MediaItem item) => MediaItem(
      id: '${item.id}:$id',
      title: '${item.title} · $label',
      description: item.description,
      genre: item.genre,
      year: item.year,
      durationMinutes: item.durationMinutes,
      posterUrl: item.posterUrl,
      kind: item.kind,
      streamUrl: url,
      streamHeaders: headers,
      sources: item.sources);
}

/// Uses the requests exposed by the source's own player, keeping its session.
/// An embed URL is explicitly distinguished from verified video bytes.
class ProviderPlaybackResolver {
  ProviderPlaybackResolver({http.Client? client})
      : client = client ?? http.Client();
  final http.Client client;
  final cookies = <String, Map<String, String>>{};
  bool closed = false;
  void close() {
    closed = true;
    client.close();
  }

  Future<String> _text(Uri uri,
      {String? body,
      bool discover = false,
      String? referer,
      bool xhr = false}) async {
    final initial = uri;
    for (var redirects = 0; redirects < 5; redirects++) {
      if (closed) throw StateError('Consulta cancelada.');
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw StateError('Endereço da fonte inválido.');
      }
      final request = http.Request(body == null ? 'GET' : 'POST', uri)
        ..followRedirects = false
        ..headers.addAll({
          'User-Agent': 'CINESHOW/0.4.0',
          if (referer != null) 'Referer': referer,
          if (xhr) 'X-Requested-With': 'XMLHttpRequest',
          if (cookies[uri.host]?.isNotEmpty == true)
            'Cookie': cookies[uri.host]!
                .entries
                .map((e) => '${e.key}=${e.value}')
                .join('; ')
        });
      if (body != null) {
        request.headers['Content-Type'] = 'application/x-www-form-urlencoded';
        request.body = body;
      }
      final response =
          await client.send(request).timeout(const Duration(seconds: 20));
      final setCookie = response.headers['set-cookie'];
      if (setCookie != null) {
        for (final m
            in RegExp(r'(?:^|,\s*)([\w-]+)=([^;,]*)').allMatches(setCookie)) {
          cookies.putIfAbsent(uri.host, () => {})[m[1]!] = m[2]!;
        }
      }
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        await response.stream.listen((_) {}).cancel();
        final location = response.headers['location'];
        if (location == null) throw StateError('Redirecionamento inválido.');
        final next = uri.resolve(location);
        if (!discover && next.origin != initial.origin) {
          throw StateError('A fonte mudou de endereço durante a consulta.');
        }
        uri = next;
        if (response.statusCode == 303) body = null;
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw StateError('A fonte respondeu HTTP ${response.statusCode}.');
      }
      final bytes = <int>[];
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 2000000) {
          throw StateError('Resposta da fonte muito grande.');
        }
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      if (discover) _origin = uri.origin;
      return text;
    }
    throw StateError('A fonte redirecionou muitas vezes.');
  }

  late String _origin;
  Uri _url(String path) {
    final uri = Uri.parse(_origin).resolve(path);
    if (uri.origin != _origin) throw StateError('Rota fora da fonte.');
    return uri;
  }

  Future<String> _get(String path) => _text(_url(path));
  Future<String> _post(String path, String body) =>
      _text(_url(path), body: body);

  Future<List<ProviderPlaybackOption>> resolve(
      MediaItem item, MediaSource source,
      {required String pageUrl}) async {
    final home =
        await _text(Uri.parse(origins[source.provider]!), discover: true);
    if (source.provider == 'xonados') return _xonados(source, pageUrl);
    final brand = source.provider == 'rtfilmes' ? 'pobreflix' : 'topflix';
    if (!home.toLowerCase().contains(brand) || !home.contains('dooplay')) {
      throw StateError('A fonte não retornou seu catálogo reconhecido.');
    }
    return _dooplay(item, source, pageUrl);
  }

  Future<List<ProviderPlaybackOption>> _dooplay(
      MediaItem item, MediaSource source, String pageUrl) async {
    final selections = <Map<String, String>>[];
    if (item.kind == 'movie' && RegExp(r'^\d+$').hasMatch(source.sourceId)) {
      for (var i = 1; i <= 4; i++) {
        selections.add({
          'post': source.sourceId,
          'type': 'movie',
          'source': '$i',
          'label': 'Player $i'
        });
      }
    } else {
      final pageUri = Uri.parse(pageUrl);
      final page = await _get(
          '${pageUri.path}${pageUri.hasQuery ? '?${pageUri.query}' : ''}');
      for (final tag
          in RegExp(r'<li\b[^>]*>.*?</li>', dotAll: true).allMatches(page)) {
        final a = attributes(tag[0]!);
        if (a['data-nume'] == 'trailer' ||
            !RegExp(r'^\d+$').hasMatch(a['data-post'] ?? '') ||
            !RegExp(r'^\d+$').hasMatch(a['data-nume'] ?? '') ||
            !RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(a['data-type'] ?? '')) {
          continue;
        }
        selections.add({
          'post': a['data-post']!,
          'type': a['data-type']!,
          'source': a['data-nume']!,
          'label': plain(tag[0]!)
        });
      }
    }
    final found = await Future.wait(selections.take(6).map((selection) async {
      try {
        final data = jsonDecode(await _get(
                '/wp-json/dooplayer/v2/${selection['post']}/${selection['type']}/${selection['source']}'))
            as Map;
        final url = data['embed_url'] as String?;
        if (data['type'] != 'iframe' || url == null) return null;
        final uri = Uri.tryParse(url);
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
          return null;
        }
        final label = switch (uri.host) {
          'embed.embedplayer.site' => 'GD',
          'superflixapi.fun' => 'BK',
          'embedplayapi.top' => 'WZ',
          'www.2embed.cc' => '2B',
          _ => selection['label']!
        };
        return ProviderPlaybackOption(
            url: url,
            label: '$label · player do provedor',
            direct: false,
            id: '${source.provider}:${selection['post']}:${selection['source']}',
            headers: {'Referer': '$_origin/'});
      } catch (_) {
        return null;
      }
    }));
    final unique = <String, ProviderPlaybackOption>{};
    for (final option in found.whereType<ProviderPlaybackOption>()) {
      unique.putIfAbsent(option.url, () => option);
    }
    final result = unique.values.toList();
    if (result.isEmpty) {
      throw StateError('Nenhum player respondeu pela API da fonte.');
    }
    return result;
  }

  Future<List<ProviderPlaybackOption>> expand(
      ProviderPlaybackOption option) async {
    final uri = Uri.parse(option.url);
    if (uri.host != 'embed.embedplayer.site') return [option];
    try {
      final html = await _text(uri, referer: option.headers['Referer']);
      final server = RegExp(r"""idS=["']([^"']+)["']""", caseSensitive: false)
          .firstMatch(html)?[1];
      if (server == null) return [option];
      final data = jsonDecode(await _text(uri.resolve('/stream'),
          body: 'idS=${Uri.encodeQueryComponent(server)}',
          referer: uri.toString(),
          xhr: true)) as Map;
      if (data['break'] == true) return [option];
      final resources = data['resources'] as Map?;
      if (resources == null) return [option];
      final result = <ProviderPlaybackOption>[];
      for (final raw
          in ((resources['sources'] as List?) ?? []).whereType<Map>()) {
        final value = raw['file'] as String?;
        final target = value == null ? null : Uri.tryParse(value);
        if (target == null || target.scheme != 'https' || target.host.isEmpty) {
          continue;
        }
        final headers = {
          'Referer': '${uri.origin}/',
          'User-Agent': 'CINESHOW/0.4.0'
        };
        final direct = resources['iframe'] != true;
        if (direct && !await _isVideo(value!, headers)) continue;
        result.add(ProviderPlaybackOption(
            url: value!,
            label: option.label,
            direct: direct,
            id: option.id,
            headers: headers));
      }
      return result.isEmpty ? [option] : result;
    } catch (_) {
      return [option];
    }
  }

  Future<List<ProviderPlaybackOption>> _xonados(
      MediaSource source, String pageUrl) async {
    if (!RegExp(r'^\d+$').hasMatch(source.sourceId)) {
      throw StateError('Novela inválida.');
    }
    await _post('/RTRT', source.sourceId);
    final page = await _get('/');
    final script = RegExp(r'''<script[^>]+src=["']([^"']*YwZ[^"']*)''')
        .firstMatch(page)?[1];
    if (script == null) throw StateError('A fonte não selecionou a novela.');
    final js = await _get(script.replaceAll('&amp;', '&'));
    final frame = RegExp(r"iframe.src\s*=\s*'([^']+)'").firstMatch(js)?[1];
    if (frame == null) throw StateError('Lista de capítulos indisponível.');
    var markup = await _get(frame.replaceAll('&amp;', '&'));
    final requested = Uri.parse(pageUrl).queryParameters['date'];
    if (requested != null && !RegExp(r'^\d{8}(?:_\d+)?$').hasMatch(requested)) {
      throw StateError('Data de capítulo inválida.');
    }
    String? episode;
    for (var history = 0; history < 3; history++) {
      final frames = RegExp(r'<iframe\b[^>]*>')
          .allMatches(markup)
          .map((m) => attributes(m[0]!)['src'])
          .whereType<String>()
          .toList();
      for (final path in frames) {
        final date = Uri.parse(path).queryParameters['date'];
        if (date != null &&
            RegExp(r'^\d{8}(?:_\d+)?$').hasMatch(date) &&
            (requested == null || date == requested)) {
          episode = path;
          break;
        }
      }
      if (episode != null || requested == null) break;
      final dates = RegExp(r'date=(\d{8})')
          .allMatches(markup)
          .map((m) => m[1]!)
          .toList()
        ..sort();
      if (dates.isEmpty) break;
      final token = (await _post('/G_sTw', '')).trim();
      if (!RegExp(r'^[a-zA-Z0-9]{1,128}$').hasMatch(token)) break;
      markup = await _post(
          '/Y_sTw?y=${Uri.encodeQueryComponent(token)}&zy=${source.sourceId}',
          'vlum=${dates.first}');
    }
    if (episode == null) {
      throw StateError(
          'Este capítulo não foi localizado na sessão atual da fonte.');
    }
    final episodeUrl = _url(episode);
    final html = await _get(episode);
    final urls = <String>{};
    for (final tag in RegExp(r'<(?:source|video)\b[^>]*>').allMatches(html)) {
      final raw = attributes(tag[0]!)['src'];
      if (raw == null) continue;
      final uri = episodeUrl.resolve(raw);
      if (uri.scheme == 'https' && uri.host.isNotEmpty) {
        urls.add(uri.toString());
      }
    }
    final result = <ProviderPlaybackOption>[];
    final date = episodeUrl.queryParameters['date']!;
    for (final url in urls.take(3)) {
      final headers = {'Referer': '$_origin/', 'User-Agent': 'CINESHOW/0.4.0'};
      if (!await _isVideo(url, headers)) continue;
      result.add(ProviderPlaybackOption(
          url: url,
          label:
              'Capítulo ${date.substring(6, 8)}/${date.substring(4, 6)}/${date.substring(0, 4)}${date.length > 8 ? ' · Variante ${date.substring(9)}' : ''}',
          direct: true,
          id: 'xonados:${source.sourceId}:$date',
          headers: headers));
    }
    if (result.isEmpty) {
      throw StateError(
          'A fonte não entregou um vídeo direto válido para este capítulo.');
    }
    return result;
  }

  Future<bool> _isVideo(String url, Map<String, String> headers) async {
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers.addAll({...headers, 'Range': 'bytes=0-1023'});
      final response =
          await client.send(request).timeout(const Duration(seconds: 15));
      final first =
          await response.stream.first.timeout(const Duration(seconds: 15));
      if (![200, 206].contains(response.statusCode)) return false;
      final signature = latin1.decode(first.take(32).toList());
      return first.length >= 8 && signature.substring(4, 8) == 'ftyp' ||
          signature.startsWith('#EXTM3U') ||
          first.length > 188 && first[0] == 0x47 && first[188] == 0x47;
    } catch (_) {
      return false;
    }
  }
}
