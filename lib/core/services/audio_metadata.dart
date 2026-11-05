String audioLabel(String value) {
  final text = value.toLowerCase();
  final dubbed = RegExp(r'\bdublad[oa]s?\b').hasMatch(text);
  final subtitled = RegExp(r'\blegendad[oa]s?\b').hasMatch(text);
  if (dubbed && subtitled) return 'Dublado e legendado';
  if (dubbed) return 'Dublado';
  if (subtitled) return 'Legendado';
  if (RegExp(r'\bdual[\s-]+[aá]udio\b').hasMatch(text)) return 'Dual áudio';
  return '';
}

String catalogAudio(String html) {
  final tags = RegExp(
          r'''<(?:span|div)[^>]+class=["'](?:[^"']*\s)?quality(?:\s[^"']*)?["'][^>]*>(.*?)</(?:span|div)>''',
          dotAll: true)
      .allMatches(html);
  return audioLabel(
      tags.map((m) => m[1]!.replaceAll(RegExp('<[^>]+>'), '')).join(' '));
}

String cleanAudioTitle(String title) => title
    .replaceFirst(
        RegExp(r'\s*[–-]\s*(?:dublado(?:\s+e\s+legendado)?|legendado)\s*$',
            caseSensitive: false),
        '')
    .trim();
