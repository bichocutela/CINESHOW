import 'dart:convert';
import 'package:http/http.dart' as http;
import 'source_origins.dart';

class SourceHttpException implements Exception {
  const SourceHttpException(this.status);
  final int status;
  @override
  String toString() => 'Fonte respondeu HTTP $status';
}

class SourceSession {
  SourceSession(this.origin, {http.Client? client})
      : _client = client ?? http.Client();
  final String origin;
  final http.Client _client;
  final Map<String, String> _cookies = {};
  Future<String> get(String path, {String? body}) async {
    final uri = Uri.parse(canonicalSourceUrl(
        path.startsWith('https://') ? path : '$origin$path'));
    if (uri.origin != origin) throw StateError('Origem inválida');
    final headers = <String, String>{
      'User-Agent': 'CINESHOW/0.6.1',
      if (_cookies.isNotEmpty)
        'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ')
    };
    final response = await (body == null
            ? _client.get(uri, headers: headers)
            : _client.post(uri,
                headers: {
                  ...headers,
                  'Content-Type': 'application/x-www-form-urlencoded'
                },
                body: body))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw SourceHttpException(response.statusCode);
    }
    final cookie = response.headers['set-cookie'];
    if (cookie != null) {
      for (final m
          in RegExp(r'(?:^|,\s*)([\w-]+)=([^;,]*)').allMatches(cookie)) {
        _cookies[m[1]!] = m[2]!;
      }
    }
    return utf8.decode(response.bodyBytes);
  }

  void close() => _client.close();
}
