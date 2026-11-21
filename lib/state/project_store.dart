import 'dart:convert';

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

/// Projekti se čuvaju lokalno u pregledniku (localStorage).
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

  /// Spremi projekt. Ako je slika nacrta prevelika za preglednik, sprema se bez nje.
  void save(String id, Plan plan) {
    try {
      _ls.setItem(_key(id), jsonEncode(plan.toJson()));
    } catch (_) {
      _ls.setItem(_key(id), jsonEncode(plan.toJson(includeImage: false)));
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
      ..rooms = plan.rooms.length
      ..area = plan.rooms.fold(0.0, (a, r) => a + roomNetArea(plan, r));
    _writeIndex(l);
  }

  String create(Plan plan) {
    final id = newId('p');
    save(id, plan);
    return id;
  }

  void delete(String id) {
    _ls.removeItem(_key(id));
    _writeIndex(list()..removeWhere((e) => e.id == id));
  }

  String? duplicate(String id) {
    final p = load(id);
    if (p == null) return null;
    p.name = '${p.name} (kopija)';
    return create(p);
  }

  void rename(String id, String name) {
    final p = load(id);
    if (p == null) return;
    p.name = name;
    save(id, p);
  }
}
