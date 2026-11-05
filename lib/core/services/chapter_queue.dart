String chapterUrl(Map<String, dynamic> chapter) =>
    (chapter['page_url'] as String?) ?? (chapter['player_path'] as String?) ?? '';

String chapterIdentity(String url) {
  final uri = Uri.parse(url);
  return uri.queryParameters['date']?.split('_').first ?? uri.path;
}

List<Map<String, dynamic>> orderedChapters(List<Map<String, dynamic>> chapters) {
  final unique = <String, Map<String, dynamic>>{};
  for (final chapter in chapters) {
    final url = chapterUrl(chapter);
    if (url.isEmpty) continue;
    final key = chapterIdentity(url);
    final prior = unique[key];
    if (prior == null ||
        (Uri.parse(url).queryParameters['date']?.contains('_') == false)) {
      unique[key] = chapter;
    }
  }
  (int, int, String) order(Map<String, dynamic> value) {
    final uri = Uri.parse(chapterUrl(value));
    final numbers = RegExp(r'-(\d+)x(\d+)/?$').firstMatch(uri.path);
    if (numbers != null) return (int.parse(numbers[1]!), int.parse(numbers[2]!), '');
    return (0, 0, chapterIdentity(chapterUrl(value)));
  }
  return unique.values.toList()..sort((a, b) {
    final x = order(a), y = order(b);
    final season = x.$1.compareTo(y.$1);
    if (season != 0) return season;
    final number = x.$2.compareTo(y.$2);
    return number != 0 ? number : x.$3.compareTo(y.$3);
  });
}

Map<String, dynamic>? nextChapter(
    List<Map<String, dynamic>> chapters, String currentUrl) {
  final ordered = orderedChapters(chapters);
  final current = chapterIdentity(currentUrl);
  final index = ordered.indexWhere((c) => chapterIdentity(chapterUrl(c)) == current);
  return index >= 0 && index + 1 < ordered.length ? ordered[index + 1] : null;
}
