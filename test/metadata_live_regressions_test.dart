import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/public_title_metadata.dart';
import 'package:cineshow/core/services/title_information.dart';
import 'package:cineshow/core/services/source_session.dart';
import 'package:cineshow/core/services/superflix_catalog.dart';
import 'package:cineshow/core/services/player_migrations.dart';
import 'package:cineshow/core/services/provider_embed.dart';
import 'package:cineshow/core/services/provider_playback.dart';
import 'package:cineshow/core/services/tv_aberta.dart';
import 'package:cineshow/features/details/title_ratings.dart';
import 'package:cineshow/features/details/published_cast.dart';
import 'package:cineshow/features/live/superflix_live_view.dart';

String fixture(String name) =>
    File('test/fixtures/$name.html').readAsStringSync();
const title = 'Spider-Man: Brand New Day';
final rt =
    Uri.parse('https://www.rottentomatoes.com/m/spider_man_brand_new_day');
String snapshot({bool events = false}) => jsonEncode({
      'source': superflixOrigin,
      'fetchedAt': '2026-11-05T14:00:00Z',
      'items': [
        {
          'id': 'test',
          if (events)
            'title': 'Evento verificado'
          else
            'name': 'Canal verificado',
          if (events)
            'play_event_url': '$superflixOrigin/eventos/test'
          else
            'embed_url': '$superflixOrigin/canal/test',
          'category': 'Esportes',
          'is_active': true
        }
      ]
    });

