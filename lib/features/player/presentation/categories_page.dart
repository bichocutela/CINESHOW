import 'package:flutter/material.dart';
import '../../../core/models/media_item.dart';
import '../../../main.dart' show PosterCard;

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({
    super.key,
    required this.items,
    required this.onOpen,
    required this.enriching,
  });
  final List<MediaItem> items;
  final void Function(MediaItem) onOpen;
  final bool enriching;
  @override
  State<CategoriesPage> createState() => _CategoriesState();
}

class _CategoriesState extends State<CategoriesPage> {
  String type = 'Todos', genre = 'Todos';
  String query = '';
  @override
  Widget build(BuildContext context) {
    final typed = widget.items
        .where((item) => type == 'Todos' || item.typeLabel == type)
        .toList();
    final genres = typed.expand((item) => item.genres).toSet().toList()..sort();
    final selected = genre == 'Sem gênero informado' || genres.contains(genre)
        ? genre
        : 'Todos';
    final visible = typed
        .where(
          (item) =>
              (selected == 'Todos' ||
                  selected == 'Sem gênero informado' && item.genres.isEmpty ||
                  item.genres.contains(selected)) &&
              item.title.toLowerCase().contains(query.toLowerCase()),
        )
        .toList()
      ..sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Categorias',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: const InputDecoration(
                hintText: 'Buscar nesta categoria',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final value in [
                  'Todos',
                  'Filme',
                  'Série',
                  'Novela',
                  'Reality',
                  'Programa',
                ])
                  ChoiceChip(
                    label: Text(value),
                    selected: type == value,
                    onSelected: (_) => setState(() {
                      type = value;
                      genre = 'Todos';
                    }),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final value in [
                  'Todos',
                  ...genres,
                  if (typed.any((item) => item.genres.isEmpty))
                    'Sem gênero informado',
                ])
                  FilterChip(
                    label: Text(value),
                    selected: selected == value,
                    onSelected: (_) => setState(() => genre = value),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${visible.length} títulos${widget.enriching ? ' · Buscando gêneros e capas nas fontes...' : ''}',
            ),
          ),
        ),
        if (visible.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhum título nesta categoria.'),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) => PosterCard(
                item: visible[index],
                onOpen: () => widget.onOpen(visible[index]),
              ),
              childCount: visible.length,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              childAspectRatio: .58,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
          ),
        ),
      ],
    );
  }
}
