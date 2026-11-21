import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../models/catalog.dart';
import '../models/catalog_gen.dart';
import 'imported_catalog.dart';

/// Model proizvoda trgovine s varijantama (boje / veličine istog proizvoda).
class RetailModel {
  RetailModel(this.id, this.name, this.retailer, this.category, this.zone, this.variants);
  final String id;
  final String name;
  final String retailer;
  final String category;
  final CatalogZone zone;
  final List<CatalogItem> variants;
}

/// Stvarni proizvodi trgovina (naziv, mjere, cijena, poveznica) iz web/retail/products.csv.
/// 3D prikaz je generički oblik u stvarnim mjerama proizvoda.
class RetailCatalog extends ChangeNotifier {
  RetailCatalog._();
  static final instance = RetailCatalog._();

  final List<RetailModel> models = [];
  int get productCount => models.fold(0, (a, m) => a + m.variants.length);
  List<String> get retailers => {for (final m in models) m.retailer}.toList()..sort();
  bool loaded = false;
  Future<void>? _loading;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final resp = await web.window.fetch('retail/products.csv'.toJS).toDart;
      if (!resp.ok) return;
      final text = (await resp.text().toDart).toDart;
      _parse(text);
    } catch (_) {
      // bez kataloga trgovina aplikacija i dalje radi s generiranim namještajem
    } finally {
      loaded = true;
      notifyListeners();
    }
  }

  static const _roomOf = {
    'Trosjedi': catLiving,
    'Sofe': catLiving,
    'Kauči': catLiving,
    'Kutne garniture': catLiving,
    'Dvosjedi i trosjedi': catLiving,
    'Fotelje': catLiving,
    'TV komode': catLiving,
    'Police': catLiving,
    'Stolići': catLiving,
    'Kreveti': catBed,
    'Ormari': catBed,
    'Komode': catBed,
    'Spavaća soba': catBed,
    'Blagovaonski stolovi': catKitchen,
    'Stolice': catKitchen,
    'Bijela tehnika': catKitchen,
    'Kuhinja': catKitchen,
    'Kupaonica': catBath,
    'Radni stolovi': catWork,
    'Vrtni namještaj': catGarden,
  };

  static const _extraShapes = <(String, String)>[
    ('kutna', 'sofa_corner'),
    ('počivaljk', 'sofa_corner'),
    ('produžetkom', 'sofa_corner'),
    ('chaise', 'pouf'),
    ('naslonjač', 'sofa'),
    ('lounge stolica', 'sofa'),
    ('fotelj', 'sofa'),
    ('jednosjed', 'sofa'),
    ('otoman', 'bed'),
    ('divan', 'bed'),
    ('dnevni krevet', 'bed'),
    ('okvir kreveta', 'bed'),
    ('biblioteka', 'shelf'),
    ('regal', 'shelf'),
    ('element', 'shelf'),
    ('vitrina', 'vitrine'),
    ('tv klupa', 'tv_stand'),
    ('tv komoda', 'tv_stand'),
    ('tv stalak', 'tv_stand'),
    ('multimed', 'tv_stand'),
    ('noćni ormarić', 'dresser'),
    ('komoda', 'dresser'),
    ('ormar', 'wardrobe'),
    ('hladnjak', 'fridge'),
    ('perilica posuđa', 'dishwasher'),
    ('perilica', 'washer'),
    ('stolac', 'stool'),
    ('barska', 'stool'),
    ('stolica', 'chair'),
    ('okrugl', 'table_round'),
    ('ø', 'table_round'),
    ('garnitura', 'sofa'),
  ];

  static String _shape(String name, String sub) {
    final t = '${name.toLowerCase()} ${sub.toLowerCase()}';
    for (final (k, s) in _extraShapes) {
      if (t.contains(k)) {
        if (s == 'sofa_corner' && (t.contains('trosjed s produžetkom') || t.contains('počivaljk')) && !t.contains('kutn')) return 'sofa_corner';
        return s;
      }
    }
    return ImportedCatalog.guessShape(t);
  }

  static String _slug(String s) => s
      .toLowerCase()
      .replaceAll('š', 's')
      .replaceAll(RegExp('[čć]'), 'c')
      .replaceAll('ž', 'z')
      .replaceAll('đ', 'd')
      .replaceAll(RegExp('[åä]'), 'a')
      .replaceAll('ö', 'o')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  void _parse(String text) {
    final lines = const LineSplitter().convert(text);
    if (lines.length < 2) return;
    final groups = <String, List<CatalogItem>>{};
    final meta = <String, (String, String, String, CatalogZone)>{};
    final seenIds = <String>{};
    final dimRe = RegExp(r',?\s*\d{2,3}(?:\(\d+\))?(?:/\d+)*x\d{2,3}(?:[,.]\d)?(?:x\d{2,3}(?:/\d+)?)?\s*cm', caseSensitive: false);
    for (final line in lines.skip(1)) {
      final f = line.split(';');
      if (f.length < 9) continue;
      final retailer = f[0].trim();
      final sub = f[1].trim();
      final name = f[2].trim();
      final w = double.tryParse(f[3]) ?? 100, d = double.tryParse(f[4]) ?? 60, h = double.tryParse(f[5]) ?? 80;
      final price = double.tryParse(f[6]);
      final colorName = f[7].trim();
      final url = f[8].trim();
      final exact = f.length > 9 && f[9].trim() == '1';
      final room = _roomOf[sub] ?? catLiving;
      final zone = room == catGarden ? CatalogZone.exterior : CatalogZone.interior;

      // grupiraj boje/veličine istog proizvoda (IKEA: "NAZIV Tip, boja, mjere")
      String base = name, colorText = '';
      final comma = name.indexOf(', ');
      if (retailer == 'IKEA' && comma > 0) {
        base = name.substring(0, comma);
        colorText = name.substring(comma + 2).replaceAll(dimRe, '').trim();
        if (colorText.endsWith(',')) colorText = colorText.substring(0, colorText.length - 1);
      }
      final key = '$retailer|$base';
      final shape = _shape(name, sub);
      var color = ImportedCatalog.colorFor(colorName.isEmpty ? name : colorName, shape);
      final list = groups.putIfAbsent(key, () => []);
      while (list.any((v) => v.color == color && v.w == w / 100 && v.d == d / 100 && v.h == h / 100)) {
        color = (color & 0xFFFFFF00) | (((color & 0xFF) + 9) & 0xFF);
      }
      var id = 'r:${_slug(retailer)}:${_slug(name)}';
      while (!seenIds.add(id)) {
        id = '$id-';
      }
      final dimsNote = exact ? '' : ' · mjere okvirne';
      list.add(CatalogItem(
        id: id,
        name: name,
        category: room,
        zone: zone,
        shape: shape,
        w: w / 100,
        d: d / 100,
        h: h / 100,
        color: color,
        price: price,
        retailer: retailer,
        productUrl: url.isEmpty ? null : url,
        modelId: 'r:${_slug(key)}',
        variant: '$sub, ${colorText.isEmpty ? (colorName.isEmpty ? sub : colorName) : colorText}$dimsNote',
      ));
      meta[key] = (base, retailer, room, zone);
    }
    models.clear();
    for (final e in groups.entries) {
      final (base, retailer, room, zone) = meta[e.key]!;
      models.add(RetailModel('r:${_slug(e.key)}', base, retailer, room, zone, e.value));
    }
    retailById
      ..clear()
      ..addEntries(models.expand((m) => m.variants).map((v) => MapEntry(v.id, v)));
  }
}
