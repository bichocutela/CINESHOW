import 'package:cineshow/core/services/provider_embed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'embed keeps the API player in a frame without copying the source page scripts',
      () {
    final html =
        providerEmbedHtml('https://player.example/embed?id=123&lang=pt');
    expect(html, contains('<iframe'));
    expect(html, contains('id=123&amp;lang=pt'));
    expect(html, contains('allowfullscreen'));
    expect(html, isNot(contains('<script')));
  });
  test(
      'original player referer becomes the embedding base and invalid URLs are rejected',
      () {
    expect(
        providerEmbedBase('https://player.example/embed/1',
            {'Referer': 'https://source.example/'}),
        'https://source.example/');
    expect(providerEmbedBase('https://player.example/embed/1', {}),
        'https://player.example/');
    expect(() => providerEmbedHtml('javascript:alert(1)'), throwsArgumentError);
  });
}
