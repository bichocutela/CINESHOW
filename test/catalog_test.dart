import 'package:cineshow/core/models/media_item.dart';
import 'package:cineshow/core/services/live_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fontes sobrevivem ao cache JSON', () {
    final item = MediaItem.fromJson({
      'id': '1',
      'title': 'Demo',
      'kind': 'novela',
      'year': 0,
      'sources': [
        {
          'provider': 'xonados',
          'source_id': '5',
          'page_url': 'https://www.xonados.com/'
        }
      ]
    });
    final restored = MediaItem.fromJson(item.toJson());
    expect(restored.sources.single.sourceId, '5');
    expect(restored.typeLabel, 'Novela');
  });
  test('atributos aceitam aspas simples e escapam query string', () {
    expect(
        attributes("<iframe src='/ast/OnW/?zy=1&amp;date=20261012_1'>")['src'],
        '/ast/OnW/?zy=1&date=20261012_1');
  });
}
