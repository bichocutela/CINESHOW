import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/alternative_sources.dart';
import 'package:cineshow/core/services/live_catalog.dart';
import 'package:cineshow/main.dart';

class EmptyCatalog extends LiveCatalog {
  @override
  Future<List<Map<String, dynamic>>> episodes(MediaSource source) async => [];
  @override
  Future<List<MediaItem>> cached() async => [];
  @override
  Future<CatalogResult> refresh({String? query}) async =>
      const CatalogResult([], []);
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
  testWidgets(
      'details discovers alternate sources without a previous catalog visit',
      (tester) async {
    final item = daima('animesonlinecc', audio: 'Legendado');
    SharedPreferences.setMockInitialValues({
      'cineshow.titleinfo.v3:animesonlinecc:daima:${item.id}': jsonEncode({
        'at': DateTime.now().toIso8601String(),
        'data': {'plot': 'Sinopse de teste', 'title': item.title, 'year': 0}
      })
    });
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
}
