import '../models/media_item.dart';
import 'source_origins.dart';

List<String> posterSources(MediaItem item) {
  final candidates = <String>{};
  for (final value in [
    item.posterUrl,
    ...item.sources.map((s) => s.posterUrl)
  ]) {
    if (value == null || value.isEmpty) continue;
    final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) continue;
    // Reuse the exact artwork filename already present in the provider's data.
    // Do not guess posters by title or generate arbitrary TMDB identifiers.
    if (sourceHostAliases.containsKey(uri.host) &&
        uri.path.startsWith('/wp-content/uploads/')) {
      final filename = uri.pathSegments.last;
      final match =
          RegExp(r'^([a-zA-Z0-9]{20,40})(?:-\d+x\d+)?\.(jpg|jpeg|png|webp)$')
              .firstMatch(filename);
      if (match != null) {
        candidates.add('https://image.tmdb.org/t/p/w342/${match[1]}.jpg');
        if (match[2] != 'jpg')
          candidates
              .add('https://image.tmdb.org/t/p/w342/${match[1]}.${match[2]}');
      }
    }
    candidates.add(canonicalSourceUrl(uri.toString()));
    candidates.add(uri.toString());
  }
  return candidates.toList();
}

String? catalogPoster(Map<String, String> attributes, String origin) {
  for (final key in ['data-src', 'data-lazy-src', 'data-original', 'src']) {
    final value = attributes[key];
    if (value == null || value.isEmpty || value.startsWith('data:')) continue;
    final uri = Uri.parse(origin).resolve(value);
    if (['http', 'https'].contains(uri.scheme) && uri.host.isNotEmpty)
      return canonicalSourceUrl(uri.toString());
  }
  return null;
}
