class CatalogCategory {
  const CatalogCategory(this.label, this.slug);
  final String label, slug;
}

const catalogGenres = [
  CatalogCategory('Ação', 'acao'),
  CatalogCategory('Aventura', 'aventura'),
  CatalogCategory('Animação', 'animacao'),
  CatalogCategory('Comédia', 'comedia'),
  CatalogCategory('Crime', 'crime'),
  CatalogCategory('Documentário', 'documentario'),
  CatalogCategory('Drama', 'drama'),
  CatalogCategory('Família', 'familia'),
  CatalogCategory('Fantasia', 'fantasia'),
  CatalogCategory('Ficção científica', 'ficcao-cientifica'),
  CatalogCategory('Mistério', 'misterio'),
  CatalogCategory('Romance', 'romance'),
  CatalogCategory('Suspense', 'thriller'),
  CatalogCategory('Terror', 'terror'),
  CatalogCategory('LGBT+ / GL', 'amy-gl'),
];

List<CatalogCategory> categoriesForSection(String section) {
  if (section == 'Novela' || section == 'Reality') return const [];
  return [
    ...catalogGenres,
    if (section == 'Série') ...[
      const CatalogCategory('Doramas', 'melhores-doramas'),
      const CatalogCategory('Animes', 'animes')
    ]
  ];
}

String? categoryKind(String section) =>
    switch (section) { 'Filme' => 'movie', 'Série' => 'series', _ => null };
