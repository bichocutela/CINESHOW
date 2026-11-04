import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/poster_sources.dart';
import 'package:cineshow/core/services/source_origins.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses exact provider artwork ID and retains original fallback', () {
    const url =
        'https://rtfilmes.com/wp-content/uploads/2026/10/62vtHEyzKhFRuEOLLiQfPi60mSs-185x278.jpg';
    const item = MediaItem(
        id: '1',
        title: 'Test',
        description: '',
        genre: '',
        year: 2026,
        durationMinutes: 0,
        posterUrl: url);
    final sources = posterSources(item);
    expect(sources.first,
        'https://image.tmdb.org/t/p/w342/62vtHEyzKhFRuEOLLiQfPi60mSs.jpg');
    expect(sources, contains(url));
    expect(
        sources,
        contains(
            'https://filmesamadoresgratis.com/wp-content/uploads/2026/10/62vtHEyzKhFRuEOLLiQfPi60mSs-185x278.jpg'));
  });
  test('does not guess a TMDB ID from arbitrary images', () {
    const item = MediaItem(
        id: '1',
        title: 'Test',
        description: '',
        genre: '',
        year: 0,
        durationMinutes: 0,
        posterUrl: 'https://example.org/my-poster.jpg');
    expect(posterSources(item), ['https://example.org/my-poster.jpg']);
  });
  test('lazy and relative images are resolved against the catalog origin', () {
    expect(
        catalogPoster(
            {'src': 'data:image/gif;base64,x', 'data-lazy-src': '/cover.jpg'},
            'https://example.org'),
        'https://example.org/cover.jpg');
  });
  test('cached source posters and canonical provider URL survive round trip',
      () {
    final source = MediaSource.fromJson({
      'provider': 'rtfilmes',
      'source_id': '1',
      'page_url': 'https://rtfilmes.com/filme/a/',
      'poster_url': 'https://example.org/cover.jpg'
    });
    final restored = MediaSource.fromJson(source.toJson());
    expect(restored.pageUrl, 'https://filmesamadoresgratis.com/filme/a/');
    expect(restored.posterUrl, 'https://example.org/cover.jpg');
    expect(canonicalSourceUrl('https://unrelated.example/path'),
        'https://unrelated.example/path');
  });
}
