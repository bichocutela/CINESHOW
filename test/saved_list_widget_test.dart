import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/favorites.dart';
import 'package:cineshow/core/services/live_catalog.dart';
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

void main() {
  testWidgets('My List shows a saved title that has never appeared on Home',
      (tester) async {
    final item = movie();
    SharedPreferences.setMockInitialValues({
      Favorites.key: jsonEncode([item.toJson()]),
      'favorites': [item.id]
    });
    await tester
        .pumpWidget(MaterialApp(home: ShellPage(catalog: EmptyCatalog())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minha lista').last);
    await tester.pumpAndSettle();
    expect(find.text('Encontrado pelo ator'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
