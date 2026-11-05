String plain(String s) => s
    .replaceAll(RegExp('<[^>]+>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&#8211;', '–')
    .replaceAll('&#8217;', '’')
    .replaceAll('&#039;', "'")
    .trim();
Map<String, String> attributes(String s) => {
      for (final m in RegExp(r'''([\w-]+)\s*=\s*(["'])(.*?)\2''', dotAll: true)
          .allMatches(s))
        m[1]!: m[3]!.replaceAll('&amp;', '&')
    };
