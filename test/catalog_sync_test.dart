import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/catalog_notices.dart';
import 'package:cineshow/core/services/live_catalog.dart';

class FakeSession extends SourceSession {
  FakeSession(super.origin, this.requests, this.fail);
  final List<String> requests;
  final bool Function(String) fail;
  @override
  Future<String> get(String path, {String? body}) async {
    final key = '$origin$path';
    requests.add(key);
    if (fail(key)) throw StateError('Temporary failure');
    final page = path.contains('/page/2/') ? 2 : 1;
    return '''<article id="post-$page"><img src="https://cdn.example/poster.jpg"><h3><a href="$origin/filme/title-$page/">Título $page</a></h3><span>2026</span></article>
${page == 1 ? '<a href="$origin/filme/page/2/">Próxima</a>' : ''}''';
  }
}

void main() {
  test('pagination retries failed source page without skipping it', () async {
    final requests = <String>[];
    var first = true;
    final catalog = LiveCatalog(
        sessionFactory: (origin) => FakeSession(origin, requests, (key) {
              if (origin.contains('filmeonlinebistrita') && first) {
                first = false;
                return true;
              }
              return false;
            }));
    final one = await catalog.more(kind: 'movie');
    expect(one.items, hasLength(1));
    expect(one.errors, isNotEmpty);
    await catalog.more(kind: 'movie');
    final three = await catalog.more(kind: 'movie');
    expect(three.hasMore, isFalse);
    expect(three.items, hasLength(2));
    expect(three.items.first.sources, hasLength(3));
    expect(requests.where((r) => r == 'https://filmeonlinebistrita.com/filme/'),
        hasLength(2));
  });

  test('notices baseline is silent, new title and chapter have details',
      () async {
    SharedPreferences.setMockInitialValues({});
    final notices = CatalogNotices();
    const source = MediaSource(
        provider: 'xonados',
        sourceId: '5',
        pageUrl: 'https://www.xonados.com/');
    const item = MediaItem(
        id: 'novela:quem ama cuida:0',
        title: 'Quem Ama Cuida',
        description: '',
        genre: '',
        year: 0,
        durationMinutes: 0,
        kind: 'novela',
        sources: [source]);
    await notices.syncCatalog([item]);
    expect(await notices.events(), isEmpty);
    await notices.toggle(item, source, [
      {'id': '20261104', 'title': '04/11/2026'}
    ]);
    await notices.syncChapters(item, source, [
      {'id': '20261104', 'title': '04/11/2026'},
      {'id': '20261105', 'title': '05/11/2026'}
    ]);
    final events = await notices.events();
    expect(events, hasLength(1));
    expect(events.single['title'], 'Quem Ama Cuida');
    expect(events.single['body'], 'Xonados · 05/11/2026');
    await notices.syncChapters(item, source, [
      {'id': '20261105', 'title': '05/11/2026'}
    ]);
    expect(await notices.events(), hasLength(1));
    await notices.markRead();
    expect(notices.unread.value, 0);
  });
}
