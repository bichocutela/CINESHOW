import 'package:flutter/material.dart';

class EpisodePagination extends StatelessWidget {
  const EpisodePagination(
      {super.key,
      required this.total,
      required this.page,
      required this.onChanged});
  final int total, page;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final pages = (total / 100).ceil();
    if (pages <= 1)
      {
return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('$total episódios disponíveis'));
}
    final current = page.clamp(0, pages - 1).toInt();
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          IconButton(
              tooltip: '100 episódios anteriores',
              onPressed: current > 0 ? () => onChanged(current - 1) : null,
              icon: const Icon(Icons.chevron_left)),
          Expanded(
              child: DropdownButton<int>(
                  isExpanded: true,
                  value: current,
                  items: [
                    for (var p = 0; p < pages; p++)
                      DropdownMenuItem(
                          value: p,
                          child: Text(
                              'Episódios ${p * 100 + 1}–${((p + 1) * 100).clamp(0, total)}'))
                  ],
                  onChanged: (value) {
                    if (value != null) onChanged(value);
                  })),
          IconButton(
              tooltip: 'Próximos 100 episódios',
              onPressed:
                  current + 1 < pages ? () => onChanged(current + 1) : null,
              icon: const Icon(Icons.chevron_right))
        ]));
  }
}
