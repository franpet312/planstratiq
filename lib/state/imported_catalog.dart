import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../models/catalog.dart';
import '../models/catalog_gen.dart';

/// Proizvodi trgovina uvezeni iz CSV/JSON datoteke (npr. partnerski feed).
/// Spremaju se u preglednik i pojavljuju se u katalogu s nazivom trgovine.
class ImportedCatalog extends ChangeNotifier {
  ImportedCatalog._() {
    _load();
  }
  static final instance = ImportedCatalog._();
  static const _key = 'planstratiq.imported.v1';

  final List<CatalogItem> items = [];

  List<String> get retailers => {for (final i in items) i.retailer ?? 'Uvezeno'}.toList()..sort();

  void _load() {
    try {
      final raw = web.window.localStorage.getItem(_key);
      if (raw == null) return;
      for (final m in (jsonDecode(raw) as List)) {
        final it = _fromMap(Map<String, dynamic>.from(m as Map));
        if (it != null) items.add(it);
      }
      _index();
    } catch (_) {}
  }

  void _save() {
    try {
      web.window.localStorage.setItem(_key, jsonEncode([for (final i in items) _toMap(i)]));
    } catch (_) {}
  }

  void _index() {
    importedById
      ..clear()
      ..addEntries(items.map((i) => MapEntry(i.id, i)));
  }

  void clear() {
    items.clear();
    _index();
    _save();
    notifyListeners();
  }

  void removeRetailer(String r) {
    items.removeWhere((i) => (i.retailer ?? 'Uvezeno') == r);
    _index();
    _save();
    notifyListeners();
  }

  /// Uvezi datoteku; vraća broj uvezenih proizvoda.
  int importText(String text, {String? fallbackRetailer}) {
    final t = text.trimLeft();
    final rows = <Map<String, String>>[];
    if (t.startsWith('[') || t.startsWith('{')) {
      final data = jsonDecode(t);
      final list = data is List ? data : (data is Map && data['products'] is List ? data['products'] as List : const []);
      for (final e in list) {
        if (e is Map) rows.add({for (final kv in e.entries) _norm(kv.key.toString()): '${kv.value ?? ''}'});
      }
    } else {
      rows.addAll(_parseCsv(t));
    }
    var n = 0;
    for (final r in rows) {
      final it = _fromRow(r, fallbackRetailer: fallbackRetailer, index: items.length + n);
      if (it != null) {
        items.add(it);
        n++;
      }
    }
    _index();
    _save();
    notifyListeners();
    return n;
  }

  // ---------------------------------------------------------------- parsiranje

  static String _norm(String k) => k
      .toLowerCase()
      .trim()
      .replaceAll('š', 's')
      .replaceAll('č', 'c')
      .replaceAll('ć', 'c')
      .replaceAll('ž', 'z')
      .replaceAll('đ', 'd')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static List<Map<String, String>> _parseCsv(String text) {
    final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return [];
    final sep = lines.first.split(';').length >= lines.first.split(',').length ? ';' : ',';
    List<String> split(String line) {
      final out = <String>[];
      final b = StringBuffer();
      var q = false;
      for (var i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') {
          if (q && i + 1 < line.length && line[i + 1] == '"') {
            b.write('"');
            i++;
          } else {
            q = !q;
          }
        } else if (ch == sep && !q) {
          out.add(b.toString());
          b.clear();
        } else {
          b.write(ch);
        }
      }
      out.add(b.toString());
      return out;
    }

