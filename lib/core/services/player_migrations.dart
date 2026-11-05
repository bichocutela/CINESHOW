/// Published migration notice: redeflixapi.store -> redeflixapi.bar.
/// Keep the complete player path, title ID, episode and query parameters.
String canonicalPlayerUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.userInfo.isNotEmpty) {
    return value;
  }
  if (uri.host != 'redeflixapi.store') return value;
  return uri
      .replace(scheme: 'https', host: 'redeflixapi.bar', port: 443)
      .toString();
}
