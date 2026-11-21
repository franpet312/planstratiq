import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../models/catalog.dart';
import '../models/geometry.dart';
import '../models/materials.dart';
import '../models/plan.dart';
import '../state/plan_controller.dart';

@JS('Planstratiq3D')
external _Engine get _js;

extension type _Engine._(JSObject _) implements JSObject {
  external bool? get ready;
  external void mount(web.HTMLElement el);
  external void setPlan(String json);
  external void setMode(String mode);
  external void setSelection(String kind, String id);
  external void setOptions(String json);
  external void frame();
  external void walkTo(double x, double y);
  external String? screenshot();
  external String? thumbnail(String json);
  external String? groundPoint(double x, double y);
  external set onEvent(JSFunction? f);
}

typedef EngineListener = void Function(String type, Object? data);

/// Jedinstveni most prema Three.js engineu (web/planstratiq3d.js).
class Engine3D {
  Engine3D._() {
    _js.onEvent = ((String type, String payload) {
      Object? data;
      try {
        data = jsonDecode(payload);
      } catch (_) {}
      for (final l in List.of(_listeners)) {
        l(type, data);
      }
    }).toJS;
  }

  static final instance = Engine3D._();
  final _listeners = <EngineListener>[];

  bool get ready => _js.ready == true;

  void addListener(EngineListener l) => _listeners.add(l);
  void removeListener(EngineListener l) => _listeners.remove(l);

  void mount(web.HTMLElement el) => _js.mount(el);
  void setPlan(PlanController c) => _js.setPlan(jsonEncode(sceneJson(c)));
  void setMode(String m) => _js.setMode(m);
  void setSelection(Selection s) => _js.setSelection(
        switch (s.kind) {
          SelKind.item => 'item',
          SelKind.wall => 'wall',
          SelKind.room => 'room',
          _ => '',
        },
        s.id,
      );
  void setTime(double hour) => _js.setOptions(jsonEncode({'time': hour}));
  void frame() => _js.frame();
  void walkTo(Offset p) => _js.walkTo(p.dx, p.dy);

  Uint8List? screenshotPng() => _decode(_js.screenshot());
  Uint8List? thumbnail(CatalogItem it) => _decode(_js.thumbnail(jsonEncode(it.toSceneJson())));

  Offset? groundPoint(Offset local) {
    final s = _js.groundPoint(local.dx, local.dy);
    if (s == null) return null;
    final l = jsonDecode(s) as List;
    return Offset((l[0] as num).toDouble(), (l[1] as num).toDouble());
  }

  static Uint8List? _decode(String? dataUrl) {
    if (dataUrl == null || !dataUrl.contains(',')) return null;
    return base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
  }

  /// Plan pretvoren u oblik koji engine očekuje (s podacima o materijalima i strani interijera).
  static Map<String, dynamic> sceneJson(PlanController c) {
    final plan = c.plan;
    final inside = <String, int>{};
    for (final w in plan.walls) {
      final sides = c.wallSides(w);
      if (sides != 1) {
        inside[w.id] = 0;
        continue;
      }
      // pronađi prostoriju uz zid i odredi s koje je strane
      var sign = 0;
      for (final r in plan.rooms) {
        final ids = r.nodeIds;
        for (var i = 0; i < ids.length; i++) {
          final a = ids[i], b = ids[(i + 1) % ids.length];
          if ((a == w.a && b == w.b) || (a == w.b && b == w.a)) {
            final pa = plan.nodePos(a), pb = plan.nodePos(b);
            final d = pb - pa;
            final inward = Offset(-d.dy, d.dx);
            final wd = plan.nodePos(w.b) - plan.nodePos(w.a);
            final n = Offset(-wd.dy, wd.dx);
            sign = dot(inward, n) >= 0 ? 1 : -1;
          }
        }
      }
      inside[w.id] = sign;
    }
    return {
      'projectId': c.projectId,
      'wallHeight': plan.wallHeight,
      'roof': plan.roof,
      'nodes': {for (final n in plan.nodes.values) n.id: {'x': n.pos.dx, 'y': n.pos.dy}},
      'walls': [
        for (final w in plan.walls) {...w.toJson(), 'inside': inside[w.id] ?? 0}
      ],
      'openings': plan.openings.map((o) => o.toJson()).toList(),
      'rooms': [
        for (final r in plan.rooms)
          () {
            final poly = plan.roomPolygon(r);
            final m = floorById(r.floor);
            final lp = poly.length >= 3 ? labelPoint(poly) : Offset.zero;
            return {
              'id': r.id,
              'nodeIds': r.nodeIds,
              'floorColor': m.color,
              'floorTexture': m.texture,
              'area': polygonArea(poly),
              'cx': lp.dx,
              'cy': lp.dy,
            };
          }()
      ],
      'outlines': [
        for (final o in c.outlines) [for (final p in o) [p.dx, p.dy]]
      ],
      'items': plan.items.map((i) => i.toJson()).toList(),
    };
  }
}

/// Sličice kataloga renderirane u 3D engineu, na zahtjev (samo vidljive), s predmemorijom.
class Thumbnails extends ChangeNotifier {
  Thumbnails._();
  static final instance = Thumbnails._();

  // ignore: prefer_collection_literals
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  final List<CatalogItem> _queue = [];
  final Set<String> _queued = {};
  bool _running = false;
  static const _max = 900;

  /// Vrati sličicu ako postoji; inače je zatraži (stigne kroz notifyListeners).
  Uint8List? get(CatalogItem it) {
    final k = it.thumbKey;
    final v = _cache.remove(k);
    if (v != null) {
      _cache[k] = v; // LRU: na kraj
      return v;
    }
    if (_queued.add(k)) {
      _queue.add(it);
      if (!_running) Future.microtask(_pump);
    }
    return null;
  }

  /// Zaboravi zahtjeve za sličicama koje više nisu vidljive.
  void cancelPending() {
    _queue.clear();
    _queued.clear();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    var waited = 0;
    while (_queue.isNotEmpty) {
      if (!Engine3D.instance.ready) {
        if (waited++ > 200) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        continue;
      }
      final sw = Stopwatch()..start();
      while (_queue.isNotEmpty && sw.elapsedMilliseconds < 24) {
        final it = _queue.removeLast(); // najnoviji zahtjev prvi (ono što je sad na ekranu)
        final k = it.thumbKey;
        _queued.remove(k);
        if (_cache.containsKey(k)) continue;
        try {
          final png = Engine3D.instance.thumbnail(it);
          if (png != null) _cache[k] = png;
        } catch (_) {}
        while (_cache.length > _max) {
          _cache.remove(_cache.keys.first);
        }
      }
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    _running = false;
  }
}
