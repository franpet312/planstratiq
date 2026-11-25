import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../models/plan.dart';
import '../models/topology.dart';

class ProjectMeta {
  ProjectMeta({required this.id, required this.name, required this.updated, this.area = 0, this.rooms = 0});

  final String id;
  String name;
  int updated;
  double area;
  int rooms;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'updated': updated, 'area': area, 'rooms': rooms};

  factory ProjectMeta.fromJson(Map<String, dynamic> j) => ProjectMeta(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Projekt',
        updated: (j['updated'] as num?)?.toInt() ?? 0,
        area: (j['area'] as num?)?.toDouble() ?? 0,
        rooms: (j['rooms'] as num?)?.toInt() ?? 0,
      );
}

@JS('psqStore')
external _Idb? get _idb;

extension type _Idb(JSObject _) implements JSObject {
  external JSPromise<JSString?> get(String key);
  external JSPromise<JSBoolean> put(String key, String value);
  external JSPromise<JSBoolean> del(String key);
  external JSPromise<JSBoolean> delPrefix(String prefix);
}

/// Projekti se čuvaju lokalno u pregledniku: tlocrt u localStorage, slike nacrta u IndexedDB-u
/// (localStorage ima samo ~5 MB, pa bi se slike inače gubile).
class ProjectStore {
  ProjectStore._();
  static final instance = ProjectStore._();

  static const _indexKey = 'planstratiq.index.v2';
  static String _key(String id) => 'planstratiq.p.$id';

  web.Storage get _ls => web.window.localStorage;

  List<ProjectMeta> list() {
    try {
      final raw = _ls.getItem(_indexKey);
      if (raw == null) return [];
      final l = (jsonDecode(raw) as List).map((e) => ProjectMeta.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      l.sort((a, b) => b.updated.compareTo(a.updated));
      return l;
    } catch (_) {
      return [];
    }
  }

  void _writeIndex(List<ProjectMeta> l) => _ls.setItem(_indexKey, jsonEncode(l.map((e) => e.toJson()).toList()));

  Plan? load(String id) {
    try {
      final raw = _ls.getItem(_key(id));
      if (raw == null) return null;
      return Plan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Greška pri spremanju (npr. pun preglednik) – prikazuje se korisniku.
  final error = ValueNotifier<String?>(null);

  static String _imgKey(String id, String levelId) => 'img:$id:$levelId';
  final _savedImg = <String, String>{}; // ključ -> potpis spremljene slike

  static String _sig(Map<String, dynamic> j) {
    final d = (j['dataUrl'] as String?) ?? '';
    final rest = Map<String, dynamic>.from(j)..remove('dataUrl');
    final mid = d.length > 200 ? d.substring(d.length ~/ 2, d.length ~/ 2 + 64) : d;
    return '${d.length}|$mid|${d.length > 64 ? d.substring(d.length - 64) : ''}|${jsonEncode(rest)}';
  }

  /// Učitaj slike nacrta iz IndexedDB-a u etaže koje ih nemaju. Vraća true ako je nešto učitano.
  Future<bool> attachImages(String id, Plan plan) async {
    final db = _idb;
    if (db == null) return false;
    var any = false;
    for (final l in plan.levels) {
      final key = _imgKey(id, l.id);
      if (l.image != null) continue;
      try {
        final raw = (await db.get(key).toDart)?.toDart;
        if (raw == null) continue;
        final j = jsonDecode(raw) as Map<String, dynamic>;
        l.image = PlanImage.fromJson(j);
        _savedImg[key] = _sig(j);
        any = true;
      } catch (_) {}
    }
    return any;
  }

  /// Spremi projekt (slike nacrta odvojeno, u IndexedDB).
  void save(String id, Plan plan) {
    final db = _idb;
    final withImages = db == null;
    try {
      _ls.setItem(_key(id), jsonEncode(plan.toJson(includeImage: withImages)));
      if (error.value != null) error.value = null;
    } catch (_) {
      try {
        _ls.setItem(_key(id), jsonEncode(plan.toJson(includeImage: false)));
      } catch (_) {
        error.value = 'Preglednik je pun pa se projekt ne može spremiti. Izvezi ga kao datoteku (Ctrl+S) i obriši stare projekte.';
        return;
      }
    }
    if (db != null) {
      for (final l in plan.levels) {
        final key = _imgKey(id, l.id);
        final im = l.image;
        if (im == null) {
          if (_savedImg.remove(key) != null) db.del(key);
          continue;
        }
        final j = im.toJson();
        final sig = _sig(j);
        if (_savedImg[key] == sig) continue;
        _savedImg[key] = sig;
        db.put(key, jsonEncode(j)).toDart.then((ok) {
          if (!ok.toDart) error.value = 'Slika nacrta se nije mogla spremiti u preglednik.';
        });
      }
    }
    final l = list();
    var m = l.where((e) => e.id == id).firstOrNull;
    if (m == null) {
      m = ProjectMeta(id: id, name: plan.name, updated: 0);
      l.add(m);
    }
    m
      ..name = plan.name
      ..updated = DateTime.now().millisecondsSinceEpoch
      ..rooms = plan.levels.fold(0, (a, lv) => a + lv.rooms.length)
      ..area = plan.rooms.fold(0.0, (a, r) => a + roomNetArea(plan, r));
    try {
      _writeIndex(l);
    } catch (_) {}
  }

  String create(Plan plan) {
    final id = newId('p');
    save(id, plan);
    return id;
  }

  void delete(String id) {
    _ls.removeItem(_key(id));
    _idb?.delPrefix('img:$id:');
    _writeIndex(list()..removeWhere((e) => e.id == id));
  }

  Future<String?> duplicate(String id) async {
    final p = load(id);
    if (p == null) return null;
    await attachImages(id, p);
    p.name = '${p.name} (kopija)';
    return create(p);
  }

  void rename(String id, String name) {
    final p = load(id);
    if (p == null) return;
    p.name = name;
    // spremi samo tlocrt; slike nacrta u IndexedDB-u ostaju kakve jesu
    try {
      _ls.setItem(_key(id), jsonEncode(p.toJson(includeImage: _idb == null)));
    } catch (_) {}
    final l = list();
    for (final m in l) {
      if (m.id == id) m.name = name;
    }
    try {
      _writeIndex(l);
    } catch (_) {}
  }
}