void main() {
  test('source exposes ten actors and an explicitly labelled IMDb score', () {
    final html = fixture('source_credits');
    final credits = publishedCredits(html);
    expect(credits['cast'], hasLength(10));
    expect(credits['cast'], contains('Marvin Jones III'));
    expect(credits['director'], 'Destin Daniel Cretton');
    expect(publishedImdbRating(html), 8.0);
    expect(
        publishedImdbRating(
            '<span class="dt_rating_vgs" itemprop="ratingValue">9.9</span>'),
        isNull);
  });
  test('Rotten critics and verified audience percentages stay separate', () {
    final data = publicRottenTitle(fixture('rotten_title'), rt, title, 2026,
        movie: true);
    expect(data['rtRating'], 90);
    expect(data['rtAudienceRating'], 97);
    expect(rottenCredits(fixture('rotten_cast')), hasLength(11));
    expect(
        publicRottenTitle(fixture('rotten_title'), rt, title, 2025,
            movie: true),
        isEmpty);
    expect(
        publicRottenTitle(fixture('rotten_title'), rt, 'Another movie', 2026,
            movie: true),
        isEmpty);
    expect(rottenCandidates(fixture('rotten_search'), title, 2026, movie: true),
        [rt]);
    expect(rottenCandidates(fixture('rotten_search'), title, 2025, movie: true),
        isEmpty);
    expect(
        publicImdbTitle(
            '<script type="application/ld+json">{"@type":"Movie","url":"https://www.imdb.com/title/tt0000001/","aggregateRating":{"ratingValue":9}}</script>',
            'tt22084616',
            movie: true),
        isEmpty);
  });
  test(
      'IMDb access refusal still preserves source score and full Rotten credits without an API key',
      () async {
    SharedPreferences.setMockInitialValues({});
    const source = MediaSource(
        provider: 'rtfilmes',
        sourceId: '164791',
        pageUrl: 'https://filmesamadoresgratis.com/filme/example/');
    const item = MediaItem(
        id: 'spider',
        title: 'Homem-Aranha: Um Novo Dia',
        description: '',
        genre: '',
        year: 2026,
        durationMinutes: 0,
        sources: [source]);
    final service = TitleInformationService(
        apiBase: '',
        clientFactory: () => MockClient((request) async {
              if (request.url.host == 'filmesamadoresgratis.com')
                return http.Response(fixture('source_credits'), 200);
              if (request.url.host == 'v2.sg.media-imdb.com')
                return http.Response(
                    jsonEncode({
                      'd': [
                        {
                          'id': 'tt22084616',
                          'l': title,
                          'y': 2026,
                          'qid': 'movie',
                          's': 'Tom Holland, Zendaya'
                        }
                      ]
                    }),
                    200);
              if (request.url.host == 'www.imdb.com')
                return http.Response('Forbidden', 403);
              if (request.url.path == '/search')
                return http.Response(fixture('rotten_search'), 200);
              if (request.url.path.endsWith('/cast-and-crew'))
                return http.Response(fixture('rotten_cast'), 200);
              return http.Response(fixture('rotten_title'), 200);
            }));
    final data = await service.load(item, source);
    expect(data['imdbRating'], 8.0);
    expect(data['imdbRatingSource'], contains('Pobreflix'));
    expect(data['rtRating'], 90);
    expect(data['rtAudienceRating'], 97);
    expect((data['cast'] as List).length, greaterThanOrEqualTo(11));
    expect(data['cast'], contains('Marvin Jones III'));
  });
  test('live API HTTP failure recovers verified channels and events', () async {
    for (final events in [false, true]) {
      final service = SuperflixService(
          sessionFactory: (origin) => SourceSession(origin,
              client:
                  MockClient((_) async => http.Response('Unavailable', 503))),
          snapshotLoader: (requestedEvents) async =>
              snapshot(events: requestedEvents));
      final rows = await service.live(events: events);
      expect(rows, hasLength(1));
      expect(service.usingSnapshot, isTrue);
      expect(service.lastError, contains('503'));
      expect(service.lastUpdatedAt, DateTime.utc(2026, 11, 5, 14));
    }
    expect(() => parseSuperflixLive('<html>Challenge</html>'),
        throwsFormatException);
    expect(
        parseSuperflixLive(jsonEncode({
          'success': true,
          'data': [
            {'name': 'Wrong host', 'embed_url': 'https://evil.test/canal/1'}
          ]
        })),
        isEmpty);
  });
  test('RedeFlix migrates exact host while preserving title, season and query',
      () async {
    const old = 'https://redeflixapi.store/serie/1396/2/5?lang=pt#player';
    const current = 'https://redeflixapi.bar/serie/1396/2/5?lang=pt#player';
    expect(canonicalPlayerUrl(old), current);
    expect(canonicalPlayerUrl('https://redeflixapi.store.evil.test/filme/1'),
        'https://redeflixapi.store.evil.test/filme/1');
    expect(providerEmbedHtml(old), contains('redeflixapi.bar'));
    final resolver = ProviderPlaybackResolver(
        client: MockClient((_) async =>
            throw StateError('Must not request discontinued domain')));
    final options = await resolver.expand(const ProviderPlaybackOption(
        url: old, label: 'Player', direct: false, id: 'chapter'));
    expect(options.single.url, current);
    resolver.close();
  });
  test('TV Aberta novela schema keeps covers, all seasons and chapter 125', () {
    final body = jsonEncode([
      {
        'id': 'a-candidata',
        'name': 'Assistir A Candidata Dublada Grátis',
        'cover': 'https://example.test/poster.webp',
        'temporadas': {
          '1': List.generate(
              125,
              (n) => {
                    'e': '${n + 1}',
                    't': 'Capítulo ${n + 1}',
                    'sp': 'ACAND-${n + 1}'
                  })
        }
      }
    ]);
    final items = parseTvNovelas(body);
    expect(items.single.title, 'A Candidata');
    expect(items.single.sources.single.provider, 'tvaberta');
    expect(items.single.posterUrl, 'https://example.test/poster.webp');
    final episodes = parseTvEpisodes((jsonDecode(body) as List).single as Map);
    expect(episodes, hasLength(125));
    expect(episodes.last['page_url'], '$tvNovelasOrigin/play/ACAND-125');
  });
  testWidgets(
      'ratings fit a narrow phone and show separate critics/audience scores',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 320,
                child: TitleRatings(data: const {
                  'imdbRating': 7.9,
                  'rtRating': 90,
                  'rtAudienceRating': 97
                }, onImdb: () {}, onRotten: () {})))));
    expect(find.text('7,9/10'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('97%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('full cast list can reach the final credited actor',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PublishedCast(
                names: List.generate(125, (n) => 'Ator ${n + 1}'),
                details: const [],
                onActor: (_) {}))));
    await tester.tap(find.text('Ver todos os 125 atores'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Ator 125'), 500);
    expect(find.text('Ator 125'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('SuperFlix failure displays verified rows and an explicit retry',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = SuperflixService(
        sessionFactory: (origin) => SourceSession(origin,
            client: MockClient((_) async => http.Response('', 503))),
        snapshotLoader: (_) async => snapshot());
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SuperflixLiveView(service: service))));
    await tester.pumpAndSettle();
    expect(find.text('Canal verificado'), findsOneWidget);
    expect(find.text('Atualizar lista'), findsOneWidget);
    expect(find.textContaining('Nenhum resultado'), findsNothing);
    expect(find.textContaining('503'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
