import 'dart:convert';
import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/provider_playback.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const item = MediaItem(
    id: 'title',
    title: 'Teste',
    description: '',
    genre: '',
    year: 2026,
    durationMinutes: 0);

void main() {
  test(
      'DooPlay root migration resolves APIs and keeps embeds distinct from video',
      () async {
    final calls = <Uri>[];
    final resolver =
        ProviderPlaybackResolver(client: MockClient((request) async {
      calls.add(request.url);
      if (request.url.host == 'filmesamadoresgratis.com') {
        return http.Response('', 301,
            headers: {'location': 'https://current.example/'});
      }
      if (request.url.path == '/') {
        return http.Response('''Pobreflix dooplay
<li data-post="123" data-type="movie" data-nume="1">GD</li>
<li data-post="123" data-type="movie" data-nume="7">Servidor extra</li>
<li data-post="123" data-type="movie" data-nume="7">Duplicado</li>
<li data-post="123" data-type="movie" data-nume="trailer">Trailer</li>''', 200);
      }
      if (request.url.path.endsWith('/movie/7')) {
        return http.Response(
            jsonEncode({
              'type': 'iframe',
              'embed_url': 'https://player.example/embed/movie'
            }),
            200);
      }
      return http.Response('missing', 404);
    }));
    try {
      final options = await resolver.resolve(
          item,
          const MediaSource(
              provider: 'rtfilmes',
              sourceId: '123',
              pageUrl: 'https://rtfilmes.com/filme/old/'),
          pageUrl: 'https://rtfilmes.com/filme/old/');
      expect(options, hasLength(1));
      expect(options.single.direct, isFalse);
      expect(options.single.url, 'https://player.example/embed/movie');
      expect(
          calls.any((u) =>
              u.host == 'current.example' &&
              u.path == '/wp-json/dooplayer/v2/123/movie/7'),
          isTrue);
      expect(calls.where((u) => u.path.endsWith('/movie/7')), hasLength(1));
      expect(calls.any((u) => u.path.endsWith('/movie/2')), isFalse);
      expect(calls.any((u) => u.path.endsWith('/trailer')), isFalse);
    } finally {
      resolver.close();
    }
  });
  test(
      'Xonados refreshes episode session and validates MP4 bytes, not an old player URL',
      () async {
    var selected = false;
    final resolver =
        ProviderPlaybackResolver(client: MockClient((request) async {
      if (request.url.host == 'cdn.example') {
        expect(request.headers['Range'], 'bytes=0-1023');
        expect(request.headers.keys.any((k) => k.toLowerCase() == 'cookie'),
            isFalse);
        return http.Response('\u0000\u0000\u0000\u0018ftypisom', 206,
            headers: {'content-type': 'video/mp4'});
      }
      if ((request.url.path.isEmpty || request.url.path == '/') && !selected) {
        return http.Response('XONADOS', 200, headers: {
          'set-cookie': 'PHPSESSID=public-session; Path=/; Secure'
        });
      }
      expect(request.headers['Cookie'], contains('PHPSESSID=public-session'));
      if (request.url.path == '/RTRT') {
        expect(request.body, '2');
        selected = true;
        return http.Response('', 200);
      }
      if (request.url.path == '/') {
        return http.Response(
            '<script src="/ast/YwZ.js?y=fresh"></script>', 200);
      }
      if (request.url.path == '/ast/YwZ.js') {
        return http.Response("iframe.src = '/ast/FzY?y=fresh&zy=2';", 200);
      }
      if (request.url.path == '/ast/FzY') {
        return http.Response(
            '<iframe src="/ast/OnW/?zy=2&amp;date=20261103&amp;y=fresh"></iframe>',
            200);
      }
      if (request.url.path == '/ast/OnW/') {
        expect(request.url.queryParameters['y'], 'fresh');
        return http.Response(
            '<video><source src="https://cdn.example/video?id=chapter"></video>',
            200);
      }
      return http.Response('missing', 404);
    }));
    try {
      final result = await resolver.resolve(
          item,
          const MediaSource(
              provider: 'xonados',
              sourceId: '2',
              pageUrl: 'https://www.xonados.com/'),
          pageUrl: '/ast/OnW/?date=20261103&y=expired');
      expect(result.single.direct, isTrue);
      expect(result.single.url, 'https://cdn.example/video?id=chapter');
      expect(result.single.media(item).id, contains('xonados:2:20261103'));
      expect(result.single.headers['Referer'], contains('/ast/OnW/'));
      expect(result.single.headers['Referer'], contains('date=20261103'));
    } finally {
      resolver.close();
    }
  });
  test('video signature accepts fragmented MP4 and rejects HTML', () async {
    for (final valid in [true, false]) {
      final resolver = ProviderPlaybackResolver(
          client: MockClient.streaming((request, body) async {
        await body.drain<void>();
        if (request.url.host == 'cdn.example') {
          expect(request.headers['Range'], 'bytes=0-1023');
          final chunks = valid
              ? <List<int>>[
                  [0, 0],
                  [0, 24, 102],
                  [116, 121, 112, 105, 115, 111, 109]
                ]
              : [utf8.encode('<html>not a video</html>')];
          return http.StreamedResponse(Stream.fromIterable(chunks), 206);
        }
        if (request.method == 'GET') {
          return http.StreamedResponse(
              Stream.value(utf8.encode('<div idS="public"></div>')), 200);
        }
        return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'resources': {
                'iframe': false,
                'sources': [
                  {'file': 'https://cdn.example/video'}
                ]
              }
            }))),
            200);
      }));
      try {
        final result = await resolver.expand(const ProviderPlaybackOption(
            url: 'https://embed.embedplayer.site/tt1234567',
            label: 'GD',
            direct: false,
            id: 'gd'));
        expect(result.single.direct, valid);
        expect(
            result.single.url,
            valid
                ? 'https://cdn.example/video'
                : 'https://embed.embedplayer.site/tt1234567');
      } finally {
        resolver.close();
      }
    }
  });
  test(
      'GD normal server selection returns an iframe without claiming direct playback',
      () async {
    final resolver =
        ProviderPlaybackResolver(client: MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response('<div idS="public-choice"></div>', 200);
      }
      expect(request.url.path, '/stream');
      expect(request.body, 'idS=public-choice');
      expect(request.headers['X-Requested-With'], 'XMLHttpRequest');
      return http.Response(
          jsonEncode({
            'break': false,
            'resources': {
              'iframe': true,
              'sources': [
                {'file': 'https://nested-player.example/video/id'}
              ]
            }
          }),
          200);
    }));
    try {
      final result = await resolver.expand(const ProviderPlaybackOption(
          url: 'https://embed.embedplayer.site/tt1234567',
          label: 'GD',
          direct: false,
          id: 'gd'));
      expect(result.single.url, 'https://nested-player.example/video/id');
      expect(result.single.direct, isFalse);
    } finally {
      resolver.close();
    }
  });
  test('Mega anime page resolves its published episode player route', () async {
    final calls = <Uri>[];
    final resolver =
        ProviderPlaybackResolver(client: MockClient((request) async {
      calls.add(request.url);
      switch (request.url.path) {
        case '/anime/dragon-ball-daima':
          return http.Response(
              '<iframe id="awPlayerFrame" src="/player.php?type=anime&amp;id=236994&amp;season=1&amp;episode=1"></iframe>',
              200);
        case '/player.php':
          expect(request.url.queryParameters['type'], 'anime');
          return http.Response(
              'const apiUrl = "/generate_token.php?type=anime&id=236994&season=1&episode=1";',
              200);
        case '/generate_token.php':
          expect(request.url.queryParameters['episode'], '1');
          return http.Response(
              jsonEncode({
                'ok': true,
                'mode': 'iframe',
                'url': 'https://redeflixapi.bar/serie/236994/1/1'
              }),
              200);
        default:
          return http.Response('missing', 404);
      }
    }));
    try {
      const source = MediaSource(
          provider: 'megafilmes',
          sourceId: 'dragon-ball-daima',
          pageUrl: 'https://megafilmeshd1.com/anime/dragon-ball-daima');
      final options =
          await resolver.resolve(item, source, pageUrl: source.pageUrl);
      expect(options.single.direct, isFalse);
      expect(options.single.url, 'https://redeflixapi.bar/serie/236994/1/1');
      expect(calls.map((v) => v.path),
          ['/anime/dragon-ball-daima', '/player.php', '/generate_token.php']);
    } finally {
      resolver.close();
    }
  });
}
