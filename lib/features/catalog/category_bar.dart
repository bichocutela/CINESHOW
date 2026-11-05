import 'package:flutter/material.dart';
import '../../core/services/catalog_categories.dart';

class CategoryBar extends StatelessWidget {
  const CategoryBar({super.key, required this.section, required this.selected,
      required this.onSelected});
  final String section;
  final CatalogCategory? selected;
  final ValueChanged<CatalogCategory?> onSelected;
  @override
  Widget build(BuildContext context) {
    final categories = categoriesForSection(section);
    if (categories.isEmpty) return const SizedBox.shrink();
    return Semantics(label: 'Categorias de $section',
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SingleChildScrollView(scrollDirection: Axis.horizontal,
            child: Row(children: [
              Padding(padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: const Text('Todas as categorias'),
                  selected: selected == null, onSelected: (_) => onSelected(null))),
              for (final category in categories)
                Padding(padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(category.label),
                    selected: selected?.slug == category.slug,
                    onSelected: (_) => onSelected(category)))
            ]))));
  }
}
