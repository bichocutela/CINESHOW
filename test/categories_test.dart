import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/features/player/presentation/categories_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('combina tipo e gênero sem misturar filme com série',
      (tester) async {
    const items = [
      MediaItem(
          id: 'movie',
          title: 'Filme de drama',
          description: '',
          genre: 'Drama',
          year: 2026,
          durationMinutes: 90),
      MediaItem(
          id: 'series',
          title: 'Série de drama',
          description: '',
          genre: 'Drama',
          kind: 'series',
          year: 2026,
          durationMinutes: 0),
      MediaItem(
          id: 'novel',
          title: 'Novela',
          description: '',
          genre: '',
          kind: 'novela',
          year: 0,
          durationMinutes: 0),
    ];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CategoriesPage(
                items: items, enriching: false, onOpen: (_) {}))));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Série'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Drama'));
    await tester.pump();
    expect(find.text('Série de drama'), findsOneWidget);
    expect(find.text('Filme de drama'), findsNothing);
    expect(find.text('1 títulos'), findsOneWidget);
  });
}
