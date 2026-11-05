import '../models/media_item.dart';
import 'anime_catalog.dart';
import 'audio_metadata.dart';
import 'live_catalog.dart';
import 'public_title_metadata.dart';

bool sameSource(MediaSource? a, MediaSource? b) =>
    a != null &&
    b != null &&
    a.provider == b.provider &&
    a.sourceId == b.sourceId;

String alternativeTitle(String title) => normalizedTitle(title.replaceAll(
    RegExp(
        r'\s*(?:[-–:]\s*)?\(?\b(?:dublado(?:\s+e\s+legendado)?|legendado|dual[ -][aá]udio)\)?\s*$',
        caseSensitive: false),
    ''));

Set<String> _names(MediaItem item) => {
      item.title,
      ...item.sources.map((s) => s.originalTitle ?? '')
    }.map(alternativeTitle).where((s) => s.isNotEmpty).toSet();
Set<String> _imdb(MediaItem item) =>
    item.sources.map((s) => s.imdbId).whereType<String>().toSet();
bool _movie(MediaItem item) => item.kind == 'movie';
bool _titleMatches(MediaItem a, MediaItem b) =>
    _names(a).intersection(_names(b)).isNotEmpty;

// Shared published IDs override translated titles. Without IDs, require the same
// title, compatible release years and movie/episodic family. Never guess a remake.
MediaItem combineAlternativeSources(
    MediaItem anchor, List<MediaItem> candidates) {
  final possible = candidates
      .where((b) => _movie(anchor) == _movie(b) && b.kind != 'live')
      .toList();
  final years = possible
      .where((b) => _titleMatches(anchor, b) && b.year > 0)
      .map((b) => b.year)
      .toSet();
  if (anchor.year > 0) years.add(anchor.year);
  final ids = _imdb(anchor);
  final sources = <MediaSource>[];
  void add(MediaItem item) {
    for (final source in item.sources) {
      final annotated = MediaSource(
          provider: source.provider,
          sourceId: source.sourceId,
          pageUrl: source.pageUrl,
          posterUrl: source.posterUrl,
          imdbId: source.imdbId,
          originalTitle: source.originalTitle,
          audio: source.audio.isNotEmpty
              ? source.audio
              : item.sources.length == 1
                  ? item.audio
                  : '',
          quality: source.quality);
      final index = sources.indexWhere((s) => sameSource(s, source));
      if (index < 0) {
        sources.add(annotated);
      } else {
        final old = sources[index];
        sources[index] = MediaSource(
            provider: old.provider,
            sourceId: old.sourceId,
            pageUrl: old.pageUrl,
            posterUrl: old.posterUrl ?? annotated.posterUrl,
            imdbId: old.imdbId ?? annotated.imdbId,
            originalTitle: old.originalTitle ?? annotated.originalTitle,
            audio: old.audio.isNotEmpty ? old.audio : annotated.audio,
            quality: old.quality.isNotEmpty ? old.quality : annotated.quality);
      }
    }
  }

  add(anchor);
  for (final b in possible) {
    final otherIds = _imdb(b);
    final sharedId = ids.intersection(otherIds).isNotEmpty;
    if (ids.isNotEmpty && otherIds.isNotEmpty && !sharedId) continue;
    final sharedSource =
        anchor.sources.any((s) => b.sources.any((v) => sameSource(s, v)));
    final compatibleYear = anchor.year > 0 && b.year > 0
        ? anchor.year == b.year
        : years.length <= 1;
    if (sharedId ||
        (compatibleYear && (sharedSource || _titleMatches(anchor, b)))) add(b);
  }
  return MediaItem(
      id: anchor.id,
      title: anchor.title,
      description: anchor.description,
      genre: anchor.genre,
      year: anchor.year,
      durationMinutes: anchor.durationMinutes,
      posterUrl: anchor.posterUrl,
      backdropUrl: anchor.backdropUrl,
      streamUrl: anchor.streamUrl,
      streamHeaders: anchor.streamHeaders,
      kind: anchor.kind,
      isSeries: anchor.isSeries,
      tags: anchor.tags,
      audio: audioLabel(sources.map((s) => s.audio).join(' ')),
      sources: sources);
}

class SourceDiscovery {
  SourceDiscovery(this.catalog);
  final LiveCatalog catalog;
  Future<MediaItem> discover(MediaItem item) async {
    final query = cleanAudioTitle(item.title)
        .replaceAll(
            RegExp(r'\s*\((?:Dublado|Legendado)\)\s*$', caseSensitive: false),
            '')
        .trim();
    Future<List<MediaItem>> safe(
        Future<List<MediaItem>> Function() task) async {
      try {
        return await task().timeout(const Duration(seconds: 30));
      } catch (_) {
        return [];
      }
    }

    final batches = await Future.wait([
      safe(() async => (await catalog.refresh(query: query)).items),
      safe(() => catalog.megaAlternatives(query)),
      if (item.kind != 'movie') ...[
        safe(
            () async => (await AnimeCatalogService().list(query: query)).items),
        safe(() async => (await AnimeCatalogService(provider: 'superflix')
                .list(query: query))
            .items),
      ]
    ]);
    return combineAlternativeSources(item, batches.expand((v) => v).toList());
  }
}
