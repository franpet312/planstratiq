import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../app/theme.dart';
import '../models/catalog.dart';
import '../models/catalog_gen.dart';
import '../models/geometry.dart';
import '../state/imported_catalog.dart';
import '../state/retail_catalog.dart';
import '../state/plan_controller.dart';
import '../viewer/engine_bridge.dart';
import 'web_files.dart';

const shapeIcons = <String, IconData>{
  'bed': Icons.bed_outlined,
  'bunk': Icons.bed_outlined,
  'crib': Icons.crib_outlined,
  'sofa': Icons.weekend_outlined,
  'sofa_corner': Icons.weekend_outlined,
  'pouf': Icons.event_seat_outlined,
  'bench': Icons.event_seat_outlined,
  'table': Icons.table_restaurant_outlined,
  'table_round': Icons.table_restaurant_outlined,
  'island': Icons.countertops_outlined,
  'chair': Icons.chair_alt_outlined,
  'stool': Icons.chair_alt_outlined,
  'wardrobe': Icons.door_sliding_outlined,
  'dresser': Icons.inventory_2_outlined,
  'tv_stand': Icons.tv_outlined,
  'vitrine': Icons.shelves,
  'shelf': Icons.shelves,
  'kitchen': Icons.kitchen_outlined,
  'tall': Icons.kitchen_outlined,
  'stove': Icons.microwave_outlined,
  'fridge': Icons.kitchen_outlined,
  'dishwasher': Icons.local_laundry_service_outlined,
  'washer': Icons.local_laundry_service_outlined,
  'tv': Icons.tv_outlined,
  'lamp': Icons.light_outlined,
  'plant': Icons.local_florist_outlined,
  'rug': Icons.texture,
  'rug_round': Icons.texture,
  'fireplace': Icons.fireplace_outlined,
  'stairs': Icons.stairs_outlined,
  'stairs_l': Icons.stairs_outlined,
  'stairs_spiral': Icons.stairs_outlined,
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
  'balcony': Icons.balcony_outlined,
  'balcony_rail': Icons.balcony_outlined,
  'balcony_wall': Icons.balcony_outlined,
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

/// Stavka u rešetki kataloga: model s varijantama (generirani ili uvezeni proizvod).
class _Entry {
  _Entry({required this.id, required this.name, required this.category, required this.zone, required this.variants, this.style, this.retailer});
  final String id;
  final String name;
  final String category;
  final CatalogZone zone;
  final List<CatalogItem> variants;
  final Style? style;
  final String? retailer;

  CatalogItem get main {
    final m = catalogModels.where((m) => m.id == id).firstOrNull;
    return m?.main ?? variants.first;
  }

  double get minPrice => variants.map((v) => v.price ?? 0).fold(double.infinity, (a, b) => b > 0 && b < a ? b : a);
  late final String search = '${name.toLowerCase()} ${category.toLowerCase()} ${style?.name.toLowerCase() ?? ''} ${retailer?.toLowerCase() ?? ''}';
}

enum _Sort { recommended, priceUp, priceDown, name }

class CatalogPanel extends StatefulWidget {
  const CatalogPanel({super.key, required this.c, this.onPicked});
  final PlanController c;
  final VoidCallback? onPicked;

  @override
  State<CatalogPanel> createState() => _CatalogPanelState();
}

class _CatalogPanelState extends State<CatalogPanel> {
  static CatalogZone zone = CatalogZone.interior;
  static String? category;
  static String? styleId;
  /// null = sve, '__gen' = generički modeli, inače naziv trgovine
  static String? source;
  static _Sort sort = _Sort.recommended;
  String query = '';
  _Entry? open;
  int sizeIdx = 0, colorIdx = 0, legIdx = 0;
  final scroll = ScrollController();

  static final List<_Entry> _generated = [
    for (final m in catalogModels)
      _Entry(id: m.id, name: m.name, category: m.category, zone: m.zone, variants: m.variants, style: m.style),
  ];

  List<_Entry> get _all => [
        for (final m in RetailCatalog.instance.models)
          _Entry(id: m.id, name: m.name, category: m.category, zone: m.zone, variants: m.variants, retailer: m.retailer),
        ..._generated,
        for (final it in ImportedCatalog.instance.items)
          _Entry(id: it.id, name: it.name, category: it.category, zone: it.zone, variants: [it], retailer: it.retailer),
      ];

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  List<_Entry> _filtered() {
    final q = query.trim().toLowerCase();
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    var list = _all.where((e) {
      if (words.isNotEmpty) return words.every((w) => e.search.contains(w));
      if (category == '__imported') return e.retailer != null && e.id.startsWith('imp:');
      if (source == '__gen' && e.retailer != null) return false;
      if (source != null && source != '__gen' && e.retailer != source) return false;
      if (e.zone != zone) return false;
      if (category != null && e.category != category) return false;
      if (styleId != null && e.style != null && e.style!.id != styleId) return false;
      if (styleId != null && e.style == null && e.retailer == null) return false;
      return true;
    }).toList();
    switch (sort) {
      case _Sort.priceUp:
        list.sort((a, b) => a.minPrice.compareTo(b.minPrice));
      case _Sort.priceDown:
        list.sort((a, b) => b.minPrice.compareTo(a.minPrice));
      case _Sort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
      case _Sort.recommended:
        break;
    }
    return list;
  }

  void _openEntry(_Entry e) {
    final m = e.main;
    final idx = e.variants.indexOf(m);
    setState(() {
      open = e;
      final dims = _dims(e), cols = _colors(e), legs = _legs(e);
      sizeIdx = dims.indexWhere((d) => d == _dimKey(m)).clamp(0, 999);
      colorIdx = cols.indexWhere((c) => c.$1 == m.color).clamp(0, 999);
      legIdx = legs.indexOf(m.legs ?? '').clamp(0, 999);
      if (idx < 0) sizeIdx = colorIdx = legIdx = 0;
    });
  }

  // varijante modela
  static String _dimKey(CatalogItem v) => '${v.w}|${v.d}|${v.h}';
  List<String> _dims(_Entry e) => {for (final v in e.variants) _dimKey(v)}.toList();
  List<(int, String)> _colors(_Entry e) {
    final seen = <int>{};
    final out = <(int, String)>[];
    for (final v in e.variants) {
      if (seen.add(v.color)) {
        final parts = (v.variant ?? '').split(' · ').first.split(', ');
        out.add((v.color, parts.length > 1 ? parts.sublist(1).join(', ') : ''));
      }
    }
    return out;
  }

  List<String> _legs(_Entry e) => {for (final v in e.variants) v.legs ?? ''}.toList();

  CatalogItem _current(_Entry e) {
    final dims = _dims(e), cols = _colors(e), legs = _legs(e);
    final dk = dims[sizeIdx.clamp(0, dims.length - 1)];
    final col = cols[colorIdx.clamp(0, cols.length - 1)].$1;
    final lg = legs[legIdx.clamp(0, legs.length - 1)];
    return e.variants.firstWhere((v) => _dimKey(v) == dk && v.color == col && (v.legs ?? '') == lg, orElse: () => e.variants.first);
  }

  Future<void> _import() async {
    final f = await pickFile('.csv,.json,text/csv,application/json');
    if (f == null) return;
    String text;
    try {
      text = const Utf8Decoder(allowMalformed: true).convert(f.bytes);
    } catch (_) {
      text = String.fromCharCodes(f.bytes);
    }
    final retailer = f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name;
    int n;
    try {
      n = ImportedCatalog.instance.importText(text, fallbackRetailer: retailer);
    } catch (_) {
      n = 0;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n > 0
          ? 'Uvezeno proizvoda: $n. Nalaze se pod filtrom „Uvezeno”.'
          : 'U datoteci nisu pronađeni proizvodi. Prvi red mora imati nazive stupaca, npr. naziv, sirina_cm, dubina_cm, visina_cm.'),
    ));
    if (n > 0) setState(() => category = '__imported');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ImportedCatalog.instance, RetailCatalog.instance]),
      builder: (context, _) => open == null ? _grid(context) : _detail(context, open!),
    );
  }

  // ---------------------------------------------------------------- rešetka
  Widget _grid(BuildContext context) {
    final list = _filtered();
    final categories = <String>[];
    for (final e in _all.where((e) => e.zone == zone &&
        (source == null || (source == '__gen' ? e.retailer == null : e.retailer == source)))) {
      if (!categories.contains(e.category)) categories.add(e.category);
    }
    final retailers = RetailCatalog.instance.retailers;
    final variants = list.fold<int>(0, (a, e) => a + e.variants.length);
    final hasImported = ImportedCatalog.instance.items.isNotEmpty;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'Traži: trosjed, hrast, skandinavski…'),
          onChanged: (v) => setState(() => query = v),
        ),
      ),
      if (query.trim().isEmpty) ...[
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
        if (retailers.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              children: [
                _sourceChip('Sve trgovine', null),
                for (final r in retailers) _sourceChip(r, r),
                _sourceChip('Generički', '__gen'),
              ],
            ),
          ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            children: [
              _chip('Sve', category == null, () => setState(() => category = null)),
              if (hasImported) _chip('Uvezeno', category == '__imported', () => setState(() => category = '__imported')),
              for (final cat in categories) _chip(cat, category == cat, () => setState(() => category = cat)),
            ],
          ),
        ),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 8, 2),
        child: Row(children: [
          Expanded(
            child: Text(
              '${_fmtInt(list.length)} ${list.length == 1 ? 'model' : 'modela'}, ${_fmtInt(variants)} varijanti',
              style: AppText.ui(size: 12, color: Pal.muted),
            ),
          ),
          if (zone == CatalogZone.interior || query.isNotEmpty)
            PopupMenuButton<String?>(
              tooltip: 'Stil',
              onSelected: (v) => setState(() => styleId = v == '' ? null : v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: '', child: Text('Svi stilovi')),
                for (final s in styles) PopupMenuItem(value: s.id, child: Text('${s.name} (${s.series})')),
              ],
              child: _miniButton(Icons.palette_outlined, styleId == null ? 'Stil' : styleById(styleId).name),
            ),
          PopupMenuButton<_Sort>(
            tooltip: 'Poredak',
            onSelected: (v) => setState(() => sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Sort.recommended, child: Text('Preporučeno')),
              PopupMenuItem(value: _Sort.priceUp, child: Text('Cijena: od najniže')),
              PopupMenuItem(value: _Sort.priceDown, child: Text('Cijena: od najviše')),
              PopupMenuItem(value: _Sort.name, child: Text('Naziv')),
            ],
            child: _miniButton(Icons.sort, switch (sort) {
              _Sort.recommended => 'Preporučeno',
              _Sort.priceUp => 'Cijena ↑',
              _Sort.priceDown => 'Cijena ↓',
              _Sort.name => 'Naziv',
            }),
          ),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Ništa ne odgovara traženju. Probaj drugu riječ ili makni filtar stila.',
                    style: AppText.ui(size: 13, color: Pal.muted)),
              )
            : ListenableBuilder(
                listenable: Thumbnails.instance,
                builder: (context, _) => GridView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.68,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _ModelCard(
                    entry: list[i],
                    selected: widget.c.placing?.modelId != null && widget.c.placing?.modelId == list[i].id,
                    onTap: () => _openEntry(list[i]),
                  ),
                ),
              ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Pal.lineSoft))),
        child: Row(children: [
          Expanded(
            child: TextButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.upload_outlined, size: 18),
              label: const Text('Uvezi katalog trgovine'),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Više o uvozu',
            icon: const Icon(Icons.more_vert, size: 18, color: Pal.muted),
            onSelected: (v) {
              if (v == 'template') {
                downloadText(ImportedCatalog.csvTemplate, 'planstratiq-katalog-predlozak.csv', mime: 'text/csv;charset=utf-8');
              } else if (v == 'clear') {
                ImportedCatalog.instance.clear();
                setState(() => category = null);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'template', child: Text('Preuzmi predložak CSV datoteke')),
              if (hasImported) const PopupMenuItem(value: 'clear', child: Text('Ukloni uvezene proizvode')),
            ],
          ),
        ]),
      ),
    ]);
  }

  Widget _sourceChip(String label, String? value) {
    final active = source == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() {
          source = value;
          category = null;
          if (value != null && value != '__gen') styleId = null;
        }),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: active ? Pal.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? Pal.accent : Pal.line),
          ),
          child: Text(label,
              style: AppText.ui(size: 12, weight: FontWeight.w600, color: active ? Pal.accentDeep : Pal.inkSoft)),
        ),
      ),
    );
  }

  Widget _miniButton(IconData icon, String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: Pal.inkSoft),
          const SizedBox(width: 4),
          Text(label, style: AppText.ui(size: 12, weight: FontWeight.w600, color: Pal.inkSoft)),
        ]),
      );

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

  // ---------------------------------------------------------------- detalj modela
  Widget _detail(BuildContext context, _Entry e) {
    final dims = _dims(e), cols = _colors(e), legs = _legs(e);
    final v = _current(e);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 14, 0),
        child: Row(children: [
          IconButton(
            tooltip: 'Natrag na katalog',
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => setState(() => open = null),
          ),
          Expanded(
            child: Text(e.style?.name ?? e.retailer ?? e.category,
                style: AppText.ui(size: 12, color: Pal.muted), overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Draggable<CatalogItem>(
            data: v,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _dragFeedback(v),
            child: AspectRatio(
              aspectRatio: 1.35,
              child: Container(
                decoration: BoxDecoration(color: const Color(0xFFF5F7F6), borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.all(10),
                child: ListenableBuilder(listenable: Thumbnails.instance, builder: (_, __) => _thumb(v, 160)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(e.name, style: AppText.ui(size: 17, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${v.dims}${v.variant == null ? '' : '\n${v.variant}'}', style: AppText.ui(size: 12.5, color: Pal.muted, height: 1.4)),
          const SizedBox(height: 8),
          Row(children: [
            if (v.price != null)
              Text('≈ ${fmtEur(v.price!)}', style: AppText.narrow(size: 20, weight: FontWeight.w700)),
            const Spacer(),
            if (v.retailer != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Pal.accentSoft, borderRadius: BorderRadius.circular(6)),
                child: Text(v.retailer!, style: AppText.ui(size: 11.5, weight: FontWeight.w600, color: Pal.accentDeep)),
              ),
          ]),
          if (dims.length > 1) ...[
            _label('Veličina'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < dims.length; i++)
                _option(_sizeText(e, dims[i]), i == sizeIdx.clamp(0, dims.length - 1), () => setState(() => sizeIdx = i)),
            ]),
          ],
          if (cols.length > 1) ...[
            _label('Boja: ${cols[colorIdx.clamp(0, cols.length - 1)].$2}'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < cols.length; i++)
                Tooltip(
                  message: cols[i].$2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => colorIdx = i),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(cols[i].$1),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: i == colorIdx.clamp(0, cols.length - 1) ? Pal.accent : Pal.line,
                            width: i == colorIdx.clamp(0, cols.length - 1) ? 2.5 : 1),
                      ),
                    ),
                  ),
                ),
            ]),
          ],
          if (legs.length > 1) ...[
            _label('Izvedba'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < legs.length; i++)
                _option(_legName(legs[i]), i == legIdx.clamp(0, legs.length - 1), () => setState(() => legIdx = i)),
            ]),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () {
              widget.c.setTool(Tool.place, item: v);
              widget.onPicked?.call();
            },
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: const Text('Postavi u tlocrt'),
          ),
          const SizedBox(height: 8),
          Text('Ili povuci sliku iznad na tlocrt ili u 3D prikaz.', style: AppText.ui(size: 12, color: Pal.muted)),
          if (v.productUrl != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => web.window.open(v.productUrl!, '_blank'),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Otvori u trgovini'),
            ),
          ],
        ]),
      ),
    ]);
  }

  String _sizeText(_Entry e, String key) {
    final v = e.variants.firstWhere((x) => _dimKey(x) == key);
    return '${(v.w * 100).round()} × ${(v.d * 100).round()}';
  }

  String _legName(String l) => switch (l) {
        'wood' => 'Drvene noge',
        'metal' => 'Metalne noge',
        'chrome' => 'Kromirane noge',
        'plinth' => 'Bez nogu',
        _ => 'Standardno',
      };

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t, style: AppText.ui(size: 12, weight: FontWeight.w600, color: Pal.muted)),
      );

  Widget _option(String label, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: active ? Pal.accentSoft : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? Pal.accent : Pal.line, width: active ? 1.5 : 1),
          ),
          child: Text(label, style: AppText.narrow(size: 12.5, weight: FontWeight.w600, color: active ? Pal.accentDeep : Pal.inkSoft)),
        ),
      );
}

