import 'package:flutter/services.dart';

class UpdateRelease {
  const UpdateRelease(this.version, this.url, this.sha256);
  final String version;
  final String url;
  final String sha256;

  static bool isNewer(String candidate, String installed) {
    List<int> parts(String version) => version
        .replaceFirst(RegExp(r'^v'), '')
        .split('+').first.split('.').map(int.parse).toList();
    final a = parts(candidate), b = parts(installed);
    for (var i = 0; i < 3; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left > right;
    }
    return false;
  }

  static UpdateRelease? fromGitHub(Map<String, dynamic> release) {
    final tag = release['tag_name'] as String? ?? '';
    if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag) ||
        release['draft'] == true || release['prerelease'] == true) return null;
    for (final asset in (release['assets'] as List? ?? [])) {
      if (asset['name'] != 'CINESHOW-$tag.apk') continue;
      final url = asset['browser_download_url'] as String? ?? '';
      final digest = asset['digest'] as String? ?? '';
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https' || uri.host != 'github.com' ||
          uri.path != '/bichocutela/CINESHOW/releases/download/$tag/CINESHOW-$tag.apk' ||
          !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(digest)) return null;
      return UpdateRelease(tag.substring(1), url, digest.substring(7));
    }
    return null;
  }
}

class AppUpdates {
  static const _channel = MethodChannel('cineshow/updates');
  Future<void> start(UpdateRelease release) => _channel.invokeMethod<void>(
      'start', {'url': release.url, 'version': release.version, 'sha256': release.sha256});
  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
      await _channel.invokeMapMethod<String, dynamic>('status') ?? {});
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
  Future<String> install() async =>
      await _channel.invokeMethod<String>('install') ?? 'installer';
}
