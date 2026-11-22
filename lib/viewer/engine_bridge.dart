import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../models/catalog.dart';
import '../models/geometry.dart';
import '../models/materials.dart';
import '../state/plan_controller.dart';

@JS('Planstratiq3D')
external _Engine get _js;

extension type _Engine._(JSObject _) implements JSObject {
  external bool? get ready;
  external JSFunction? get wantsKeys;
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

  /// True kad 3D prikaz (treće/prvo lice) preuzima tipkovnicu – editor tada ne smije reagirati.
  bool get wantsKeys {
    final f = _js.wantsKeys;
    if (f == null) return false;
    final r = f.callAsFunction();
    return r is JSBoolean && r.toDart;
  }

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
  void setShowAll(bool v) => _js.setOptions(jsonEncode({'showAll': v}));
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
  /// Aktivna etaža je na vrhu objekta; ostale etaže su u `others` (samo za prikaz).
  static Map<String, dynamic> sceneJson(PlanController c) {
    final plan = c.plan;
    final active = plan.active;
    final top = plan.levels.last;
    final (topOutlines, _) = c.levelSceneData(plan.levels.length - 1);
    return {
      'projectId': c.projectId,
      'roof': plan.roof,
      ..._levelJson(c, active),
      'others': [
        for (var i = 0; i < plan.levels.length; i++)
          if (i != active) _levelJson(c, i)
      ],
      'roofLevel': {
        'y': top.elevation + top.height,
        'outlines': [
          for (final o in topOutlines) [for (final p in o) [p.dx, p.dy]]
        ],
      },
    };
  }

  /// Otvori u podu za stubišta: pravokutnici stubišta s etaže [li] (u tlocrtnim koordinatama).
  static List<List<List<double>>> _stairHoles(PlanController c, int li) {
    if (li < 0 || li >= c.plan.levels.length) return const [];
    final out = <List<List<double>>>[];
    for (final it in c.plan.levels[li].items) {
      if (it.shape != 'stairs') continue;
      final cs = math.cos(it.rotation), sn = math.sin(it.rotation);
      final hw = it.w / 2 - 0.02, hd = it.d / 2 - 0.02;
      out.add([
        for (final (lx, ly) in [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)])
          [it.pos.dx + lx * cs - ly * sn, it.pos.dy + lx * sn + ly * cs]
      ]);
    }
    return out;
  }

  static Map<String, dynamic> _levelJson(PlanController c, int li) {
    final (outlines, sides) = c.levelSceneData(li);
    final plan = c.plan;
    final holes = _stairHoles(c, li - 1);
    final ceilHoles = li < plan.levels.length - 1 ? _stairHoles(c, li) : const <List<List<double>>>[];
    final prev = plan.active;
    plan.active = li;
    try {
      final inside = <String, int>{};
      for (final w in plan.walls) {
        if (sides[w.id] != 1) {
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
        'elevation': plan.level.elevation,
        'wallHeight': plan.wallHeight,
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
          for (final o in outlines) [for (final p in o) [p.dx, p.dy]]
        ],
        'items': plan.items.map((i) => i.toJson()).toList(),
        'holes': holes,
        'stairsBelow': [
          if (li > 0)
            for (final it in plan.levels[li - 1].items)
              if (it.shape == 'stairs') {'x': it.pos.dx, 'y': it.pos.dy, 'w': it.w, 'd': it.d, 'h': it.h, 'rotation': it.rotation}
        ],
        'hasAbove': li < plan.levels.length - 1,
        'hasBelow': li > 0,
        'ceilHoles': ceilHoles,
      };
    } finally {
      plan.active = prev;
    }
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
