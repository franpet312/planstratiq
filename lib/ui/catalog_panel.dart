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
  'lamp_arc': Icons.light_outlined,
  'table_lamp': Icons.table_bar_outlined,
  'wall_lamp': Icons.wb_iridescent_outlined,
  'chandelier': Icons.light_mode_outlined,
  'chandelier_ring': Icons.radio_button_unchecked,
  'pendant': Icons.emoji_objects_outlined,
  'pendant_row': Icons.emoji_objects_outlined,
  'ceiling_light': Icons.circle_outlined,
  'socket': Icons.power_outlined,
  'socket_double': Icons.power_outlined,
  'socket_high': Icons.power_outlined,
  'switch': Icons.toggle_on_outlined,
  'tv_socket': Icons.settings_input_antenna,
  'lan_socket': Icons.lan_outlined,
  'light_point': Icons.lightbulb_outline,
  'radiator': Icons.heat_pump_outlined,
  'towel_radiator': Icons.dry_outlined,
  'ac_indoor': Icons.ac_unit,
  'ac_outdoor': Icons.ac_unit,
  'heat_pump': Icons.heat_pump_outlined,
  'boiler': Icons.water_drop_outlined,
  'wood_stove': Icons.fireplace_outlined,
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

  /// Ključ izvora: naziv trgovine ili [genericSource].
  String get source => retailer ?? genericSource;

  double get minPrice => variants.map((v) => v.price ?? 0).fold(double.infinity, (a, b) => b > 0 && b < a ? b : a);
  late final String search = '${name.toLowerCase()} ${category.toLowerCase()} ${style?.name.toLowerCase() ?? ''} ${retailer?.toLowerCase() ?? ''}';
}

const genericSource = '__gen';

/// Boja oznake trgovine (samo za raspoznavanje u popisu).
Color storeColor(String? store) => switch (store) {
      'IKEA' => const Color(0xFF0058A3),
      'JYSK' => const Color(0xFF1B3A6B),
      'Emmezeta' => const Color(0xFFD7192E),
      null || genericSource => Pal.accent,
      _ => Color(0xFF000000 | (const [0x7A5236, 0x3A6EA5, 0x6E7F3A, 0x8A4F7D, 0x2F7F7A, 0xA5623A][store.hashCode.abs() % 6])),
    };

String storeName(String store) => store == genericSource ? 'Planstratiq katalog' : store;

String storeBlurb(String store) => switch (store) {
      'IKEA' => 'Stvarni proizvodi s mjerama, cijenama i poveznicama',
      'JYSK' => 'Stvarni proizvodi s mjerama, cijenama i poveznicama',
      'Emmezeta' => 'Stvarni proizvodi s mjerama, cijenama i poveznicama',
      genericSource => 'Tipski namještaj u 8 stilova, veličinama i bojama',
      _ => 'Uvezeni katalog',
    };

const _categoryIcons = <String, IconData>{
  catLiving: Icons.weekend_outlined,
  catBed: Icons.bed_outlined,
  catKitchen: Icons.kitchen_outlined,
  catBath: Icons.bathtub_outlined,
  catWork: Icons.desk_outlined,
  catHall: Icons.door_front_door_outlined,
  catLight: Icons.light_outlined,
  catElectric: Icons.electrical_services_outlined,
  catHeating: Icons.thermostat_outlined,
  catPlumbing: Icons.plumbing_outlined,
  catGarden: Icons.deck_outlined,
  catYard: Icons.yard_outlined,
};
const _categoryOrder = [catLiving, catBed, catKitchen, catBath, catWork, catHall, catLight, catElectric, catHeating, catPlumbing, catGarden, catYard];

enum _Sort { recommended, priceUp, priceDown, name }

class CatalogPanel extends StatefulWidget {
  const CatalogPanel({super.key, required this.c, this.onPicked});
  final PlanController c;
  final VoidCallback? onPicked;

  @override
  State<CatalogPanel> createState() => _CatalogPanelState();
}

