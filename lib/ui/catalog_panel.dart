import 'package:flutter/material.dart';

import '../models/catalog.dart';
import '../state/plan_controller.dart';

const shapeIcons = <String, IconData>{
  'bed': Icons.bed,
  'sofa': Icons.weekend,
  'table': Icons.table_restaurant,
  'chair': Icons.chair_alt,
  'wardrobe': Icons.door_sliding,
  'shelf': Icons.shelves,
  'kitchen': Icons.kitchen,
  'tv': Icons.tv,
  'lamp': Icons.light,
  'plant': Icons.local_florist,
  'rug': Icons.texture,
  'bath': Icons.bathtub,
  'shower': Icons.shower,
  'toilet': Icons.wc,
  'tree': Icons.park,
  'hedge': Icons.grass,
  'fence': Icons.fence,
  'pool': Icons.pool,
  'deck': Icons.deck,
  'lounger': Icons.beach_access,
  'umbrella': Icons.beach_access,
  'car': Icons.directions_car,
  'box': Icons.inventory_2,
};

class CatalogPanel extends StatefulWidget {
  const CatalogPanel({super.key, required this.c});
  final PlanController c;

  @override
  State<CatalogPanel> createState() => _CatalogPanelState();
}

class _CatalogPanelState extends State<CatalogPanel> {
  CatalogZone zone = CatalogZone.interior;
  String query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = catalog
        .where((i) => i.zone == zone)
        .where((i) => query.isEmpty || i.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    final categories = <String>[];
    for (final i in items) {
      if (!categories.contains(i.category)) categories.add(i.category);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Text('Katalog', style: theme.textTheme.titleMedium),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SegmentedButton<CatalogZone>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: CatalogZone.interior, icon: Icon(Icons.chair), label: Text('Interijer')),
            ButtonSegment(value: CatalogZone.exterior, icon: Icon(Icons.park), label: Text('Eksterijer')),
          ],
          selected: {zone},
          onSelectionChanged: (s) => setState(() => zone = s.first),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 20),
            hintText: 'Traži…',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            for (final cat in categories) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(cat.toUpperCase(),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.primary, letterSpacing: 0.8)),
              ),
              for (final it in items.where((i) => i.category == cat))
                ListTile(
                  dense: true,
                  selected: widget.c.placing?.id == it.id,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(it.color).withAlpha(70),
                    child: Icon(shapeIcons[it.shape] ?? Icons.inventory_2,
                        size: 18, color: theme.colorScheme.onSurface),
                  ),
                  title: Text(it.name),
                  subtitle: Text(it.retailer == null ? it.dims : '${it.retailer} · ${it.dims}'),
                  onTap: () => widget.c.setTool(Tool.place, item: it),
                ),
            ],
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.all(10),
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        child: Text(
          'Klikni objekt pa klikni na tlocrt. Proizvodi trgovaca (IKEA, JYSK, Emmezeta…) '
          'dodaju se kroz partnerske kataloge.',
          style: theme.textTheme.bodySmall,
        ),
      ),
    ]);
  }
}
