import '../services/source_origins.dart';

class MediaSource {
  const MediaSource(
      {required this.provider,
      required this.sourceId,
      required this.pageUrl,
      this.posterUrl});
  final String provider, sourceId, pageUrl;
  final String? posterUrl;
  factory MediaSource.fromJson(Map<String, dynamic> j) => MediaSource(
      provider: j['provider'] as String,
      sourceId: j['source_id'].toString(),
      pageUrl: canonicalSourceUrl(j['page_url'] as String),
      posterUrl: j['poster_url'] as String?);
  Map<String, dynamic> toJson() => {
        'provider': provider,
        'source_id': sourceId,
        'page_url': pageUrl,
        'poster_url': posterUrl
      };
  String get label => switch (provider) {
        'rtfilmes' => 'Pobreflix',
        'tontons' => 'TopFlix',
        'xonados' => 'Xonados',
        'novelasflix' => 'Novelasflix',
        'amyflix' => 'Amyflix',
        _ => provider
      };
}

class MediaItem {
  const MediaItem(
      {required this.id,
      required this.title,
      required this.description,
      required this.genre,
      required this.year,
      required this.durationMinutes,
      this.posterUrl,
      this.audio = '',
      this.tags = const [],
      this.backdropUrl,
      this.streamUrl,
      this.streamHeaders = const {},
      this.isSeries = false,
      this.kind = 'movie',
      this.sources = const []});
  final String id, title, description, genre, kind;
  final String audio;
  final List<String> tags;
  final int year, durationMinutes;
  final String? posterUrl, backdropUrl, streamUrl;
  final Map<String, String> streamHeaders;
  final bool isSeries;
  final List<MediaSource> sources;
  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
      id:
          '${j['kind'] ?? 'movie'}:${(j['title'] as String).toLowerCase().trim()}:${j['year'] ?? 0}',
      title: j['title'] as String,
      description: (j['description'] as String?) ?? '',
      genre: (j['genre'] as String?) ?? '',
      year: (j['year'] as num?)?.toInt() ?? 0,
      durationMinutes: (j['duration_minutes'] as num?)?.toInt() ?? 0,
      streamUrl: j['stream_url'] as String?,
      streamHeaders:
          Map<String, String>.from((j['stream_headers'] as Map?) ?? {}),
      backdropUrl: j['backdrop_url'] as String?,
      posterUrl: j['poster_url'] as String?,
      audio: (j['audio'] as String?) ?? '',
      tags: ((j['tags'] as List?) ?? []).whereType<String>().toList(),
      kind: (j['kind'] as String?) ?? 'movie',
      isSeries: j['kind'] == 'series',
      sources: ((j['sources'] as List?) ?? [])
          .map((s) => MediaSource.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList());
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'genre': genre,
        'audio': audio,
        'tags': tags,
        'year': year,
        'poster_url': posterUrl,
        'stream_url': streamUrl,
        'stream_headers': streamHeaders,
        'backdrop_url': backdropUrl,
        'duration_minutes': durationMinutes,
        'kind': kind,
        'sources': sources.map((s) => s.toJson()).toList()
      };
  MediaItem copyWith(
          {String? streamUrl, String? posterUrl, String? backdropUrl}) =>
      MediaItem(
          id: id,
          title: title,
          description: description,
          audio: audio,
          tags: tags,
          genre: genre,
          year: year,
          durationMinutes: durationMinutes,
          posterUrl: posterUrl ?? this.posterUrl,
          backdropUrl: backdropUrl ?? this.backdropUrl,
          streamUrl: streamUrl ?? this.streamUrl,
          streamHeaders: streamHeaders,
          isSeries: isSeries,
          kind: kind,
          sources: sources);
  String get typeLabel => switch (kind) {
        'live' => 'Ao vivo',
        'series' => 'Série',
        'novela' => 'Novela',
        'reality' => 'Reality',
        _ => 'Filme'
      };
}