class _CatalogPanelState extends State<CatalogPanel> {
  /// Odabrana trgovina (null = sve) i kategorija (null = sve); pamte se dok je aplikacija otvorena.
  static String? source;
  static String? category;
  static bool browsing = false;
  static String? styleId;
  static _Sort sort = _Sort.recommended;
  static final List<CatalogItem> recent = [];
  String query = '';
  _Entry? open;
  int sizeIdx = 0, colorIdx = 0, legIdx = 0;
  final scroll = ScrollController();
  final search = TextEditingController();

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
    search.dispose();
    super.dispose();
  }

  bool get _home => !browsing && query.trim().isEmpty;

  void _go({String? store, String? cat, bool keepStore = false, bool keepCat = false}) => setState(() {
        browsing = true;
        if (!keepStore) source = store;
        if (!keepCat) category = cat;
        if (source != null && source != genericSource) styleId = null;
        if (scroll.hasClients) scroll.jumpTo(0);
      });

  void _goHome() => setState(() {
        browsing = false;
        source = null;
        category = null;
        query = '';
        search.clear();
      });

  List<_Entry> _filtered({bool ignoreStore = false, bool ignoreCat = false}) {
    final q = query.trim().toLowerCase();
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final list = _all.where((e) {
      if (words.isNotEmpty && !words.every((w) => e.search.contains(w))) return false;
      if (!ignoreStore && source != null && e.source != source) return false;
      if (!ignoreCat && category != null && e.category != category) return false;
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

  void _place(CatalogItem v) {
    recent
      ..removeWhere((r) => r.id == v.id)
      ..insert(0, v);
    if (recent.length > 12) recent.removeLast();
    widget.c.setTool(Tool.place, item: v);
    widget.onPicked?.call();
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
          ? 'Uvezeno proizvoda: $n. Trgovina „$retailer” sada je na popisu trgovina.'
          : 'U datoteci nisu pronađeni proizvodi. Prvi red mora imati nazive stupaca, npr. naziv, sirina_cm, dubina_cm, visina_cm.'),
    ));
    if (n > 0) _go(store: ImportedCatalog.instance.items.last.retailer ?? retailer);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ImportedCatalog.instance, RetailCatalog.instance]),
      builder: (context, _) => open == null
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _searchBar(),
              Expanded(child: _home ? _homeView(context) : _browseView(context)),
              _footer(),
            ])
          : _detail(context, open!),
    );
  }

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: TextField(
          controller: search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: source == null ? 'Traži u svim trgovinama: krevet 160, hrast…' : 'Traži u: ${storeName(source!)}',
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Očisti',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      query = '';
                      search.clear();
                    }),
                  ),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
      );

  // ---------------------------------------------------------------- početna stranica kataloga
  Map<String, int> _countBy(Iterable<_Entry> list, String Function(_Entry) key) {
    final out = <String, int>{};
    for (final e in list) {
      out[key(e)] = (out[key(e)] ?? 0) + 1;
    }
    return out;
  }

  List<String> get _stores {
    final all = _all;
    final retail = {for (final e in all) if (e.retailer != null) e.retailer!}.toList();
    const known = ['IKEA', 'JYSK', 'Emmezeta'];
    retail.sort((a, b) {
      final ia = known.indexOf(a), ib = known.indexOf(b);
      if (ia >= 0 || ib >= 0) return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
      return a.compareTo(b);
    });
    return [...retail, genericSource];
  }

  List<String> _orderedCats(Iterable<String> cats) {
    final l = cats.toSet().toList();
    l.sort((a, b) {
      final ia = _categoryOrder.indexOf(a), ib = _categoryOrder.indexOf(b);
      return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
    });
    return l;
  }

  Widget _homeView(BuildContext context) {
    final all = _all;
    final byStore = _countBy(all, (e) => e.source);
    final catsByStore = <String, Set<String>>{};
    for (final e in all) {
      (catsByStore[e.source] ??= {}).add(e.category);
    }
    final byCat = _countBy(all, (e) => e.category);
    final cats = _orderedCats(byCat.keys);
    return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(14, 4, 14, 16), children: [
      if (recent.isNotEmpty) ...[
        _section('Nedavno korišteno'),
        SizedBox(
          height: 92,
          child: ListenableBuilder(
            listenable: Thumbnails.instance,
            builder: (context, _) => HStrip(drag: false, builder: (ctl) => ListView.separated(
              controller: ctl,
              scrollDirection: Axis.horizontal,
              itemCount: recent.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final v = recent[i];
                return Tooltip(
                  message: '${v.name}\n${v.dims}',
                  child: Draggable<CatalogItem>(
                    data: v,
                    dragAnchorStrategy: pointerDragAnchorStrategy,
                    feedback: _dragFeedback(v),
                    child: InkWell(
                      onTap: () => _place(v),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 84,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F7F6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Pal.lineSoft),
                        ),
                        child: Column(children: [
                          Expanded(child: _thumb(v, 60)),
                          Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.ui(size: 10.5, weight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                );
              },
            )),
          ),
        ),
      ],
      _section('Trgovine', trailing: TextButton(onPressed: () => _go(), child: const Text('Svi proizvodi'))),
      for (final st in _stores)
        if ((byStore[st] ?? 0) > 0)
          _StoreCard(
            store: st,
            products: byStore[st]!,
            categories: _orderedCats(catsByStore[st] ?? {}),
            onTap: () => _go(store: st),
            onCategory: (cat) => _go(store: st, cat: cat),
          ),
      _section('Po prostoriji'),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.3,
        children: [
          for (final cat in cats)
            _CategoryTile(
              icon: _categoryIcons[cat] ?? Icons.category_outlined,
              name: cat,
              count: byCat[cat] ?? 0,
              stores: {for (final e in all) if (e.category == cat) e.source}.length,
              onTap: () => _go(cat: cat),
            ),
        ],
      ),
    ]);
  }

  Widget _section(String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Row(children: [
          Expanded(child: Text(title, style: AppText.ui(size: 13, weight: FontWeight.w700))),
          if (trailing != null) trailing,
        ]),
      );

  // ---------------------------------------------------------------- popis proizvoda
  Widget _browseView(BuildContext context) {
    final list = _filtered();
    final variants = list.fold<int>(0, (a, e) => a + e.variants.length);
    final searching = query.trim().isNotEmpty;
    final title = searching && source == null && category == null
        ? 'Rezultati traženja'
        : _orAll([if (source != null) storeName(source!), if (category != null) category!].join(' · '));
    // kategorije unutar trgovine i trgovine unutar kategorije, s brojem proizvoda
    final catCounts = _countBy(_filtered(ignoreCat: true), (e) => e.category);
    final storeCounts = _countBy(_filtered(ignoreStore: true), (e) => e.source);
    final cats = _orderedCats(catCounts.keys);
    final stores = _stores.where((s) => (storeCounts[s] ?? 0) > 0).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
        child: Row(children: [
          IconButton(tooltip: 'Početna stranica kataloga', icon: const Icon(Icons.arrow_back, size: 20), onPressed: _goHome),
          if (source != null)
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: storeColor(source), shape: BoxShape.circle),
            ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.ui(size: 14, weight: FontWeight.w700)),
              Text('${_fmtInt(list.length)} ${list.length == 1 ? 'model' : 'modela'} · ${_fmtInt(variants)} varijanti',
                  style: AppText.ui(size: 11.5, color: Pal.muted)),
            ]),
          ),
        ]),
      ),
      if (stores.length > 1 || source != null)
        _chipRow([
          _chip('Sve trgovine', source == null, () => _go(keepCat: true)),
          for (final st in stores)
            _chip('${storeName(st)}  ${storeCounts[st]}', source == st, () => _go(store: st, keepCat: true), dot: storeColor(st)),
        ]),
      _chipRow([
        _chip('Sve kategorije', category == null, () => _go(keepStore: true)),
        for (final cat in cats) _chip('$cat  ${catCounts[cat]}', category == cat, () => _go(cat: cat, keepStore: true)),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 8, 2),
        child: Row(children: [
          const Spacer(),
          if (source == null || source == genericSource)
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
                child: Text(
                    source != null && searching
                        ? 'U trgovini ${storeName(source!)} nema ništa za „$query”. Odaberi „Sve trgovine” da tražiš posvuda.'
                        : 'Ništa ne odgovara traženju. Probaj drugu riječ ili makni filtar stila.',
                    style: AppText.ui(size: 13, color: Pal.muted, height: 1.4)),
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
                    childAspectRatio: 0.66,
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
    ]);
  }

  Widget _chipRow(List<Widget> chips) => SizedBox(
        height: 40,
        child: HStrip(
            builder: (ctl) => ListView(controller: ctl, scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(14, 6, 14, 2), children: chips)),
      );

  Widget _footer() {
    final hasImported = ImportedCatalog.instance.items.isNotEmpty;
    return Container(
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
              _goHome();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'template', child: Text('Preuzmi predložak CSV datoteke')),
            if (hasImported) const PopupMenuItem(value: 'clear', child: Text('Ukloni uvezene proizvode')),
          ],
        ),
      ]),
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

  Widget _chip(String label, bool active, VoidCallback onTap, {Color? dot}) => Padding(
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
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (dot != null) ...[
                Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: active ? 1 : 0))),
                const SizedBox(width: 6),
              ],
              Text(label, style: AppText.ui(size: 12, weight: FontWeight.w500, color: active ? Colors.white : Pal.inkSoft)),
            ]),
          ),
        ),
      );

  /// Sličan namještaj (isti oblik) iz drugih trgovina, po cijeni.
  List<_Entry> _alternatives(_Entry e) {
    final shape = e.variants.first.shape;
    final out = _all.where((x) => x.id != e.id && x.source != e.source && x.variants.first.shape == shape).toList();
    // po jedan (najjeftiniji) iz generičkog kataloga po stilu bi bio previše – ograniči ga
    out.sort((a, b) => a.minPrice.compareTo(b.minPrice));
    final gen = out.where((x) => x.source == genericSource).take(2);
    final shops = out.where((x) => x.source != genericSource).take(10);
    return [...shops, ...gen];
  }

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
            child: Text(
                [storeName(e.source), e.category, if (e.style != null) e.style!.name].join(' · '),
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
            InkWell(
              onTap: () {
                setState(() => open = null);
                _go(store: e.source);
              },
              borderRadius: BorderRadius.circular(6),
              child: _StoreBadge(store: e.source),
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
            onPressed: () => _place(v),
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
              label: Text('Otvori na stranici trgovine ${v.retailer ?? ''}'.trim()),
            ),
          ],
          ..._alternativesSection(e),
        ]),
      ),
    ]);
  }

  List<Widget> _alternativesSection(_Entry e) {
    final alts = _alternatives(e);
    if (alts.isEmpty) return const [];
    return [
      _label('Slično u drugim trgovinama'),
      SizedBox(
        height: 168,
        child: ListenableBuilder(
          listenable: Thumbnails.instance,
          builder: (context, _) => HStrip(drag: false, builder: (ctl) => ListView.separated(
            controller: ctl,
            scrollDirection: Axis.horizontal,
            itemCount: alts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => SizedBox(
              width: 118,
              child: _ModelCard(entry: alts[i], selected: false, onTap: () => _openEntry(alts[i])),
            ),
          )),
        ),
      ),
    ];
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

String _orAll(String s) => s.isEmpty ? 'Svi proizvodi' : s;

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
              Row(children: [
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(color: storeColor(entry.source), shape: BoxShape.circle),
                ),
                Expanded(
                  child: Text(
                    entry.retailer ?? (entry.style?.name ?? entry.category),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.ui(size: 10.5, color: Pal.muted, weight: entry.retailer != null ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
              ]),
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


class _StoreBadge extends StatelessWidget {
  const _StoreBadge({required this.store});
  final String store;

  @override
  Widget build(BuildContext context) {
    final c = storeColor(store);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withAlpha(24), borderRadius: BorderRadius.circular(6), border: Border.all(color: c.withAlpha(90))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(storeName(store), style: AppText.ui(size: 11.5, weight: FontWeight.w600, color: c)),
      ]),
    );
  }
}

