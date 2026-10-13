import 'package:cineshow/core/services/app_updates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compara versões numericamente e não oferece downgrade', () {
    expect(UpdateRelease.isNewer('v0.2.10', '0.2.9'), isTrue);
    expect(UpdateRelease.isNewer('v0.2.1', '0.2.1'), isFalse);
    expect(UpdateRelease.isNewer('v0.2.1', '0.3.0'), isFalse);
  });
  test('só aceita APK oficial com hash e release final completo', () {
    final asset = <String, dynamic>{
      'name': 'CINESHOW-v0.2.1.apk',
      'browser_download_url':
          'https://github.com/bichocutela/CINESHOW/releases/download/v0.2.1/CINESHOW-v0.2.1.apk',
      'digest': 'sha256:${List.filled(64, 'a').join()}',
    };
    final release = <String, dynamic>{
      'tag_name': 'v0.2.1',
      'assets': [asset]
    };
    expect(UpdateRelease.fromGitHub(release)?.version, '0.2.1');
    expect(UpdateRelease.fromGitHub({...release, 'prerelease': true}), isNull);
    expect(UpdateRelease.fromGitHub({...release, 'assets': []}), isNull);
    asset['browser_download_url'] = 'https://outro-site.example/app.apk';
    expect(UpdateRelease.fromGitHub(release), isNull);
    asset['browser_download_url'] =
        'https://github.com/bichocutela/CINESHOW/releases/download/v0.2.1/CINESHOW-v0.2.1.apk';
    asset['digest'] = null;
    expect(UpdateRelease.fromGitHub(release), isNull);
  });
}
