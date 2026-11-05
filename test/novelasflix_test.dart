import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cineshow/core/services/novelasflix.dart';
import 'package:cineshow/core/services/catalog_categories.dart';

void main() {
  test('Novelasflix search keeps exact URL and artwork supplied by API', () {
    final items = parseNovelasflixSearch(jsonEncode({
      'response': true,
      'data': [
        {
          'title': 'Quem Ama Cuida',
          'url': 'https://novelasflix.lol/novela/quem-ama-cuida',
          'poster':
              'https://novelascdn.link/content/series/posters/180/233.webp',
          'sinopse': 'Descrição'
        }
      ]
    }));
    expect(items.single.title, 'Quem Ama Cuida');
    expect(items.single.year, 0);
    expect(items.single.sources.single.label, 'Novelasflix');
    expect(items.single.posterUrl, contains('/233.webp'));
    expect(novelasflixItem('https://ad.example/novela/fake', 'fake', null),
        isNull);
  });
  test(
      'Novelasflix lazy images are parsed and chapters sorted without duplicates',
      () {
    final cards = parseNovelasflixCards(
        '''<article><a href="https://novelasflix.lol/novela/alem-do-tempo"><img src="data:placeholder" data-src="https://cdn.example/10.webp"><h3>Além do Tempo</h3></a></article>''');
    expect(cards.single.posterUrl, 'https://cdn.example/10.webp');
    final episodes = parseNovelasflixEpisodes(
        '''<a href="https://novelasflix.lol/episodio/quem-ama-cuida-1x2">2</a><a href="https://novelasflix.lol/episodio/quem-ama-cuida-1x1">1</a><a href="https://novelasflix.lol/episodio/quem-ama-cuida-1x1">1</a><a href="https://ad.example/episodio/quem-ama-cuida-1x3">3</a>''');
    expect(episodes.map((e) => e['number']), [1, 2]);
  });
  test('section categories keep type filters and series-specific choices', () {
    expect(categoryKind('Filme'), 'movie');
    expect(categoryKind('Série'), 'series');
    expect(
        categoriesForSection('Série').any((c) => c.label == 'Doramas'), isTrue);
    expect(categoriesForSection('Filme').any((c) => c.label == 'Doramas'),
        isFalse);
    expect(categoriesForSection('Novela'), isEmpty);
  });
}
