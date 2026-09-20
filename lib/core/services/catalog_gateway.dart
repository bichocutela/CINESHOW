import '../models/media_item.dart';

abstract interface class CatalogGateway {
  Future<List<MediaItem>> fetchHome();
  Future<List<MediaItem>> search(String query);
}

class InMemoryCatalogGateway implements CatalogGateway {
  const InMemoryCatalogGateway();

  static const _items = <MediaItem>[
    MediaItem(
      id: 'last-horizon',
      title: 'O último horizonte',
      description: 'Uma viagem para além do que parecia ser possível.',
      genre: 'Drama',
      year: 2026,
      durationMinutes: 118,
    ),
    MediaItem(
      id: 'silent-city',
      title: 'Cidade em silêncio',
      description: 'Um suspense urbano em que cada detalhe pode mudar tudo.',
      genre: 'Suspense',
      year: 2025,
      durationMinutes: 104,
    ),
    MediaItem(
      id: 'after-midnight',
      title: 'Depois da meia-noite',
      description: 'Uma série sobre escolhas, segredos e recomeços.',
      genre: 'Série',
      year: 2024,
      durationMinutes: 8,
      isSeries: true,
    ),
  ];

  @override
  Future<List<MediaItem>> fetchHome() async {
    return List<MediaItem>.unmodifiable(_items);
  }

  @override
  Future<List<MediaItem>> search(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return fetchHome();

    return _items
        .where(
          (item) =>
              item.title.toLowerCase().contains(normalized) ||
              item.genre.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }
}
