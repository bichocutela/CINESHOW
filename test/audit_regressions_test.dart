import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/favorites.dart';
import 'package:cineshow/core/services/alternative_sources.dart';
import 'package:cineshow/core/services/audio_metadata.dart';
import 'package:cineshow/core/services/catalog_notices.dart';
import 'package:cineshow/core/services/live_catalog.dart';
import 'package:cineshow/core/services/playback_gateway.dart';
import 'package:cineshow/core/services/continue_watching.dart';
import 'package:cineshow/core/services/anime_catalog.dart';
import 'package:cineshow/core/services/media_downloads.dart';
import 'package:cineshow/features/anime/anime_category_view.dart';
import 'package:cineshow/features/downloads/downloads_page.dart';
import 'package:cineshow/main.dart';

const source = MediaSource(
    provider: 'rtfilmes',
    sourceId: '123',
    pageUrl: 'https://filmesamadoresgratis.com/filme/test/');
MediaItem movie(
        {String id = 'search-only',
        String title = 'Encontrado pelo ator',
        int year = 2026}) =>
    MediaItem(
        id: id,
        title: title,
        description: '',
        genre: '',
        year: year,
        durationMinutes: 0,
        sources: const [source]);

class EmptyCatalog extends LiveCatalog {
  @override
  Future<List<Map<String, dynamic>>> episodes(MediaSource source) async => [];
  @override
  Future<List<MediaItem>> cached() async => [];
  @override
  Future<CatalogResult> refresh({String? query}) async =>
      const CatalogResult([], []);
}

