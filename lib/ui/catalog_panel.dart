import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/catalog.dart';
import '../models/geometry.dart';
import '../state/plan_controller.dart';
import '../viewer/engine_bridge.dart';

const shapeIcons = <String, IconData>{
  'bed': Icons.bed_outlined,
  'bunk': Icons.bed_outlined,
  'sofa': Icons.weekend_outlined,
  'sofa_corner': Icons.weekend_outlined,
  'table': Icons.table_restaurant_outlined,
  'table_round': Icons.table_restaurant_outlined,
  'island': Icons.countertops_outlined,
  'chair': Icons.chair_alt_outlined,
  'stool': Icons.chair_alt_outlined,
  'wardrobe': Icons.door_sliding_outlined,
  'dresser': Icons.inventory_2_outlined,
  'shelf': Icons.shelves,
  'kitchen': Icons.kitchen_outlined,
  'stove': Icons.microwave_outlined,
  'fridge': Icons.kitchen_outlined,
  'washer': Icons.local_laundry_service_outlined,
  'tv': Icons.tv_outlined,
  'lamp': Icons.light_outlined,
  'plant': Icons.local_florist_outlined,
  'rug': Icons.texture,
  'rug_round': Icons.texture,
  'fireplace': Icons.fireplace_outlined,
  'stairs': Icons.stairs_outlined,
  'bath': Icons.bathtub_outlined,
  'shower': Icons.shower_outlined,
  'toilet': Icons.wc_outlined,
  'vanity': Icons.wash_outlined,
  'tree': Icons.park_outlined,
  'cypress': Icons.forest_outlined,
  'hedge': Icons.grass,
  'flowerbed': Icons.yard_outlined,
  'fence': Icons.fence,
  'pool': Icons.pool,
  'deck': Icons.deck_outlined,
  'path': Icons.signpost_outlined,
  'lounger': Icons.beach_access_outlined,
  'umbrella': Icons.beach_access_outlined,
  'grill': Icons.outdoor_grill_outlined,
  'trampoline': Icons.sports_gymnastics,
  'swing': Icons.child_care_outlined,
  'shed': Icons.cabin_outlined,
  'carport': Icons.garage_outlined,
  'car': Icons.directions_car_outlined,
  'box': Icons.inventory_2_outlined,
};

class CatalogPanel extends StatefulWidget {
  const CatalogPanel({super.key, required this.c, this.onPicked});
  final PlanController c;

  /// Poziva se nakon odabira (npr. zatvaranje panela na mobitelu).
  final VoidCallback? onPicked;

  @override
  State<CatalogPanel> createState() => _CatalogPanelState();
}

class _CatalogPanelState extends State<CatalogPanel> {
  CatalogZone zone = CatalogZone.interior;
  String? category;
  String query = '';

  @override
  void initState() {
    super.initState();
    Thumbnails.instance.ensure();
  }

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final items = catalog.where((i) {
      if (q.isNotEmpty) return i.name.toLowerCase().contains(q) || i.category.toLowerCase().contains(q);
      return i.zone == zone && (category == null || i.category == category);
    }).toList();
    final categories = <String>[];
    for (final i in catalog.where((i) => i.zone == zone)) {
      if (!categories.contains(i.category)) categories.add(i.category);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'Traži krevet, kadu, stablo…'),
          onChanged: (v) => setState(() => query = v),
        ),
      ),
      if (q.isEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SegmentedButton<CatalogZone>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: CatalogZone.interior, label: Text('Interijer')),
              ButtonSegment(value: CatalogZone.exterior, label: Text('Okućnica')),
            ],
            selected: {zone},
            onSelectionChanged: (s) => setState(() {
              zone = s.first;
              category = null;
            }),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            children: [
              _chip('Sve', category == null, () => setState(() => category = null)),
              for (final cat in categories) _chip(cat, category == cat, () => setState(() => category = cat)),
            ],
          ),
        ),
      ],
      Expanded(
        child: ListenableBuilder(
          listenable: Thumbnails.instance,
          builder: (context, _) => GridView.builder(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.74,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _CatalogCard(
              item: items[i],
              selected: widget.c.placing?.id == items[i].id,
              onTap: () {
                widget.c.setTool(Tool.place, item: items[i]);
                widget.onPicked?.call();
              },
            ),
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Pal.lineSoft))),
        child: Text(
          'Povuci objekt na tlocrt ili 3D prikaz, ili ga klikni pa klikni mjesto. Uz zid se sam okrene leđima prema zidu. '
          'Cijene su okvirne.',
          style: AppText.ui(size: 11.5, color: Pal.muted, height: 1.35),
        ),
      ),
    ]);
  }

  Widget _chip(String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: active ? Pal.ink : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: active ? Pal.ink : Pal.line),
            ),
            child: Text(label, style: AppText.ui(size: 12, weight: FontWeight.w500, color: active ? Colors.white : Pal.inkSoft)),
          ),
        ),
      );
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.item, required this.selected, required this.onTap});
  final CatalogItem item;
  final bool selected;
  final VoidCallback onTap;

  Widget _thumb({double size = 120}) {
    final png = Thumbnails.instance.get(item.id);
    if (png != null) return Image.memory(png, fit: BoxFit.contain, gaplessPlayback: true, filterQuality: FilterQuality.medium);
    return Center(child: Icon(shapeIcons[item.shape] ?? Icons.inventory_2_outlined, size: size * 0.3, color: Pal.muted));
  }

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? Pal.accent : Pal.lineSoft, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Container(color: const Color(0xFFF5F7F6), padding: const EdgeInsets.all(6), child: _thumb()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.ui(size: 12, weight: FontWeight.w600, height: 1.2)),
              const SizedBox(height: 3),
              Row(children: [
                Expanded(child: Text(item.dims, style: AppText.narrow(size: 10.5, color: Pal.muted), overflow: TextOverflow.ellipsis)),
                if (item.price != null) Text('≈ ${fmtEur(item.price!)}', style: AppText.narrow(size: 10.5, weight: FontWeight.w600, color: Pal.inkSoft)),
              ]),
            ]),
          ),
        ]),
      ),
    );
    return Draggable<CatalogItem>(
      data: item,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Transform.translate(
        offset: const Offset(-48, -48),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(235),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Pal.accent, width: 2),
              boxShadow: const [BoxShadow(color: Color(0x331C2226), blurRadius: 16, offset: Offset(0, 6))],
            ),
            padding: const EdgeInsets.all(8),
            child: _thumb(size: 80),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: card),
      child: card,
    );
  }
}
