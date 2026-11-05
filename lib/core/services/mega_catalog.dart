import '../models/media_item.dart';
import 'source_html.dart';
import 'audio_metadata.dart';

const megaOrigin = 'https://megafilmeshd1.com';

List<MediaItem> parseMegaCards(String html) {
  final result = <String, MediaItem>{};
  for (final block
      in RegExp(r'<article\b.*?</article>', dotAll: true).allMatches(html)) {
    final value = block[0]!;
    final className = attributes(value.split('>').first)['class'] ?? '';
    if (!className.contains('anx-card') && !className.contains('browse-card'))
      continue;
    final a = RegExp(r'<a\b[^>]*>').firstMatch(value);
    final attr = attributes(a?[0] ?? '');
    final raw = attr['href'];
    if (raw == null) continue;
    final uri = Uri.parse('$megaOrigin/').resolve(raw);
    final match = RegExp(r'^/(filme|serie|novela|dorama|anime)/([^/]+)/?$')
        .firstMatch(uri.path);
    if (uri.origin != megaOrigin || match == null) continue;
    final title = attr['aria-label'] ??
        RegExp(r'<h3[^>]*>(.*?)</h3>', dotAll: true).firstMatch(value)?[1] ??
        RegExp(r'<b[^>]*>(.*?)</b>', dotAll: true).firstMatch(value)?[1];
    if (title == null || plain(title).isEmpty) continue;
    final img = attributes(RegExp(r'<img\b[^>]*>').firstMatch(value)?[0] ?? '');
    final background = RegExp(r'''background-image:\s*url\(['"]?(.*?)['"]?\)''')
        .firstMatch(value)?[1];
    final poster = img['data-src'] ?? img['src'] ?? background;
    final meta = RegExp(r'<small[^>]*>(.*?)</small>', dotAll: true)
            .firstMatch(value)?[1] ??
        RegExp(r'''<(?:div|span)[^>]+class=["'][^"']*(?:card-meta|card-year)[^"']*["'][^>]*>(.*?)</(?:div|span)>''',
                dotAll: true)
            .firstMatch(value)?[1] ??
        '';
    final year = RegExp(r'\b(?:19|20)\d{2}\b').firstMatch(plain(meta))?[0];
    final kind = switch (match[1]) {
      'filme' => 'movie',
      'novela' => 'novela',
      'anime' => 'anime',
      _ => 'series'
    };
    final picture = poster == null
        ? null
        : Uri.parse('$megaOrigin/')
            .resolve(poster.replaceAll('&amp;', '&'))
            .toString();
    result[uri.toString()] = MediaItem(
        id: 'megafilmes:${match[2]}',
        title: plain(title),
        description: '',
        genre: match[1] == 'dorama' ? 'Dorama' : '',
        year: int.tryParse(year ?? '') ?? 0,
        durationMinutes: 0,
        kind: kind,
        isSeries: kind != 'movie',
        audio: catalogAudio(value),
        posterUrl: picture,
        sources: [
          MediaSource(
              provider: 'megafilmes',
              sourceId: match[2]!,
              pageUrl: uri.toString(),
              posterUrl: picture)
        ]);
  }
  return result.values.toList();
}

List<Map<String, dynamic>> parseMegaEpisodes(String html) {
  final items = <String, Map<String, dynamic>>{};
  for (final button in RegExp(r'<button\b[^>]*>').allMatches(html)) {
    final data = attributes(button[0]!);
    if (!(data['class'] ?? '').contains('aw-episode-btn')) continue;
    final url = data['data-src'];
    if (url == null) continue;
    final uri = Uri.parse('$megaOrigin/').resolve(url);
    if (uri.origin != megaOrigin || uri.path != '/player.php') continue;
    final season = int.tryParse(uri.queryParameters['season'] ?? '');
    final number = int.tryParse(uri.queryParameters['episode'] ?? '');
    if (season == null || number == null) continue;
    items[uri.toString()] = {
      'id': uri.toString(),
      'page_url': uri.toString(),
      'title': data['data-label'] ?? 'Temporada $season · Episódio $number',
      'season': season,
      'number': number
    };
  }
  return items.values.toList()
    ..sort((a, b) {
      final season = (a['season'] as int).compareTo(b['season'] as int);
      return season != 0
          ? season
          : (a['number'] as int).compareTo(b['number'] as int);
    });
}
