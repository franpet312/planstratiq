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
import '../models/stairs.dart';
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
  void setMeasure(bool v) => _js.setOptions(jsonEncode({'measure': v}));
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
      'roofStyle': {
        'type': plan.roofType,
        'pitch': plan.roofPitch,
        'overhang': plan.roofOverhang,
        'color': plan.roofColor,
        'turn': plan.roofTurn,
        if (plan.gableKind != 'same') 'gable': {'kind': plan.gableKind, if (plan.gableKind == 'plaster') 'color': plan.facadeColor},
      },
      'site': _siteJson(c),
      ..._levelJson(c, active),
      'others': [
        for (var i = 0; i < plan.levels.length; i++)
          if (i != active) _levelJson(c, i)
      ],
      'roofLevel': {
        'y': top.elevation + (top.attic ? top.kneeWall : top.height),
        'attic': top.attic,
        // pola debljine najdebljeg vanjskog zida najviše etaže (lice zabata = lice zida)
        'wt': top.walls.isEmpty ? 0.15 : top.walls.map((w) => w.thickness).reduce((a, b) => a > b ? a : b) / 2,
        'outlines': [
          for (final o in topOutlines) [for (final p in o) [p.dx, p.dy]]
        ],
      },
    };
  }

  /// Otvori u podu za stubišta: pravokutnici stubišta s etaže [li] (u tlocrtnim koordinatama).
  static List<List<List<double>>> _stairHoles(PlanController c, int li) {
    if (li < 0 || li >= c.plan.levels.length) return const [];
    return [
      for (final it in c.plan.levels[li].items)
        if (stairShapes.contains(it.shape)) [for (final p in stairOutline(it)) [p.dx, p.dy]]
    ];
  }

  static Map<String, dynamic>? _siteJson(PlanController c) {
    final r = c.siteRect();
    final h = c.houseBounds();
    if (r == null || h == null) return null;
    final s = c.plan.site;
    final door = c.entranceTowardStreet();
    return {
      'rect': [r.left, r.top, r.right, r.bottom],
      'house': [h.left, h.top, h.right, h.bottom],
      'street': s.street,
      'fence': s.fence,
      'fenceH': s.fenceHeight,
      'env': s.surroundings,
      'driveway': s.driveway,
      'neighbors': s.neighbors,
      if (s.slope > 0) ...{
        'slope': s.slope / 100,
        'down': [c.slopeDown().dx, c.slopeDown().dy],
        'pad': [c.terrainPad()!.left, c.terrainPad()!.top, c.terrainPad()!.right, c.terrainPad()!.bottom],
      },
      if (door != null) 'door': [door.dx, door.dy],
    };
  }

  /// Završna obrada svake strane zida prema prostoriji uz nju ('p' = lokalni +z, 'n' = −z).
  static Map<String, dynamic> _wallSides(PlanController c, Wall w) {
    final out = <String, dynamic>{};
    for (final (r, sign) in c.roomsBeside(w)) {
      final f = finishById(r.wallFinish);
      out[sign > 0 ? 'p' : 'n'] = {
        'paint': r.wallColor ?? w.color,
        if (f.id != 'paint') 'color': f.color,
        if (f.texture != null) 'tex': f.texture,
        if (f.id != 'paint') 'h': r.finishHeight,
      };
    }
    return out;
  }

  /// Fasada etaže: donja zona (cokl/kamen) samo u prizemlju, podrum cijeli u donjoj oblozi,
  /// potkrovlje u oblozi zabata.
  static Map<String, dynamic> _facadeJson(Plan plan, int li) {
    final l = plan.levels[li];
    final isTop = li == plan.levels.length - 1;
    var hi = plan.facadeKind;
    int? hiColor = plan.facadeKind == 'plaster' ? plan.facadeColor : null;
    if (isTop && l.attic && plan.roof && plan.gableKind != 'same') {
      hi = plan.gableKind;
      hiColor = hi == 'plaster' ? plan.facadeColor : null;
    }
    final base = plan.baseKind;
    var h = 0.0;
    if (base != 'none') {
      if (l.elevation < -0.5) {
        h = 99;
      } else if (li == plan.groundIndex) {
        h = plan.baseHeight;
      }
    }
    // podrum je ispod terena: vanjski zidovi su beton (ako nije odabrana druga donja obloga)
    if (l.elevation < -0.5 && base == 'none') return {'hi': hi, 'hiColor': hiColor, 'lo': 'concrete', 'loColor': null, 'h': 99};
    final baseColor = base == 'plaster' ? _darken(plan.facadeColor, 0.25) : null;
    return {'hi': hi, 'hiColor': hiColor, 'lo': base == 'none' ? hi : base, 'loColor': baseColor ?? (base == 'none' ? hiColor : null), 'h': h};
  }

  static int _darken(int c, double f) {
    int ch(int v) => (v * (1 - f)).round().clamp(0, 255);
    return 0xFF000000 | (ch((c >> 16) & 0xFF) << 16) | (ch((c >> 8) & 0xFF) << 8) | ch(c & 0xFF);
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
        'attic': plan.level.attic && li == plan.levels.length - 1 && plan.roof,
        'kneeWall': plan.level.kneeWall,
        'facade': _facadeJson(plan, li),
        'joinery': plan.joineryColor,
        'slabAbove': plan.levels.any((o) => o.elevation > plan.levels[li].elevation + 0.5),
        'nodes': {for (final n in plan.nodes.values) n.id: {'x': n.pos.dx, 'y': n.pos.dy}},
        'walls': [
          for (final w in plan.walls) {...w.toJson(), 'inside': inside[w.id] ?? 0, 'sides': _wallSides(c, w)}
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
              if (stairShapes.contains(it.shape))
                {'shape': it.shape, 'x': it.pos.dx, 'y': it.pos.dy, 'w': it.w, 'd': it.d, 'h': it.h, 'rotation': it.rotation}
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
