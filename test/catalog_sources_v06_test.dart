import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cineshow/core/services/superflix_catalog.dart';
import 'package:cineshow/core/services/mega_catalog.dart';
import 'package:cineshow/core/services/anime_catalog.dart';
import 'package:cineshow/core/services/title_information.dart';
import 'package:cineshow/core/services/chapter_queue.dart';
import 'package:cineshow/features/player/widgets/episode_pagination.dart';

void main() {
  test('SuperFlix reads published title/embed fields and keeps anime type', () {
    final url = base64Encode(utf8.encode('https://superflixapi.fun/serie/123'));
    final title = base64Encode(utf8.encode('Anime de exemplo'));
    final rows = parseSuperflixCards('<div x-data="{ open: false }"><img src="https://image.tmdb.org/t/p/w500/a.jpg"><span>2024</span><h3>Example</h3><button data-embed="$url" data-title="$title"></button></div>', kind: 'anime');
    expect(rows.single.title, 'Anime de exemplo');
    expect(rows.single.kind, 'anime');
    expect(rows.single.year, 2024);
    expect(rows.single.sources.single.provider, 'superflix');
    expect(parseSuperflixCards('<div>tt1234567</div>'), isEmpty);
  });
  test('catalog pagination does not mistake page 20 for page 2', () {
    expect(hasCatalogNextPage('<a href="?page=20">20</a>', 1), isFalse);
    expect(hasCatalogNextPage('<a href="?page=2&amp;sort=recent">2</a>', 1), isTrue);
    expect(hasCatalogNextPage('<a href="?paged=2">2</a>', 1), isTrue);
  });
  test('Mega cards resolve cached posters and preserve year', () {
    final rows = parseMegaCards("""<article class="anx-card"><a href="/filme/exemplo" aria-label="Exemplo"><span style="background-image:url('/poster-cache.php?s=w500&amp;p=a.jpg')"></span><small>Filme • 2026</small></a></article>""");
    expect(rows.single.title, 'Exemplo');
    expect(rows.single.year, 2026);
    expect(rows.single.posterUrl, 'https://megafilmeshd1.com/poster-cache.php?s=w500&p=a.jpg');
  });
  test('Mega episode query keeps each season and episode distinct', () {
    final rows = parseMegaEpisodes("""<button class="aw-episode-btn" data-src="/player.php?type=serie&amp;id=5920&amp;season=1&amp;episode=2"></button><button class="aw-episode-btn" data-src="/player.php?type=serie&amp;id=5920&amp;season=1&amp;episode=1"></button>""");
    expect(rows.length, 2);
    expect(rows.first['number'], 1);
    expect(orderedChapters(rows).length, 2);
    expect(nextChapter(rows, rows.first['page_url'] as String)?['number'], 2);
  });
  test('Anime relative cards and episode blocks include the final chapter', () {
    final cards = parseAnimeCards('<article><a href="/anime/naruto/"><img src="/poster.jpg"><h3>Naruto</h3></a></article>');
    expect(cards.single.sources.single.pageUrl, 'https://animesonlinecc.to/anime/naruto/');
    final html = '<ul class="episodios">${List.generate(250, (n) => '<li>Ep - ${n + 1}<div class="episodiotitle"><a href="/episodio/naruto-${n + 1}/">Episódio ${n + 1}</a></div></li>').join()}</ul>';
    final rows = parseAnimeEpisodes(html);
    expect(rows.length, 250);
    expect(episodeBlock(rows, 0).length, 100);
    expect(episodeBlock(rows, 1).length, 100);
    expect(episodeBlock(rows, 2).last['number'], 250);
    expect(episodeBlock(rows, 2).length, 50);
    expect(episodeBlock(rows, -1), isEmpty);
  });
  test('source synopsis excludes SEO and IMDb ID must be unambiguous', () {
    expect(sourceSynopsis('<meta name="description" content="Uma história com mais de trinta caracteres para descrever o filme.">'), contains('Uma história'));
    expect(sourceImdbId('<iframe src="https://player.test/tt28534120"></iframe>'), 'tt28534120');
    expect(sourceImdbId('<a href="/tt28534120">A</a><a href="/tt12345678">B</a>'), isNull);
    expect(sourceSynopsis('<div class="wp-content"><p>Uma história com mais de trinta caracteres para descrever o filme.</p><p>Onde assistir este filme online de graça com qualidade?</p></div>'), isNot(contains('Onde assistir')));
  });
  testWidgets('phone safe area permits scrolling to chapter 250', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var page = 0;
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(360, 640), padding: EdgeInsets.only(bottom: 48)),
      child: Scaffold(body: StatefulBuilder(builder: (context, update) => SafeArea(
        child: ListView(children: [
          EpisodePagination(total: 250, page: page, onChanged: (v) => update(() => page = v)),
          for (final n in episodeBlock(List.generate(250, (n) => n + 1), page))
            ListTile(title: Text('Capítulo $n')),
          const SizedBox(height: 32)
        ])))))));
    await tester.tap(find.byTooltip('Próximos 100 episódios'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Próximos 100 episódios'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Capítulo 250'), 400);
    expect(find.text('Capítulo 250'), findsOneWidget);
    expect(tester.getBottomRight(find.text('Capítulo 250')).dy, lessThan(592));
    expect(tester.takeException(), isNull);
  });
}
