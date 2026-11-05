import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/actor_catalog.dart';
import 'package:cineshow/core/services/source_session.dart';
import 'package:cineshow/core/services/source_origins.dart';
import 'package:cineshow/core/services/live_catalog.dart';
import 'package:cineshow/core/services/superflix_catalog.dart';
import 'package:cineshow/core/services/title_information.dart';
import 'package:cineshow/core/services/title_identity.dart';

String archive() =>
    File('test/fixtures/actor_tom_holland.html').readAsStringSync();

class ActorSession extends SourceSession {
  ActorSession(super.origin, this.calls, {this.failFirst = false});
  final List<String> calls;
  final bool failFirst;
  @override
  Future<String> get(String path, {String? body}) async {
    calls.add('$origin$path');
    if (failFirst &&
        origin == origins['tontons'] &&
        calls.where((v) => v.startsWith(origin)).length == 1) {
      throw StateError('Temporary source failure');
    }
    return archive()
        .replaceAll('filmesamadoresgratis.com', Uri.parse(origin).host);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'actor search retrieves unseen movies from live archives and excludes sidebar recommendations',
      () async {
    final calls = <String>[];
    final service =
        ActorCatalog(sessionFactory: (origin) => ActorSession(origin, calls));
    expect(await service.titles('Tom Holland'), isEmpty);
    final result = await service.search('Tom Holland', reset: true);
    expect(result.items, hasLength(16));
    expect(result.items.map((v) => v.title), contains('O Impossível'));
    expect(result.items.map((v) => v.title), isNot(contains('Falso')));
    expect(result.items.first.sources, hasLength(2));
    expect(calls, hasLength(2));
    expect(await service.titles('Tom Holland'), hasLength(16));
    await service.search('Tom Holland', reset: true);
    expect(calls, hasLength(4));
    expect(result.hasMore, isFalse);
  });
  test(
      'actor archives must confirm the person and failed sources can be retried',
      () async {
    expect(() => parseActorArchive(archive(), 'Brad Pitt', 'rtfilmes'),
        throwsStateError);
    final calls = <String>[];
    final service = ActorCatalog(
        sessionFactory: (origin) =>
            ActorSession(origin, calls, failFirst: true));
    final first = await service.search('Tom Holland', reset: true);
    expect(first.errors, ['tontons']);
    expect(first.items, hasLength(16));
    final next = await service.search('Tom Holland');
    expect(next.errors, isEmpty);
    expect(next.items.first.sources, hasLength(2));
    expect(calls.where((v) => v.startsWith(origins['tontons']!)), hasLength(2));
  });
  test(
      'original title removes source SEO and suggestion matching rejects another year or person',
      () {
    expect(
        originalSourceTitle(
            '<div class="custom_fields"><b class="variante">Título Original </b><span class="valor">Watch Spider-Man: Brand New Day Online</span></div>'),
        'Spider-Man: Brand New Day');
    final raw = {
      'd': [
        {
          'id': 'tt22084616',
          'l': 'Spider-Man: Brand New Day',
          'y': 2026,
          'qid': 'movie'
        },
        {'id': 'tt1234567', 'l': 'Another Movie', 'y': 2026, 'qid': 'movie'},
        {
          'id': 'nm0000001',
          'l': 'Spider-Man: Brand New Day',
          'y': 2026,
          'qid': 'name'
        }
      ]
    };
    expect(
        matchImdbSuggestion(raw, ['Spider-Man: Brand New Day'], 2026,
            movie: true)?['id'],
        'tt22084616');
    expect(
        matchImdbSuggestion(raw, ['Spider-Man: Brand New Day'], 2025,
            movie: true),
        isNull);
    expect(
        matchImdbSuggestion(raw, ['Homem-Aranha: Um Novo Dia'], 2026,
            movie: true),
        isNull);
    final ambiguous = {
      'd': [
        ...raw['d']!,
        {
          'id': 'tt9876543',
          'l': 'Spider-Man: Brand New Day',
          'y': 2026,
          'qid': 'movie'
        }
      ]
    };
    expect(
        matchImdbSuggestion(ambiguous, ['Spider-Man: Brand New Day'], 2026,
            movie: true),
        isNull);
  });
  test(
      'public SuperFlix IMDb IDs survive serialization and enrich already cached sources',
      () {
    final rows = parseSuperflixCards(
        File('test/fixtures/super_imdb.html').readAsStringSync());
    final current = rows.single;
    expect(current.sources.single.imdbId, matches(r'^tt\d{7,10}$'));
    final original = current.sources.single;
    final old = MediaItem(
        id: current.id,
        title: current.title,
        description: '',
        genre: '',
        year: current.year,
        durationMinutes: 0,
        sources: [
          MediaSource(
              provider: original.provider,
              sourceId: original.sourceId,
              pageUrl: original.pageUrl)
        ]);
    final updated = LiveCatalog().mergeItems([old, current]).single;
    final restored = MediaItem.fromJson(updated.toJson());
    expect(restored.sources.single.imdbId, original.imdbId);
  });
  test(
      'metadata lookup uses the published IMDb ID without requiring a playable SuperFlix page',
      () async {
    final requests = <Uri>[];
    const source = MediaSource(
        provider: 'superflix',
        sourceId: '123',
        pageUrl: 'https://superflixapi.fun/filme/123',
        imdbId: 'tt22084616');
    const item = MediaItem(
        id: 'super',
        title: 'Homem-Aranha: Um Novo Dia',
        description: '',
        genre: '',
        year: 2026,
        durationMinutes: 0,
        sources: [source]);
    final service = TitleInformationService(
        apiBase: '',
        clientFactory: () => MockClient((request) async {
              requests.add(request.url);
              if (request.url.host == 'v2.sg.media-imdb.com') {
                return http.Response(
                    jsonEncode({
                      'd': [
                        {
                          'id': 'tt22084616',
                          'l': 'Spider-Man: Brand New Day',
                          'y': 2026,
                          'qid': 'movie'
                        }
                      ]
                    }),
                    200);
              }
              if (request.url.host == 'www.rottentomatoes.com') {
                if (request.url.path == '/search') {
                  return http.Response(
                      File('test/fixtures/rotten_search.html')
                          .readAsStringSync(),
                      200);
                }
                return http.Response(
                    File('test/fixtures/rotten_title.html').readAsStringSync(),
                    200);
              }
              return http.Response('Forbidden', 403);
            }));
    final data = await service.load(item, source);
    expect(data['title'], 'Spider-Man: Brand New Day');
    expect(data['rtRating'], 90);
    expect(data['rtAudienceRating'], 97);
    expect(requests.where((v) => v.host == 'superflixapi.fun'), isEmpty);
  });
}
