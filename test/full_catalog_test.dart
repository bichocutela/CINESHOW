import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/live_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistorySession extends SourceSession {
  HistorySession() : super('https://www.xonados.com');
  int calls = 0;
  String frames(int day) =>
      '<iframe src="/ast/OnW?zy=1&amp;date=202610${day.toString().padLeft(2, '0')}&amp;y=abc"></iframe>';
  @override
  Future<String> get(String path, {String? body}) async {
    if (path == '/' || path == '/RTRT') {
      return '<script src="/ast/YwZ.js"></script>';
    }
    if (path == '/ast/YwZ.js') return "iframe.src = '/ast/FzY';";
    if (path == '/ast/FzY') return frames(30);
    if (path == '/G_sTw') return 'abc';
    if (path.startsWith('/Y_sTw')) {
      calls++;
      final day = int.parse(body!.substring(body.length - 2));
      return day <= 1
          ? ''
          : [
              for (var previous = day - 1;
                  previous >= 1 && previous >= day - 4;
                  previous--)
                frames(previous)
            ].join();
    }
    throw StateError('Unexpected path');
  }
}

class ArchiveSession extends SourceSession {
  ArchiveSession(super.origin);
  @override
  Future<String> get(String path, {String? body}) async {
    final uri = Uri.parse(path);
    final page =
        int.tryParse(RegExp(r'/page/(\d+)/').firstMatch(uri.path)?[1] ?? '') ??
            1;
    final series = uri.path.startsWith('/serie/');
    final type = series ? 'serie' : 'filme';
    final id = series ? 99 : page;
    return '<article id="post-$id"><img src="$origin/capa.jpg"><h3><a href="$origin/$type/titulo-$id/">${series ? 'Série' : 'Filme $page'}</a></h3><span>2026</span></article>'
        '${!series && page < 3 ? '<a href="$origin/filme/page/${page + 1}/">Próxima</a>' : ''}';
  }
}

class PublishedProgramSession extends SourceSession {
  PublishedProgramSession(super.origin);
  @override
  Future<String> get(String path, {String? body}) async {
    if (path == '/') return '<script src="/ast/WTyNK.js"></script>';
    if (path == '/ast/WTyNK.js') return "fetch('/ast/ZXDSX')";
    if (path == '/ast/ZXDSX') {
      return '<img data-wheel="9" data-title="Nova produção" src="https://www.xonados.com/img/nova.jpg">';
    }
    throw StateError('Unexpected path');
  }
}

void main() {
  test('paginação segue a próxima página publicada sem limite numérico', () {
    const markup =
        '''<a href="https://assistirfilmeshdonline.com/filme/page/478/">478</a>
      <a href="https://assistirfilmeshdonline.com/filme/page/479/">479</a>
      <a href="https://outro.example/filme/page/478/">link externo</a>''';
    expect(
        LiveCatalog.nextArchivePage(
            markup, 'https://rtfilmes.com/filme/page/477/', 'rtfilmes'),
        'https://assistirfilmeshdonline.com/filme/page/478/');
    expect(
        LiveCatalog.nextArchivePage(
            markup, 'https://rtfilmes.com/filme/page/479/', 'rtfilmes'),
        isNull);
  });
  test('mantém variantes de capítulos com a mesma data', () {
    final chapters = LiveCatalog.xonadosChapters(
        '<iframe src="/ast/OnW?date=20261012&amp;y=abc"></iframe><iframe src="/ast/OnW?date=20261012_2&amp;y=abc"></iframe>',
        'https://www.xonados.com');
    expect(chapters.map((item) => item['id']), ['20261012', '20261012_2']);
  });
  test('histórico percorre todos os lotes e guarda o resultado completo',
      () async {
    SharedPreferences.setMockInitialValues({});
    final session = HistorySession();
    final catalog = LiveCatalog(sessionFactory: (_) => session);
    var shown = 0;
    final episodes = await catalog.episodes(
        const MediaSource(
            provider: 'xonados',
            sourceId: '1',
            pageUrl: 'https://www.xonados.com/'),
        onBatch: (batch) => shown = batch.length);
    expect(episodes.length, 30);
    expect(shown, 30);
    expect(session.calls, greaterThan(1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cineshow.episodes.v2.xonados.1'),
        contains('20261001'));
  });
  test(
      'varredura inclui páginas posteriores e persiste a continuação até o fim',
      () async {
    SharedPreferences.setMockInitialValues({'cineshow.catalog.v1': '[]'});
    final catalog = LiveCatalog(sessionFactory: ArchiveSession.new);
    final batches = await catalog.syncFull().toList();
    expect(batches.last.complete, isTrue);
    expect(batches.last.pages, 8);
    expect(batches.last.items.map((item) => item.title).toSet(),
        {'Filme 1', 'Filme 2', 'Filme 3', 'Série'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cineshow.catalog.v1'), contains('Filme 3'));
    expect(prefs.getString('cineshow.full-catalog.cursor.v1'),
        contains('completed_at'));
  });
  test('novos IDs publicados pelo Xonados não são descartados', () async {
    SharedPreferences.setMockInitialValues({'cineshow.catalog.v1': '[]'});
    final catalog = LiveCatalog(sessionFactory: PublishedProgramSession.new);
    final result = await catalog.refresh();
    expect(result.items.single.title, 'Nova produção');
    expect(result.items.single.sources.single.sourceId, '9');
    expect(result.items.single.typeLabel, 'Programa');
  });
  test('temporadas são lidas dentro do título sem incluir sugestões laterais',
      () {
    const page =
        '<div id="seasons"><div><a href="/episodio/serie-1x1/">1</a></div><div><a href="/episodio/serie-2x1/">2</a></div></div><aside><a href="/episodio/outro-1x1/">Outro</a></aside>';
    final scope = LiveCatalog.episodeScope(page);
    expect(scope, contains('serie-2x1'));
    expect(scope, isNot(contains('outro-1x1')));
  });
}
