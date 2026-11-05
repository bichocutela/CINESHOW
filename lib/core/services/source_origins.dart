const origins = {
  'rtfilmes': 'https://filmesamadoresgratis.com',
  'tontons': 'https://filmeonlinebistrita.com',
  'xonados': 'https://www.xonados.com',
  'novelasflix': 'https://novelasflix.lol'
};
const sourceHostAliases = {
  'novelasflix.lol': 'novelasflix',
  'filmesamadoresgratis.com': 'rtfilmes',
  'www.filmesamadoresgratis.com': 'rtfilmes',
  'filmeonlinebistrita.com': 'tontons',
  'www.filmeonlinebistrita.com': 'tontons',
  'rtfilmes.com': 'rtfilmes',
  'www.rtfilmes.com': 'rtfilmes',
  'filme-cinema.com': 'rtfilmes',
  'www.filme-cinema.com': 'rtfilmes',
  'casasdefilmes.com': 'rtfilmes',
  'www.casasdefilmes.com': 'rtfilmes',
  'tontonsfilmeurs.com': 'tontons',
  'www.tontonsfilmeurs.com': 'tontons',
  'filmevdeizle.com': 'tontons',
  'www.filmevdeizle.com': 'tontons',
};

String canonicalSourceUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !['http', 'https'].contains(uri.scheme)) return url;
  final provider = sourceHostAliases[uri.host];
  if (provider == null) return url;
  final origin = Uri.parse(origins[provider]!);
  return uri
      .replace(scheme: origin.scheme, host: origin.host, port: origin.port)
      .toString();
}
