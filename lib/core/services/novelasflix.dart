import 'dart:convert';
import '../models/media_item.dart';
import 'source_html.dart';

const novelasflixOrigin = 'https://novelasflix.lol';

MediaItem? novelasflixItem(String url, String title, String? poster,
    {String description = ''}) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.origin != novelasflixOrigin ||
      !RegExp(r'^/novela/[a-z0-9-]+/?$').hasMatch(uri.path)) {
    return null;
  }
  final slug = uri.pathSegments.where((s) => s.isNotEmpty).last;
  final kind = title.startsWith('A Fazenda') ? 'reality' : 'novela';
  return MediaItem(
      id: 'novelasflix:$slug',
      title: plain(title),
      description: plain(description),
      genre: '',
      year: 0,
      durationMinutes: 0,
      kind: kind,
      posterUrl: poster,
      sources: [
        MediaSource(
            provider: 'novelasflix',
            sourceId: slug,
            pageUrl: uri.toString(),
            posterUrl: poster)
      ]);
}

List<MediaItem> parseNovelasflixCards(String html) {
  final found = <String, MediaItem>{};
  for (final block
      in RegExp(r'<article\b.*?</article>', dotAll: true).allMatches(html)) {
    final link = RegExp(r'<a\b[^>]*>').firstMatch(block[0]!);
    final title = RegExp(r'<h3[^>]*>(.*?)</h3>', dotAll: true)
        .firstMatch(block[0]!)?[1];
    final img = RegExp(r'<img\b[^>]*>').firstMatch(block[0]!);
    final image = attributes(img?[0] ?? '');
    final item = novelasflixItem(
        attributes(link?[0] ?? '')['href'] ?? '',
        title ?? image['alt'] ?? '',
        image['data-src']);
    if (item != null) found[item.id] = item;
  }
  return found.values.toList();
}

List<MediaItem> parseNovelasflixSearch(String json) {
  final raw = jsonDecode(json) as Map;
  final items = <MediaItem>[];
  for (final row in ((raw['data'] as List?) ?? []).whereType<Map>()) {
    final item = novelasflixItem('${row['url']}', '${row['title']}',
        row['poster'] as String?,
        description: row['sinopse'] as String? ?? '');
    if (item != null) items.add(item);
  }
  return items;
}

List<Map<String, dynamic>> parseNovelasflixEpisodes(String html) {
  final items = <String, Map<String, dynamic>>{};
  for (final link in RegExp(r'<a\b[^>]*href=["\x27]([^"\x27]+/episodio/[^"\x27]+)["\x27][^>]*>(.*?)</a>',
          dotAll: true)
      .allMatches(html)) {
    final uri = Uri.tryParse(link[1]!.replaceAll('&amp;', '&'));
    if (uri == null || uri.origin != novelasflixOrigin) continue;
    final numbers = RegExp(r'-(\d+)x(\d+)$').firstMatch(uri.path);
    if (numbers == null) continue;
    final season = int.parse(numbers[1]!);
    final number = int.parse(numbers[2]!);
    items[uri.toString()] = {
      'id': uri.toString(),
      'title': 'Temporada $season · Capítulo $number',
      'season': season,
      'number': number,
      'page_url': uri.toString()
    };
  }
  return items.values.toList()
    ..sort((a, b) {
      final season = (a['season'] as int).compareTo(b['season'] as int);
      return season != 0 ? season : (a['number'] as int).compareTo(b['number'] as int);
    });
}
