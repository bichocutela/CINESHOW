class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.description,
    required this.genre,
    required this.year,
    required this.durationMinutes,
    this.posterUrl,
    this.backdropUrl,
    this.streamUrl,
    this.isSeries = false,
  });

  final String id;
  final String title;
  final String description;
  final String genre;
  final int year;
  final int durationMinutes;
  final String? posterUrl;
  final String? backdropUrl;
  final String? streamUrl;
  final bool isSeries;

  MediaItem copyWith({
    String? streamUrl,
    String? posterUrl,
    String? backdropUrl,
  }) {
    return MediaItem(
      id: id,
      title: title,
      description: description,
      genre: genre,
      year: year,
      durationMinutes: durationMinutes,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      streamUrl: streamUrl ?? this.streamUrl,
      isSeries: isSeries,
    );
  }
}
