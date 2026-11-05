import 'package:flutter/material.dart';

class PublishedCast extends StatelessWidget {
  const PublishedCast({super.key, required this.names, required this.details, required this.onActor});
  final List<String> names;
  final List<Map> details;
  final ValueChanged<String> onActor;
  String role(String name) => details.where((v) => v['name'] == name)
      .map((v) => '${v['role'] ?? ''}').where((v) => v.isNotEmpty).toSet().join(' · ');
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Elenco · ${names.length} atores', style: const TextStyle(fontWeight: FontWeight.bold)),
    Wrap(spacing: 8, children: [
      for (final name in names.take(12)) Tooltip(message: role(name).isEmpty ? name : '$name · ${role(name)}',
        child: ActionChip(label: Text(name), onPressed: () => onActor(name)))
    ]),
    if (names.length > 12) TextButton.icon(icon: const Icon(Icons.people_outline),
      label: Text('Ver todos os ${names.length} atores'),
      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Elenco publicado nas fontes')),
        body: SafeArea(top: false, child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 24), itemCount: names.length,
          itemBuilder: (context, i) => ListTile(title: Text(names[i]),
            subtitle: role(names[i]).isEmpty ? null : Text(role(names[i])),
            trailing: const Icon(Icons.chevron_right), onTap: () => onActor(names[i]))))))
    )
  ]);
}
