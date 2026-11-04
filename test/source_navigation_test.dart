import 'package:cineshow/core/services/source_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const movie = 'https://casasdefilmes.com/filme/o-fim-da-rua/';
  test('advertising redirect cannot replace the movie or become retry target',
      () {
    final policy = SourceNavigationPolicy(movie);
    expect(
        policy.allows('https://interlinecustomroofingllc.com/4/9f0a1ca56fe',
            isMainFrame: true),
        isFalse);
    expect(policy.retryUrl, movie);
    expect(policy.allows('about:blank', isMainFrame: true), isFalse);
  });
  test('third-party embedded video frame does not become the top-level page',
      () {
    final policy = SourceNavigationPolicy(movie);
    const player = 'https://player.example.org/embed/123';
    expect(policy.allows(player, isMainFrame: false), isTrue);
    expect(policy.allows(player, isMainFrame: true), isFalse);
    expect(policy.retryUrl, movie);
  });
  test('known provider migration and same-provider navigation remain available',
      () {
    final policy = SourceNavigationPolicy('https://rtfilmes.com/filme/demo/');
    expect(policy.allows(movie, isMainFrame: true), isTrue);
    expect(policy.retryUrl, movie);
    expect(
        policy.allows('https://casasdefilmes.com.evil.example/filme/demo/',
            isMainFrame: true),
        isFalse);
    expect(
        policy.allows('https://filmevdeizle.com/filme/demo/',
            isMainFrame: true),
        isFalse);
  });
  test('an unknown provider is confined to its initial origin', () {
    final policy = SourceNavigationPolicy('https://www.xonados.com/');
    expect(
        policy.allows('https://www.xonados.com/@novela/a/', isMainFrame: true),
        isTrue);
    expect(policy.allows('https://elsewhere.example/', isMainFrame: true),
        isFalse);
    expect(policy.allows('intent://download/app', isMainFrame: false), isFalse);
  });
}