String _fmtInt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

Widget _thumb(CatalogItem it, double size) {
  final png = Thumbnails.instance.get(it);
  if (png != null) return Image.memory(png, fit: BoxFit.contain, gaplessPlayback: true, filterQuality: FilterQuality.medium);
  return Center(child: Icon(shapeIcons[it.shape] ?? Icons.inventory_2_outlined, size: size * 0.3, color: Pal.line));
}

Widget _dragFeedback(CatalogItem it) => Transform.translate(
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
          child: _thumb(it, 80),
        ),
      ),
    );

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.entry, required this.selected, required this.onTap});
  final _Entry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final main = entry.main;
    final colors = <int>[];
    for (final v in entry.variants) {
      if (!colors.contains(v.color)) colors.add(v.color);
      if (colors.length >= 6) break;
    }
    final more = {for (final v in entry.variants) v.color}.length - colors.length;
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
          Expanded(child: Container(color: const Color(0xFFF5F7F6), padding: const EdgeInsets.all(6), child: _thumb(main, 120))),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.ui(size: 12, weight: FontWeight.w600, height: 1.2)),
              const SizedBox(height: 3),
              Text(
                entry.retailer ?? (entry.style?.name ?? entry.category),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.ui(size: 10.5, color: Pal.muted),
              ),
              const SizedBox(height: 5),
              Row(children: [
                for (final c in colors)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: Pal.line, width: 0.6)),
                  ),
                if (more > 0) Text('+$more', style: AppText.narrow(size: 10, color: Pal.muted)),
                const Spacer(),
                if (entry.minPrice.isFinite)
                  Text('${entry.variants.length > 1 ? 'od ' : ''}${fmtEur(entry.minPrice)}',
                      style: AppText.narrow(size: 10.5, weight: FontWeight.w600, color: Pal.inkSoft)),
              ]),
            ]),
          ),
        ]),
      ),
    );
    return Draggable<CatalogItem>(
      data: main,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _dragFeedback(main),
      childWhenDragging: Opacity(opacity: 0.45, child: card),
      child: card,
    );
  }
}