    final header = split(lines.first.replaceFirst('﻿', '')).map(_norm).toList();
    return [
      for (final l in lines.skip(1))
        () {
          final cells = split(l);
          return {for (var i = 0; i < header.length && i < cells.length; i++) header[i]: cells[i].trim()};
        }()
    ];
  }

  static String? _pick(Map<String, String> r, List<String> keys) {
    for (final k in keys) {
      final v = r[k];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  static double? _num(String? s) => s == null ? null : double.tryParse(s.replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.'));

  static const _shapeKeywords = <(String, String)>[
    ('kutna', 'sofa_corner'),
    ('krevet na kat', 'bunk'),
    ('krevetic', 'crib'),
    ('barsk', 'stool'),
    ('tabure', 'pouf'),
    ('pouf', 'pouf'),
    ('trosjed', 'sofa'),
    ('dvosjed', 'sofa'),
    ('kauc', 'sofa'),
    ('sofa', 'sofa'),
    ('garnitur', 'sofa_corner'),
    ('fotelj', 'sofa'),
    ('krevet', 'bed'),
    ('madrac', 'bed'),
    ('ormaric', 'dresser'),
    ('ormar', 'wardrobe'),
    ('garderob', 'wardrobe'),
    ('komod', 'dresser'),
    ('cipelar', 'dresser'),
    ('vitrin', 'vitrine'),
    ('polic', 'shelf'),
    ('regal', 'shelf'),
    ('tv', 'tv_stand'),
    ('stolic', 'table'),
    ('okrugli stol', 'table_round'),
    ('stolica', 'chair'),
    ('stolac', 'chair'),
    ('klupa', 'bench'),
    ('stol', 'table'),
    ('tepih', 'rug'),
    ('lamp', 'lamp'),
    ('svjetilj', 'lamp'),
    ('biljk', 'plant'),
    ('hladnjak', 'fridge'),
    ('frizider', 'fridge'),
    ('stednjak', 'stove'),
    ('perilica posud', 'dishwasher'),
    ('perilic', 'washer'),
    ('susilic', 'washer'),
    ('kada', 'bath'),
    ('tus', 'shower'),
    ('wc', 'toilet'),
    ('skoljk', 'toilet'),
    ('umivaonik', 'vanity'),
    ('kuhinj', 'kitchen'),
    ('lezaljk', 'lounger'),
    ('suncobran', 'umbrella'),
    ('rostilj', 'grill'),
  ];

  static String guessShape(String text) {
    final t = text
        .toLowerCase()
        .replaceAll('š', 's')
        .replaceAll('č', 'c')
        .replaceAll('ć', 'c')
        .replaceAll('ž', 'z')
        .replaceAll('đ', 'd');
    for (final (k, s) in _shapeKeywords) {
      if (t.contains(k)) return s;
    }
    return 'box';
  }

  static int colorFor(String? s, String shape) => _color(s, shape);

  static int _color(String? s, String shape) {
    if (s != null) {
      final hex = s.replaceAll('#', '').trim();
      if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return int.parse('FF$hex', radix: 16);
      final n = s.toLowerCase();
      const named = {
        'bijel': 0xFFF1EFEA, 'crn': 0xFF2C2C2C, 'siv': 0xFF8E9296, 'bez': 0xFFCDBBA0, 'bež': 0xFFCDBBA0,
        'smed': 0xFF7A5236, 'smeđ': 0xFF7A5236, 'plav': 0xFF33455E, 'zelen': 0xFF6B8A5E, 'hrast': 0xFFC09A6B,
        'orah': 0xFF7A5236, 'crven': 0xFFA8323A, 'zut': 0xFFC99A35, 'žut': 0xFFC99A35, 'roz': 0xFFD4A5A0,
      };
      for (final e in named.entries) {
        if (n.contains(e.key)) return e.value;
      }
    }
    return switch (shape) {
      'sofa' || 'sofa_corner' || 'pouf' => 0xFF8E9296,
      'fridge' || 'stove' || 'washer' || 'dishwasher' => 0xFFC5C8CA,
      'bath' || 'toilet' || 'vanity' => 0xFFFFFFFF,
      _ => 0xFFC09A6B,
    };
  }

  CatalogItem? _fromRow(Map<String, String> r, {String? fallbackRetailer, required int index}) {
    final name = _pick(r, ['naziv', 'name', 'proizvod', 'product', 'title']);
    if (name == null) return null;
    final category = _pick(r, ['kategorija', 'category', 'grupa']) ?? 'Uvezeno';
    final shape = _pick(r, ['oblik', 'shape', 'tip']) ?? guessShape('$name $category');
    double cm(List<String> k, double def) {
      final v = _num(_pick(r, k));
      if (v == null || v <= 0) return def;
      return v > 20 ? v / 100 : v; // cm ili m
    }

    final w = cm(['sirina', 'width', 'sirinacm', 'widthcm', 'w'], 1.0);
    final d = cm(['dubina', 'depth', 'dubinacm', 'depthcm', 'duzina', 'length', 'd'], 0.6);
    final h = cm(['visina', 'height', 'visinacm', 'heightcm', 'h'], 0.8);
    final retailer = _pick(r, ['trgovina', 'retailer', 'brand', 'marka', 'trgovac']) ?? fallbackRetailer ?? 'Uvezeno';
    final ext = RegExp(r'vrt|teras|dvori|balkon|outdoor|garden', caseSensitive: false).hasMatch(category);
    return CatalogItem(
      id: 'imp:${_norm(retailer)}:${_pick(r, ['sifra', 'sku', 'id', 'artikl']) ?? index}',
      name: name,
      category: category,
      zone: ext ? CatalogZone.exterior : CatalogZone.interior,
      shape: shape,
      w: w,
      d: d,
      h: h,
      color: _color(_pick(r, ['boja', 'color', 'colour', 'hex']), shape),
      price: _num(_pick(r, ['cijena', 'price', 'cijenaeur', 'mpc'])),
      retailer: retailer,
      productUrl: _pick(r, ['link', 'url', 'poveznica', 'producturl']),
      modelUrl: _pick(r, ['model', 'modelurl', 'glb', '3d', 'model3d']),
      variant: _pick(r, ['opis', 'varijanta', 'description']),
    );
  }

  static Map<String, dynamic> _toMap(CatalogItem i) => {
        'id': i.id,
        'name': i.name,
        'category': i.category,
        'zone': i.zone.name,
        'shape': i.shape,
        'w': i.w,
        'd': i.d,
        'h': i.h,
        'color': i.color,
        'price': i.price,
        'retailer': i.retailer,
        'productUrl': i.productUrl,
        'modelUrl': i.modelUrl,
        'variant': i.variant,
      };

  static CatalogItem? _fromMap(Map<String, dynamic> m) {
    try {
      return CatalogItem(
        id: m['id'] as String,
        name: m['name'] as String,
        category: (m['category'] as String?) ?? 'Uvezeno',
        zone: m['zone'] == 'exterior' ? CatalogZone.exterior : CatalogZone.interior,
        shape: (m['shape'] as String?) ?? 'box',
        w: (m['w'] as num).toDouble(),
        d: (m['d'] as num).toDouble(),
        h: (m['h'] as num).toDouble(),
        color: (m['color'] as num).toInt(),
        price: (m['price'] as num?)?.toDouble(),
        retailer: m['retailer'] as String?,
        productUrl: m['productUrl'] as String?,
        modelUrl: m['modelUrl'] as String?,
        variant: m['variant'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Primjer datoteke za uvoz.
  static const csvTemplate = 'naziv;kategorija;sirina_cm;dubina_cm;visina_cm;cijena;boja;trgovina;sifra;link;model\n'
      'Trosjed primjer;Dnevni boravak;210;92;85;599;siva;Moja trgovina;T-100;https://primjer.hr/trosjed;\n'
      'Krevet primjer 160x200;Spavaća soba;166;212;100;449;#C09A6B;Moja trgovina;K-160;https://primjer.hr/krevet;\n'
      'Hladnjak primjer;Kuhinja;60;65;185;529;inox;Moja trgovina;H-60;;https://primjer.hr/modeli/hladnjak.glb\n';
}