/// Kartica trgovine na početnoj stranici kataloga: broj proizvoda i brzi ulaz u kategorije.
class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store, required this.products, required this.categories, required this.onTap, required this.onCategory});
  final String store;
  final int products;
  final List<String> categories;
  final VoidCallback onTap;
  final void Function(String) onCategory;

  @override
  Widget build(BuildContext context) {
    final c = storeColor(store);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Pal.lineSoft)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 5, color: c),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(storeName(store), style: AppText.ui(size: 14.5, weight: FontWeight.w700, color: store == genericSource ? Pal.ink : c))),
                      Text('${_fmtInt(products)} ${products == 1 ? 'proizvod' : 'proizvoda'}', style: AppText.narrow(size: 12, weight: FontWeight.w600, color: Pal.inkSoft)),
                      const Icon(Icons.chevron_right, size: 18, color: Pal.muted),
                    ]),
                    const SizedBox(height: 2),
                    Text(storeBlurb(store), style: AppText.ui(size: 11.5, color: Pal.muted)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 4, runSpacing: 4, children: [
                      for (final cat in categories.take(6))
                        InkWell(
                          onTap: () => onCategory(cat),
                          borderRadius: BorderRadius.circular(5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xFFF3F5F4), borderRadius: BorderRadius.circular(5)),
                            child: Text(cat, style: AppText.ui(size: 11, color: Pal.inkSoft)),
                          ),
                        ),
                      if (categories.length > 6)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                          child: Text('+${categories.length - 6}', style: AppText.ui(size: 11, color: Pal.muted)),
                        ),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.icon, required this.name, required this.count, required this.stores, required this.onTap});
  final IconData icon;
  final String name;
  final int count;
  final int stores;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFF5F7F6),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Icon(icon, size: 22, color: Pal.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.ui(size: 12, weight: FontWeight.w600, height: 1.15)),
                  Text('$count · ${stores == 1 ? '1 izvor' : '$stores izvora'}', style: AppText.ui(size: 10.5, color: Pal.muted)),
                ]),
              ),
            ]),
          ),
        ),
      );
}
