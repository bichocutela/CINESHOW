import 'package:cineshow/core/services/video_sources.dart';
import 'package:cineshow/core/services/catalog_metadata.dart';
import 'package:cineshow/core/models/media_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seleciona apenas opções reais de vídeo e rejeita IDs malformados', () {
    final options = VideoSources.selections('''
      <li data-post="123" data-type="movie" data-nume="trailer">
      <li data-post="123" data-type="movie" data-nume="1">
      <li data-post="123" data-type="movie" data-nume="1">
      <li data-post="../admin" data-type="movie" data-nume="2">
    ''');
    expect(options, [
      {'post': '123', 'type': 'movie', 'source': '1'}
    ]);
    expect(VideoSources.safeUrl('javascript:alert(1)', 'https://rtfilmes.com/'),
        isNull);
    expect(
        VideoSources.safeUrl(
            'http://example.com/video', 'https://rtfilmes.com/'),
        isNull);
    expect(
        VideoSources.safeUrl(
            '/player?id=1&amp;source=2', 'https://rtfilmes.com/'),
        'https://rtfilmes.com/player?id=1&source=2');
  });
  test('gêneros vêm do título e não das categorias do menu ou anúncios', () {
    final metadata = CatalogMetadata.parse('''
      <a href="/melhores/acao">Ação</a>
      <meta property="og:image" content="https://example.com/anuncio.jpg">
      <div class="poster"><img src="/filme.jpg"></div>
      <div class="sgeneros"><a>BK Filmes Stream</a><a>Crime</a><a>Suspense</a></div>
    ''', 'https://rtfilmes.com/filme/titulo');
    expect(metadata['genre'], 'Crime, Suspense');
    expect(metadata['poster_url'], 'https://rtfilmes.com/filme.jpg');
  });
  test('metadados de novela usam a capa publicada na própria página', () {
    expect(
        CatalogMetadata.parse(
            '<meta property="og:image" content="/img/novela.jpg">',
            'https://www.xonados.com/@novela/avenida-brasil-1/')['poster_url'],
        'https://www.xonados.com/img/novela.jpg');
  });
  test('cache preserva gêneros e suas categorias não se duplicam', () {
    const item = MediaItem(
        id: 'x',
        title: 'Filme',
        description: '',
        genre: 'Drama, Ação, Drama',
        year: 2026,
        durationMinutes: 90);
    expect(MediaItem.fromJson(item.toJson()).genres, ['Ação', 'Drama']);
    expect(item.copyWith(posterUrl: 'https://example.com/capa.jpg').genre,
        item.genre);
  });
}