class FakeAnime extends AnimeCatalogService {
  final calls = <String>[];
  final pending = <String, Completer<({List<MediaItem> items, bool more})>>{};
  bool delay = false;
  @override
  Future<Map<String, List<MediaItem>>> cached() async =>
      {'titles': [], 'episodes': []};
  @override
  Future<Map<String, List<MediaItem>>> refresh() => cached();
  @override
  Future<List<Map<String, dynamic>>> notices({bool markRead = false}) async =>
      [];
  @override
  Future<({List<MediaItem> items, bool more})> list(
      {String? letter, String query = '', int page = 1}) async {
    calls.add(query);
    if (delay)
      return pending
          .putIfAbsent(
              query, Completer<({List<MediaItem> items, bool more})>.new)
          .future;
    return (items: <MediaItem>[], more: false);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  MediaItem daima(String provider,
          {String kind = 'anime',
          int year = 0,
          String audio = '',
          String title = 'Dragon Ball Daima',
          String? imdb}) =>
      MediaItem(
          id: '$provider:daima',
          title: title,
          description: '',
          genre: '',
          year: year,
          durationMinutes: 0,
          kind: kind,
          isSeries: kind != 'movie',
          audio: audio,
          sources: [
            MediaSource(
                provider: provider,
                sourceId: 'daima',
                pageUrl: 'https://video.test/$provider/daima',
                imdbId: imdb)
          ]);
  test('Daima from Anime and Mega keeps separate audio and stable identity',
      () {
    final anime = daima('animesonlinecc', audio: 'Legendado');
    final mega =
        daima('megafilmes', kind: 'series', year: 2024, audio: 'Dublado');
    final combined = combineAlternativeSources(anime, [
      mega,
      daima('wrong', title: 'Dragon Ball Z'),
      daima('film', kind: 'movie')
    ]);
    expect(combined.id, anime.id);
    expect(combined.kind, 'anime');
    expect(combined.sources, hasLength(2));
    expect(combined.sources.first.optionLabel, 'Animes Online · Legendado');
    expect(combined.sources.last.optionLabel, 'Mega Filmes · Dublado');
    expect(MediaItem.fromJson(combined.toJson()).sources.last.audio, 'Dublado');
  });
  test(
      'alternative matching rejects remakes and conflicting IDs, accepts a shared published ID',
      () {
    final original = daima('a', year: 2024, imdb: 'tt1234567');
    expect(
        combineAlternativeSources(original, [
          daima('b', year: 1990),
          daima('c', year: 2024, imdb: 'tt7654321')
        ]).sources,
        hasLength(1));
    expect(
        combineAlternativeSources(original, [
          daima('b', year: 2024, title: 'Translated name', imdb: 'tt1234567')
        ]).sources,
        hasLength(2));
    expect(
        combineAlternativeSources(
                daima('a'), [daima('b', year: 1990), daima('c', year: 2024)])
            .sources,
        hasLength(1));
  });
  test(
      'quality badges are preserved without treating SEO text as stream quality',
      () {
    expect(
        catalogQuality(
            '<span class="quality">Dublado 1080p</span><p>2160p</p>'),
        '1080p');
    expect(catalogQuality('<p>Assista em 1080p e 720p</p>'), '');
    final repeated = combineAlternativeSources(
        daima('a', audio: 'Dublado'), [daima('a', audio: 'Dublado')]);
    expect(repeated.sources, hasLength(1));
  });
  testWidgets(
      'details discovers alternate sources without a previous catalog visit',
      (tester) async {
    final item = daima('animesonlinecc', audio: 'Legendado');
    final result = Completer<MediaItem>();
    await tester.pumpWidget(MaterialApp(
        home: DetailsPage(
            item: item,
            catalog: EmptyCatalog(),
            isFavorite: false,
            onFavorite: (_) {},
            onOpenTitle: (_) {},
            sourceDiscovery: (_) => result.future)));
    await tester.pump();
    expect(find.text('Buscando outras fontes…'), findsOneWidget);
    result.complete(combineAlternativeSources(
        item, [daima('megafilmes', year: 2024, audio: 'Dublado')]));
    await tester.pumpAndSettle();
    expect(find.text('Mega Filmes · Dublado'), findsOneWidget);
    expect(find.text('Animes Online · Legendado'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('favorites from actor/search persist even without the Home catalog',
      () async {
    final item = movie();
    await Favorites().toggle(item);
    final restored = await Favorites().load();
    expect(restored.items.single.id, item.id);
    expect(restored.contains(item), isTrue);
    expect(restored.items.single.sources.single.sourceId, '123');
    final corrected = movie(id: 'movie:encontrado pelo ator:2027', year: 2027);
    final migrated = await Favorites().load(known: [corrected]);
    expect(migrated.items, hasLength(1));
    expect(migrated.items.single.year, 2027);
    expect((await Favorites().toggle(corrected)).items, isEmpty);
  });
  test(
      'legacy favorite IDs migrate and concurrent additions do not overwrite each other',
      () async {
    final first = movie();
    SharedPreferences.setMockInitialValues({
      'favorites': [legacyMediaId(first)]
    });
    final migrated = await Favorites().load(known: [first]);
    expect(migrated.items.single.id, first.id);
    const otherSource = MediaSource(
        provider: 'tontons',
        sourceId: '999',
        pageUrl: 'https://filmeonlinebistrita.com/filme/other/');
    const other = MediaItem(
        id: 'other',
        title: 'Outro filme',
        description: '',
        genre: '',
        year: 2025,
        durationMinutes: 0,
        sources: [otherSource]);
    await Future.wait([Favorites().toggle(first), Favorites().toggle(other)]);
    final finalState = await Favorites().load();
    expect(finalState.items.single.id, 'other');
  });
  test(
      'explicit IDs survive cache round trip, while older records receive a fallback',
      () {
    final item = movie(id: 'anime:Nome Com Maiúsculas:0');
    expect(MediaItem.fromJson(item.toJson()).id, item.id);
    final old = item.toJson()..remove('id');
    expect(MediaItem.fromJson(old).id, legacyMediaId(item));
  });
  test('catalog uses the date instead of quality or a year in the title', () {
    final rows = LiveCatalog().parseProviderCards(
        '''<article id="post-1"><span class="quality">DUBLADO 1080p</span><div class="data"><h3><a href="https://filmesamadoresgratis.com/filme/blade/">Blade Runner 2049</a></h3><span>2017</span></div></article>''',
        'rtfilmes');
    expect(rows.single.year, 2017);
    final noDate = LiveCatalog().parseProviderCards(
        '''<article id="post-2"><h3><a href="https://filmesamadoresgratis.com/filme/blade/">Blade Runner 2049</a></h3></article>''',
        'rtfilmes');
    expect(noDate.single.year, 0);
  });
  test(
      'year corrections do not duplicate the same source and merging preserves direct playback',
      () {
    final merged =
        LiveCatalog().mergeItems([movie(year: 0), movie(year: 2026)]);
    expect(merged, hasLength(1));
    expect(merged.single.year, 2026);
    final direct = movie().copyWith(streamUrl: 'https://video.test/film.mp4');
    final restored = LiveCatalog().mergeItems([direct]).single;
    expect(restored.streamUrl, 'https://video.test/film.mp4');
    final remakes =
        LiveCatalog().mergeItems([movie(year: 1980), movie(year: 2026)]);
    expect(remakes, hasLength(2));
  });
  test('one corrupted progress entry does not stop valid playback/history',
      () async {
    SharedPreferences.setMockInitialValues({
      PersistentPlaybackGateway.key: jsonEncode({
        'bad': {'position': 'broken', 'duration': 50},
        'negative': {'position': -20, 'duration': 100},
        'valid': {'position': 12000, 'duration': 60000}
      })
    });
    final store = PersistentPlaybackGateway();
    expect(await store.loadPosition('bad'), isNull);
    expect((await store.loadContinueWatching()).single.mediaId, 'valid');
    final write = store.savePosition(const PlaybackPosition(
        mediaId: 'new',
        position: Duration(seconds: 20),
        duration: Duration(minutes: 2)));
    expect((await store.loadPosition('new'))?.position,
        const Duration(seconds: 20));
    await write;
  });
  test(
      'continue watching retains audio/player choice and skips a malformed item',
      () async {
    final item = movie();
    await ContinueWatching().save(item, source, source.pageUrl, 'playback',
        playerLabel: 'Legendado · GD');
    await PersistentPlaybackGateway().savePosition(const PlaybackPosition(
        mediaId: 'playback',
        position: Duration(minutes: 10),
        duration: Duration(minutes: 90)));
    final prefs = await SharedPreferences.getInstance();
    final rows = jsonDecode(prefs.getString(ContinueWatching.key)!) as List;
    rows.insert(0, {'playbackId': 'playback', 'item': 'invalid'});
    await prefs.setString(ContinueWatching.key, jsonEncode(rows));
    final history = await ContinueWatching().list();
    expect(history, hasLength(1));
    expect(history.single.playerLabel, 'Legendado · GD');
    expect(history.single.item.id, item.id);
  });
  test(
      'concurrent catalog notices are retained and malformed follow records are ignored',
      () async {
    final notices = CatalogNotices();
    await notices.syncCatalog([movie(id: 'baseline')]);
    await Future.wait([
      notices.syncCatalog([movie(id: 'new-a', title: 'Novo A')]),
      notices.syncCatalog([movie(id: 'new-b', title: 'Novo B')])
    ]);
    expect(await notices.events(), hasLength(2));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cineshow.notices.watch.v1', '[{"item":"broken"}]');
    expect(await notices.watched(), isEmpty);
    expect(await notices.toggle(movie(), source, []), isTrue);
    await notices.markRead();
    expect(notices.unread.value, 0);
  });
  testWidgets('My List shows a saved title that has never appeared on Home',
      (tester) async {
    await Favorites().toggle(movie());
    await tester
        .pumpWidget(MaterialApp(home: ShellPage(catalog: EmptyCatalog())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minha lista').last);
    await tester.pumpAndSettle();
    expect(find.text('Encontrado pelo ator'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('anime navigation cancels the pending text query',
      (tester) async {
    final service = FakeAnime();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AnimeCategoryView(
                onOpen: (_, episode) async {},
                serviceFactory: (_) => service))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Naruto');
    await tester.tap(find.text('Recentes'));
    await tester.pump(const Duration(seconds: 1));
    expect(service.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('older anime responses cannot replace the latest query',
      (tester) async {
    final service = FakeAnime()..delay = true;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AnimeCategoryView(
                onOpen: (_, episode) async {},
                serviceFactory: (_) => service))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Old');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.enterText(find.byType(TextField), 'New');
    await tester.pump(const Duration(milliseconds: 450));
    service.pending['New']!.complete(
        (items: [movie(id: 'new', title: 'Resultado novo')], more: false));
    await tester.pumpAndSettle();
    service.pending['Old']!.complete(
        (items: [movie(id: 'old', title: 'Resultado antigo')], more: false));
    await tester.pumpAndSettle();
    expect(find.text('Resultado novo'), findsOneWidget);
    expect(find.text('Resultado antigo'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Android deletion failure is shown without crashing Downloads',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MediaDownloads.channel, (call) async {
      if (call.method == 'list')
        return [
          {'id': 1, 'title': 'Arquivo', 'state': 'ready'}
        ];
      if (call.method == 'remove')
        throw PlatformException(code: 'FAIL', message: 'Cannot delete');
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MediaDownloads.channel, null));
    await tester.pumpWidget(const MaterialApp(home: DownloadsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Excluir download'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível excluir o download. Tente novamente.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
