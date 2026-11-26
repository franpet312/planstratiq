import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset, Rect;

import 'package:web/web.dart' as web;
import '../models/catalog.dart';
import '../models/catalog_gen.dart';
import '../models/clearance.dart';
import '../models/collision.dart';
import '../models/geometry.dart';
import '../models/materials.dart';
import '../models/plan.dart';
import '../models/topology.dart';

enum Tool { select, wall, room, door, window, balcony, passage, measure, calibrate, place, note }

extension ToolX on Tool {
  OpeningType? get openingType => switch (this) {
        Tool.door => OpeningType.door,
        Tool.window => OpeningType.window,
        Tool.balcony => OpeningType.balcony,
        Tool.passage => OpeningType.passage,
        _ => null,
      };
}

enum SelKind { none, wall, node, opening, item, room, note }

class Selection {
  const Selection(this.kind, this.id);
  static const none = Selection(SelKind.none, '');
  final SelKind kind;
  final String id;

  @override
  bool operator ==(Object other) => other is Selection && other.kind == kind && other.id == id;
  @override
  int get hashCode => Object.hash(kind, id);
}

class RoomStat {
  RoomStat(this.room, this.area, this.perimeter, this.material, [this.level = '', this.levelIndex = 0]);
  final Room room;
  final String level;
  final int levelIndex;
  final double area;
  final double perimeter;
  final FloorMaterial material;
  double get floorCost => area * material.pricePerM2;
}

class PlanStats {
  PlanStats({
    required this.rooms,
    required this.footprint,
    required this.paintArea,
    this.finishAreas = const {},
    required this.wallLength,
    required this.doors,
    required this.windows,
  });

  final List<RoomStat> rooms;
  final double footprint;
  final double paintArea;

  /// Površine zidnih obloga po vrsti (m²), bez boje.
  final Map<String, double> finishAreas;
  double get finishCost => finishAreas.entries.fold(0.0, (a, e) => a + e.value * finishById(e.key).pricePerM2);
  final double wallLength;
  final int doors;
  final int windows;

  double get netArea => rooms.fold(0.0, (a, r) => a + r.area);
  double get floorCost => rooms.fold(0.0, (a, r) => a + r.floorCost);
  double get paintCost => paintArea * paintPricePerM2;
  double get paintLiters => paintArea * litersPerM2;
}

class _RoomHint {
  _RoomHint(this.point, this.name, this.floor);
  final Offset point;
  final String? name;
  final String? floor;
}

typedef PlanSaver = void Function(Plan plan);

/// Centralno stanje jednog projekta: tlocrt, alat, odabir, povijest, spremanje.
class PlanController extends ChangeNotifier {
  PlanController({required this.projectId, Plan? initial, this.onSave}) {
    if (initial != null) {
      plan = initial;
      _syncRooms();
      _decodePlanImage().then((_) {
        if (!_disposed) notifyListeners();
      });
    }
  }

  final String projectId;
  final PlanSaver? onSave;

  Plan plan = Plan();
  Tool tool = Tool.select;
  Selection selection = Selection.none;
  CatalogItem? placing;
  ui.Image? bgImage;

  /// Vanjski obris zgrade (za bruto površinu, podlogu i krov).
  List<List<Offset>> outlines = [];
  List<List<String>> outlineIds = [];

  /// Položaj osobe u 3D šetnji (prikazuje se na tlocrtu): pozicija i smjer.
  final walker = ValueNotifier<(Offset, double)?>(null);

  /// Stanje spremanja za prikaz u sučelju.
  final saveState = ValueNotifier<String>('Spremljeno');

  /// Raste pri svakoj promjeni geometrije – 3D prikaz prema tome osvježava scenu.
  int revision = 0;

  final List<String> _undo = [];
  final List<String> _redo = [];
  String? _pending;
  Timer? _saveTimer;
  final List<_RoomHint> _hints = [];
  PlanStats? _stats;
  bool _dirty = false;
  bool _disposed = false;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    if (_dirty) _saveNow();
    walker.dispose();
    saveState.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- povijest

  String _snapshot() => jsonEncode(plan.toJson(includeImage: false));

  void _restore(String s) {
    final images = {for (final l in plan.levels) l.id: l.image};
    final prevLevel = plan.level.id;
    plan = Plan.fromJson(jsonDecode(s) as Map<String, dynamic>);
    for (final l in plan.levels) {
      l.image = images[l.id];
    }
    _syncRooms();
    if (plan.level.id != prevLevel) _decodePlanImage().then((_) => _disposed ? null : notifyListeners());
    if (!_selectionValid()) selection = Selection.none;
  }

  void beginChange() => _pending ??= _snapshot();

  void endChange() {
    final before = _pending;
    _pending = null;
    _syncRooms();
    if (before != null && before != _snapshot()) {
      _undo.add(before);
      if (_undo.length > 200) _undo.removeAt(0);
      _redo.clear();
    }
    _changed();
  }

  void mutate(VoidCallback f) {
    beginChange();
    f();
    endChange();
  }

  /// Za vrijeme povlačenja: osvježi prikaz bez upisa u povijest.
  void liveUpdate() {
    revision++;
    _stats = null;
    _issues = null;
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
    _changed();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
    _changed();
  }

  void _changed() {
    revision++;
    _stats = null;
    _issues = null;
    notifyListeners();
    _dirty = true;
    saveState.value = 'Spremanje…';
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _saveNow);
  }

  void _saveNow() {
    _dirty = false;
    try {
      onSave?.call(plan);
      if (!_disposed) saveState.value = 'Spremljeno';
    } catch (_) {
      if (!_disposed) saveState.value = 'Nije spremljeno – premalo prostora u pregledniku';
    }
  }

  // ---------------------------------------------------------- alati / odabir

  void setTool(Tool t, {CatalogItem? item}) {
    tool = t;
    placing = t == Tool.place ? item : null;
    notifyListeners();
  }

  void select(Selection s) {
    if (s == selection) return;
    selection = s;
    notifyListeners();
  }

  bool _selectionValid() {
    final id = selection.id;
    return switch (selection.kind) {
      SelKind.none => true,
      SelKind.wall => plan.wallById(id) != null,
      SelKind.node => plan.nodes.containsKey(id),
      SelKind.opening => plan.openingById(id) != null,
      SelKind.note => plan.noteById(id) != null,
      SelKind.item => plan.itemById(id) != null,
      SelKind.room => plan.roomById(id) != null,
    };
  }

  // ------------------------------------------------------------- topologija

  String? _nodeNear(Offset p, {double tol = 0.02, String? except}) {
    String? best;
    var bestD = tol;
    for (final n in plan.nodes.values) {
      if (n.id == except) continue;
      final d = (n.pos - p).distance;
      if (d <= bestD) {
        bestD = d;
        best = n.id;
      }
    }
    return best;
  }

  bool _hasWall(String a, String b) => wallBetween(a, b) != null;

  Wall? wallBetween(String a, String b) {
    for (final w in plan.walls) {
      if ((w.a == a && w.b == b) || (w.a == b && w.b == a)) return w;
    }
    return null;
  }

  /// Podijeli zid u točki p; otvori se raspodijele na odgovarajući dio.
  String splitWall(Wall w, Offset p) {
    final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
    final len = (b - a).distance;
    final t = projectT(p, a, b).clamp(0.0, 1.0);
    final n = PlanNode(newId('n'), a + (b - a) * t);
    plan.nodes[n.id] = n;
    final w2 = w.copyWith(id: newId('w'), a: n.id, b: w.b);
    w.b = n.id;
    plan.walls.add(w2);
    final l1 = len * t, l2 = len * (1 - t);
    for (final o in plan.openings.where((o) => o.wallId == w.id).toList()) {
      final s = o.t * len;
      if (s <= l1) {
        o.t = l1 > 0 ? s / l1 : 0.5;
      } else {
        o.wallId = w2.id;
        o.t = l2 > 0 ? (s - l1) / l2 : 0.5;
      }
    }
    return n.id;
  }

  /// Vrati čvor u točki p: postojeći, novi na zidu (dijeli zid) ili novi slobodni.
  String _attach(Offset p) {
    final near = _nodeNear(p);
    if (near != null) return near;
    for (final w in plan.walls) {
      final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
      if (distToSegment(p, a, b) < 0.015) {
        final t = projectT(p, a, b);
        if (t > 0.001 && t < 0.999) return splitWall(w, p);
      }
    }
    final n = PlanNode(newId('n'), p);
    plan.nodes[n.id] = n;
    return n.id;
  }

  /// Dodaje zid; automatski se spaja i dijeli na sjecištima s postojećim zidovima.
  void addWall(Offset p1, Offset p2, {double thickness = 0.2}) {
    if ((p2 - p1).distance < 0.05) return;
    final a = _attach(p1), b = _attach(p2);
    if (a == b) return;
    final pa = plan.nodePos(a), pb = plan.nodePos(b);
    final splits = <(double, String)>[];
    for (final w in List<Wall>.from(plan.walls)) {
      if (w.a == a || w.b == a || w.a == b || w.b == b) continue;
      final r = segmentIntersection(pa, pb, plan.nodePos(w.a), plan.nodePos(w.b));
      if (r == null) continue;
      final (t, u) = r;
      if (t <= 1e-3 || t >= 1 - 1e-3) continue;
      final String nid;
      if (u <= 1e-3) {
        nid = w.a;
      } else if (u >= 1 - 1e-3) {
        nid = w.b;
      } else {
        nid = splitWall(w, pa + (pb - pa) * t);
      }
      splits.add((t, nid));
    }
    for (final n in plan.nodes.values) {
      if (n.id == a || n.id == b) continue;
      final t = projectT(n.pos, pa, pb);
      if (t > 1e-3 && t < 1 - 1e-3 && distToSegment(n.pos, pa, pb) < 0.01) {
        splits.add((t, n.id));
      }
    }
    splits.sort((x, y) => x.$1.compareTo(y.$1));
    final chain = <String>[a];
    for (final s in splits) {
      if (chain.last != s.$2) chain.add(s.$2);
    }
    if (chain.last != b) chain.add(b);
    Wall? last;
    for (var i = 0; i + 1 < chain.length; i++) {
      final x = chain[i], y = chain[i + 1];
      if (x == y || _hasWall(x, y)) continue;
      last = Wall(id: newId('w'), a: x, b: y, thickness: thickness, height: plan.wallHeight);
      plan.walls.add(last);
    }
    if (last != null) selection = Selection(SelKind.wall, last.id);
  }

  void addRoomRect(Rect r, {String? name, String? floor, double thickness = 0.2}) {
    final c = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
    for (var i = 0; i < 4; i++) {
      addWall(c[i], c[(i + 1) % 4], thickness: thickness);
    }
    _hints.add(_RoomHint(r.center, name, floor));
    selection = Selection.none;
  }

  /// Ako je čvor spušten na drugi čvor ili na zid – spoji ih.
  void mergeNodeIfClose(String id) {
    final n = plan.nodes[id];
    if (n == null) return;
    final other = _nodeNear(n.pos, tol: 0.03, except: id);
    if (other != null) {
      _replaceNode(id, other);
      return;
    }
    for (final w in List<Wall>.from(plan.walls)) {
      if (w.a == id || w.b == id) continue;
      final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
      final t = projectT(n.pos, a, b);
      if (t > 0.01 && t < 0.99 && distToSegment(n.pos, a, b) < 0.02) {
        final split = splitWall(w, n.pos);
        _replaceNode(id, split);
        return;
      }
    }
  }

  void _replaceNode(String from, String to) {
    for (final w in plan.walls) {
      if (w.a == from) w.a = to;
      if (w.b == from) w.b = to;
    }
    plan.walls.removeWhere((w) => w.a == w.b);
    final seen = <String>{};
    plan.walls.removeWhere((w) {
      final k = w.a.compareTo(w.b) < 0 ? '${w.a}|${w.b}' : '${w.b}|${w.a}';
      return !seen.add(k);
    });
    plan.nodes.remove(from);
    if (selection == Selection(SelKind.node, from)) selection = Selection(SelKind.node, to);
    _cleanup();
  }

  /// Ponovno prepoznaj prostorije; postojećima se čuvaju naziv i pod.
  void _syncRooms() {
    final res = detectFaces(plan);
    outlines = res.outlines;
    outlineIds = res.outlineIds;
    final old = List<Room>.from(plan.rooms);
    final used = <Room>{};
    final next = <Room>[];
    for (final f in res.faces) {
      final key = f.toSet();
      final poly = [for (final id in f) plan.nodePos(id)];
      Room? match;
      for (final r in old) {
        if (used.contains(r)) continue;
        if (r.nodeIds.length == f.length && key.containsAll(r.nodeIds)) {
          match = r;
          break;
        }
      }
      if (match == null) {
        for (final r in old) {
          if (used.contains(r)) continue;
          final op = plan.roomPolygon(r);
          if (op.length >= 3 && pointInPolygon(labelPoint(op), poly)) {
            match = r;
            break;
          }
        }
      }
      if (match != null) {
        used.add(match);
        match.nodeIds = f;
        next.add(match);
      } else {
        final room = Room(id: newId('r'), name: '', nodeIds: f);
        for (final h in _hints) {
          if (pointInPolygon(h.point, poly)) {
            if (h.name != null) room.name = h.name!;
            if (h.floor != null) room.floor = h.floor!;
            break;
          }
        }
        next.add(room);
      }
    }
    for (final r in next) {
      if (r.name.isEmpty) r.name = _nextRoomName(next);
    }
    _hints.clear();
    plan.rooms
      ..clear()
      ..addAll(next);
    if (selection.kind == SelKind.room && plan.roomById(selection.id) == null) {
      selection = Selection.none;
    }
  }

  String _nextRoomName(List<Room> rooms) {
    var i = 1;
    while (rooms.any((r) => r.name == 'Prostorija $i')) {
      i++;
    }
    return 'Prostorija $i';
  }

  // ------------------------------------------------------------ otvori

  static double clampOpeningT(double length, double width, double t) {
    final m = (width / 2 + 0.05) / length;
    if (m >= 0.5) return 0.5;
    return t.clamp(m, 1 - m);
  }

  Opening? addOpening(String wallId, OpeningType type, double t) {
    final w = plan.wallById(wallId);
    if (w == null) return null;
    final len = plan.wallLength(w);
    if (len < 0.62) return null;
    final o = Opening.preset(wallId, type, t);
    if (len < o.width + 0.1) o.width = math.max(0.5, len - 0.12);
    o.height = math.min(o.height, w.height - o.sill - 0.05);
    o.t = clampOpeningT(len, o.width, t);
    plan.openings.add(o);
    selection = Selection(SelKind.opening, o.id);
    return o;
  }

  Wall? wallNear(Offset p, {double tol = 0.3}) {
    Wall? best;
    var bestD = tol;
    for (final w in plan.walls) {
      final d = distToSegment(p, plan.nodePos(w.a), plan.nodePos(w.b));
      if (d < bestD) {
        bestD = d;
        best = w;
      }
    }
    return best;
  }

  Opening? addOpeningNear(Offset p, OpeningType type, {double tol = 0.3}) {
    final w = wallNear(p, tol: tol);
    if (w == null) return null;
    final t = projectT(p, plan.nodePos(w.a), plan.nodePos(w.b));
    return addOpening(w.id, type, t);
  }

  void slideOpening(String id, Offset p) {
    final o = plan.openingById(id);
    final w = o == null ? null : plan.wallById(o.wallId);
    if (o == null || w == null) return;
    final len = plan.wallLength(w);
    final t = projectT(p, plan.nodePos(w.a), plan.nodePos(w.b));
    o.t = clampOpeningT(len, o.width, roundTo(t * len, 0.05) / len);
  }

  // ------------------------------------------------------------ namještaj

  PlacedItem placeItem(CatalogItem c, Offset p, {double rotation = 0}) {
    final it = PlacedItem(
      id: newId('i'),
      catalogId: c.id,
      name: c.name,
      shape: c.shape,
      pos: p,
      rotation: rotation,
      w: c.w,
      d: c.d,
      h: c.h,
      color: c.color,
      price: c.price,
      modelUrl: c.modelUrl,
      retailer: c.retailer,
      style: c.style,
      legs: c.legs,
      productUrl: c.productUrl,
    );
    plan.items.add(it);
    selection = Selection(SelKind.item, it.id);
    return it;
  }

  /// Postavi objekt i, ako je blizu zida, okreni ga leđima prema zidu i prisloni.
  PlacedItem placeItemSmart(CatalogItem c, Offset p) {
    var rot = 0.0;
    var pos = p;
    if (balconyShapes.contains(c.shape)) {
      // balkon se prisloni uz vanjsku stranu najbližeg zida
      final w = wallNear(p, tol: c.d + 1.2);
      if (w != null) {
        final (q, n) = _outsideOf(w, p);
        rot = math.atan2(-n.dx, n.dy);
        pos = q + n * (w.thickness / 2 + c.d / 2);
      }
    } else if (ceilingShapes.contains(c.shape) || c.shape == 'table_lamp') {
      // stropna i stolna rasvjeta: točno gdje je pušteno, bez prislanjanja uz zid
    } else if (c.zone == CatalogZone.interior && !floorShapes.contains(c.shape)) {
      final onWall = c.shape == 'wall_lamp' || electricWall.containsKey(c.shape);
      final w = wallNear(p, tol: onWall ? 1.5 : c.d / 2 + 0.45);
      if (w != null) {
        final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
        final q = closestOnSegment(p, a, b);
        final away = p - q;
        if (away.distance > 1e-6) {
          final n = away / away.distance;
          // stražnja strana objekta (lokalno -y) okrenuta je prema zidu (-n)
          rot = roundTo(math.atan2(-n.dx, n.dy), math.pi / 12);
          pos = q + n * (w.thickness / 2 + c.d / 2 + (onWall ? 0.002 : 0.01));
          if (onWall) rot = math.atan2(-n.dx, n.dy); // točno uz zid, bez zaokruživanja kuta
        }
      }
    }
    final it = placeItem(c, Offset(roundTo(pos.dx, 0.01), roundTo(pos.dy, 0.01)), rotation: rot);
    if (collisions) {
      final r = resolveItemPos(plan, it, it.pos);
      if (r != null) it.pos = Offset(roundTo(r.dx, 0.005), roundTo(r.dy, 0.005));
    }
    return it;
  }

  /// Najbliža točka na osi zida i normala prema van (strana na kojoj nije prostorija).
  (Offset, Offset) _outsideOf(Wall w, Offset near) {
    final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
    final q = closestOnSegment(near, a, b);
    final v = b - a;
    final dir = v / math.max(v.distance, 1e-9);
    var n = Offset(-dir.dy, dir.dx);
    bool inRoom(Offset x) => plan.rooms.any((r) => pointInPolygon(x, plan.roomPolygon(r)));
    final probe = w.thickness / 2 + 0.3;
    final plusIn = inRoom(q + n * probe), minusIn = inRoom(q - n * probe);
    if (plusIn && !minusIn) {
      n = -n;
    } else if (plusIn == minusIn && dot(near - q, n) < 0) {
      n = -n; // neodređeno: strana na kojoj je kursor
    }
    return (q, n);
  }

  /// Dodaj balkon uz vanjski zid; ako zid nema balkonska vrata, doda ih na sredinu.
  PlacedItem? addBalcony(String wallId, {String familyId = 'balkon', String? openingId}) {
    final w = plan.wallById(wallId);
    if (w == null) return null;
    PlacedItem? out;
    mutate(() {
      final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
      final len = (b - a).distance;
      if (len < 1.0) return;
      final ops = plan.openings.where((o) => o.wallId == w.id).toList();
      var door = ops.where((o) => o.id == openingId).firstOrNull ??
          ops.where((o) => o.type == OpeningType.balcony).firstOrNull ??
          ops.where((o) => o.type == OpeningType.door || o.type == OpeningType.passage).firstOrNull;
      door ??= addOpening(w.id, OpeningType.balcony, 0.5);
      final t = door?.t ?? 0.5;
      final model = catalogModels.firstWhere((m) => m.family.id == familyId, orElse: () => catalogModels.firstWhere((m) => m.family.id == 'balkon'));
      final base = model.variants[model.variants.length ~/ model.family.sizes.length]; // druga veličina
      final width = math.min(len - 0.1, math.max(base.w, (door?.width ?? 1.6) + 1.2)).clamp(1.2, 5.0).toDouble();
      final along = a + (b - a) * t;
      final (q, n) = _outsideOf(w, along + Offset(0.001, 0.001));
      final depth = base.d;
      final it = placeItem(base, q + n * (w.thickness / 2 + depth / 2), rotation: math.atan2(-n.dx, n.dy));
      it.w = roundTo(width, 0.05);
      it.name = '${model.family.name} ${(it.w * 100).round()} × ${(depth * 100).round()}';
      out = it;
    });
    return out;
  }

  void setNodePos(String id, Offset p) => plan.nodes[id]?.pos = p;

  // --------------------------------------------------------- bilješke
  Note addNote(Offset p, String text) {
    final n = Note(id: newId('n'), pos: p, text: text);
    mutate(() {
      plan.notes.add(n);
      selection = Selection(SelKind.note, n.id);
    });
    return n;
  }

  void updateNote(String id, {String? text, int? color}) {
    final n = plan.noteById(id);
    if (n == null) return;
    mutate(() {
      if (text != null) n.text = text;
      if (color != null) n.color = color;
    });
  }
  /// Pomakni objekt; uz uključeno sudaranje klizi uz zidove i druge objekte.
  void setItemPos(String id, Offset p) {
    final it = plan.itemById(id);
    if (it == null) return;
    if (!collisions) {
      it.pos = p;
      return;
    }
    final r = resolveItemPos(plan, it, p);
    if (r != null) {
      it.pos = Offset(roundTo(r.dx, 0.005), roundTo(r.dy, 0.005));
    } else if (itemOverlaps(plan, it)) {
      it.pos = p; // već je zaglavljen (npr. ne stane u prostoriju) – pusti ga da ga se izvuče
    }
  }

  /// Pomakni objekt tako da razmak sa strane [side] do prepreke bude točno [value] m.
  void setItemGap(String id, String side, double value) {
    final it = plan.itemById(id);
    if (it == null) return;
    final g = itemGaps(plan, it).where((g) => g.side == side).firstOrNull;
    if (g == null || g.distance < 1e-6) return;
    final dir = (g.to - g.from) / g.distance;
    mutate(() => setItemPos(id, it.pos + dir * (g.distance - math.max(0, value))));
  }

  /// Okreni objekt; ako se pri okretanju zabije u nešto, odmakne se (ili ostane kako je bio).
  bool setItemRotation(String id, double rot) {
    final it = plan.itemById(id);
    if (it == null) return false;
    if (!collisions) {
      it.rotation = rot;
      return true;
    }
    final r = resolveItemPos(plan, it, it.pos, rot: rot);
    if (r == null) {
      if (!itemOverlaps(plan, it)) return false;
      it.rotation = rot;
      return true;
    }
    it.rotation = rot;
    it.pos = r;
    return true;
  }

  /// Sudaranje namještaja sa zidovima i drugim namještajem (pamti se u pregledniku).
  bool get collisions => _collisions;
  bool _collisions = _loadCollisions();
  static bool _loadCollisions() {
    try {
      return web.window.localStorage.getItem('psq.collide') != '0';
    } catch (_) {
      return true;
    }
  }

  void setCollisions(bool v) {
    _collisions = v;
    try {
      web.window.localStorage.setItem('psq.collide', v ? '1' : '0');
    } catch (_) {}
    notifyListeners();
  }

  /// Promijeni duljinu zida – pomiče se krajnja točka B, spojeni zidovi prate.
  void setWallLength(String wallId, double len) {
    final w = plan.wallById(wallId);
    if (w == null || len < 0.1) return;
    mutate(() {
      final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
      final cur = (b - a).distance;
      if (cur == 0) return;
      setNodePos(w.b, a + (b - a) / cur * len);
    });
  }

  void updateWall(String id, {double? thickness, double? height, int? color}) {
    final w = plan.wallById(id);
    if (w == null) return;
    mutate(() {
      if (thickness != null) w.thickness = thickness.clamp(0.05, 1.0);
      if (height != null) w.height = height.clamp(0.3, 10.0);
      if (color != null) w.color = color;
    });
  }

  void applyToAllWalls({double? height, int? color}) {
    mutate(() {
      for (final w in plan.walls) {
        if (height != null) w.height = height;
        if (color != null) w.color = color;
      }
      if (height != null) {
        plan.wallHeight = height;
        plan.restackLevels();
      }
    });
  }

  void updateOpening(String id,
      {OpeningType? type,
      double? width,
      double? height,
      double? sill,
      double? offsetFromStart,
      bool? flip,
      bool? swingOut,
      String? style}) {
    final o = plan.openingById(id);
    final w = o == null ? null : plan.wallById(o.wallId);
    if (o == null || w == null) return;
    mutate(() {
      final len = plan.wallLength(w);
      if (type != null && type != o.type) {
        final p = Opening.preset(o.wallId, type, o.t);
        o
          ..type = type
          ..width = math.min(p.width, len - 0.12)
          ..height = math.min(p.height, w.height - p.sill - 0.05)
          ..sill = p.sill
          ..style = '';
      }
      if (width != null) o.width = width.clamp(0.3, math.max(0.3, len - 0.1));
      if (height != null) o.height = height.clamp(0.2, w.height);
      if (sill != null) o.sill = sill.clamp(0.0, math.max(0.0, w.height - o.height));
      if (offsetFromStart != null) o.t = offsetFromStart / len;
      if (flip != null) o.flip = flip;
      if (swingOut != null) o.swingOut = swingOut;
      if (style != null) {
        o.style = style;
        // dvokrilna vrata su šira
        if (style == 'double' && o.width < 1.2) o.width = math.min(1.4, len - 0.12);
      }
      o.t = clampOpeningT(len, o.width, o.t);
    });
  }

  void updateItem(String id, {double? w, double? d, double? h, double? rotation, int? color, String? name}) {
    final it = plan.itemById(id);
    if (it == null) return;
    mutate(() {
      if (w != null) it.w = w.clamp(0.05, 50.0);
      if (d != null) it.d = d.clamp(0.01, 50.0);
      if (h != null) it.h = h.clamp(0.005, 30.0);
      if (rotation != null) it.rotation = rotation;
      if (color != null) it.color = color;
      if (name != null) it.name = name;
    });
  }

  void rotateItem(String id, double delta) {
    final it = plan.itemById(id);
    if (it == null) return;
    mutate(() => setItemRotation(id, (it.rotation + delta) % (2 * math.pi)));
  }

  void duplicateItem(String id) {
    final it = plan.itemById(id);
    if (it == null) return;
    mutate(() {
      final copy =
          PlacedItem.fromJson({...it.toJson(), 'id': newId('i'), 'x': it.pos.dx + 0.3, 'y': it.pos.dy + 0.3});
      plan.items.add(copy);
      if (collisions) {
        // kopiju stavi do originala, na prvo slobodno mjesto
        final r = it.rotation;
        final ux = Offset(math.cos(r), math.sin(r)), uz = Offset(-math.sin(r), math.cos(r));
        for (final off in [ux * (it.w + 0.05), -ux * (it.w + 0.05), uz * (it.d + 0.05), -uz * (it.d + 0.05)]) {
          final q = it.pos + off;
          if (!itemOverlaps(plan, copy, pos: q)) {
            copy.pos = q;
            break;
          }
          final rq = resolveItemPos(plan, copy, q);
          if (rq != null) {
            copy.pos = rq;
            break;
          }
        }
      }
      selection = Selection(SelKind.item, copy.id);
    });
  }

  void updateRoom(String id, {String? name, String? floor, String? wallFinish, int? wallColor, bool clearWallColor = false, double? finishHeight}) {
    final r = plan.roomById(id);
    if (r == null) return;
    mutate(() {
      if (name != null) r.name = name;
      if (floor != null) r.floor = floor;
      if (wallFinish != null) r.wallFinish = wallFinish;
      if (wallColor != null) r.wallColor = wallColor;
      if (clearWallColor) r.wallColor = null;
      if (finishHeight != null) r.finishHeight = finishHeight;
    });
  }

  /// Prostorije uz zid i strana na kojoj su: +1 = lijevo od smjera a→b (lokalni +z u 3D-u), −1 = desno.
  List<(Room, int)> roomsBeside(Wall w) {
    final out = <(Room, int)>[];
    final wd = plan.nodePos(w.b) - plan.nodePos(w.a);
    final n = Offset(-wd.dy, wd.dx);
    for (final r in plan.rooms) {
      final ids = r.nodeIds;
      for (var i = 0; i < ids.length; i++) {
        final a = ids[i], b = ids[(i + 1) % ids.length];
        if ((a == w.a && b == w.b) || (a == w.b && b == w.a)) {
          final d = plan.nodePos(b) - plan.nodePos(a);
          final inward = Offset(-d.dy, d.dx);
          out.add((r, dot(inward, n) >= 0 ? 1 : -1));
          break;
        }
      }
    }
    return out;
  }

  void setAllFloors(String floor) => mutate(() {
        for (final r in plan.rooms) {
          r.floor = floor;
        }
      });

  void setRoof(bool v) => mutate(() => plan.roof = v);

  void setRoofStyle({String? type, double? pitch, double? overhang, int? color, bool? turn}) => mutate(() {
        plan.roof = true;
        if (type != null) plan.roofType = type;
        if (pitch != null) plan.roofPitch = pitch.clamp(5, 60).toDouble();
        if (overhang != null) plan.roofOverhang = overhang.clamp(0, 1.5).toDouble();
        if (color != null) plan.roofColor = color;
        if (turn != null) plan.roofTurn = turn;
      });

  void deleteSelection() {
    final s = selection;
    if (s.kind == SelKind.none) return;
    mutate(() {
      switch (s.kind) {
        case SelKind.wall:
          plan.walls.removeWhere((w) => w.id == s.id);
        case SelKind.node:
          plan.walls.removeWhere((w) => w.a == s.id || w.b == s.id);
          plan.nodes.remove(s.id);
        case SelKind.opening:
          plan.openings.removeWhere((o) => o.id == s.id);
        case SelKind.item:
          plan.items.removeWhere((i) => i.id == s.id);
        case SelKind.room:
          _deleteRoomWalls(s.id);
        case SelKind.note:
          plan.notes.removeWhere((n) => n.id == s.id);
        case SelKind.none:
          break;
      }
      _cleanup();
      selection = Selection.none;
    });
  }

  // --------------------------------------------------------- parcela i okolina

  /// Obuhvat kuće (svi zidovi svih etaža).
  Rect? houseBounds() {
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final l in plan.levels) {
      for (final n in l.nodes.values) {
        minX = math.min(minX, n.pos.dx);
        maxX = math.max(maxX, n.pos.dx);
        minY = math.min(minY, n.pos.dy);
        maxY = math.max(maxY, n.pos.dy);
      }
    }
    if (!minX.isFinite) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Parcela: zadana širina/dubina ili automatski oko kuće (ulica ispred, vrt iza).
  Rect? siteRect() {
    final h = houseBounds();
    if (h == null) return null;
    final s = plan.site;
    const side = 4.0, front = 7.0, back = 9.0;
    double l = side, r = side, t = side, b = side;
    switch (s.street) {
      case 'N':
        t = front;
        b = back;
      case 'E':
        r = front;
        l = back;
      case 'W':
        l = front;
        r = back;
      default:
        b = front;
        t = back;
    }
    var rect = Rect.fromLTRB(h.left - l, h.top - t, h.right + r, h.bottom + b);
    if (s.width > 0 || s.depth > 0) {
      rect = Rect.fromCenter(
        center: rect.center,
        width: s.width > 0 ? s.width : rect.width,
        height: s.depth > 0 ? s.depth : rect.height,
      );
    }
    return rect.shift(Offset(s.offsetX, s.offsetY));
  }

  /// Ulazna vrata prizemlja okrenuta prema ulici (za prilaz), ili null.
  Offset? entranceTowardStreet() {
    final g = plan.levels[plan.groundIndex];
    final dir = switch (plan.site.street) { 'N' => const Offset(0, -1), 'E' => const Offset(1, 0), 'W' => const Offset(-1, 0), _ => const Offset(0, 1) };
    Offset? best;
    var bestScore = -double.infinity;
    for (final o in g.openings) {
      if (o.type != OpeningType.door && o.type != OpeningType.passage) continue;
      final w = g.walls.where((w) => w.id == o.wallId).firstOrNull;
      if (w == null) continue;
      final a = g.nodes[w.a]?.pos, b = g.nodes[w.b]?.pos;
      if (a == null || b == null) continue;
      final c = a + (b - a) * o.t;
      final score = dot(c, dir);
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  void updateSite(void Function(Site s) f) => mutate(() => f(plan.site));

  // --------------------------------------------------------- međuspremnik (Ctrl+C / Ctrl+V)

  /// Kopirano: namještaj ili cijela prostorija (zidovi, otvori, namještaj). Dijeli se među projektima.
  static Map<String, dynamic>? clipboard;

  String? get clipboardLabel => switch (clipboard?['kind']) {
        'item' => (clipboard!['items'] as List).length == 1 ? 'objekt' : 'objekte',
        'room' => 'prostoriju „${clipboard!['name']}”',
        _ => null,
      };

  /// Kopiraj odabrano. Vraća opis kopiranog ili null.
  String? copySelection() {
    final s = selection;
    if (s.kind == SelKind.item) {
      final it = plan.itemById(s.id);
      if (it == null) return null;
      clipboard = {'kind': 'item', 'level': plan.level.id, 'project': projectId, 'items': [it.toJson()]};
      return it.name;
    }
    if (s.kind == SelKind.room) {
      final r = plan.roomById(s.id);
      if (r == null) return null;
      final poly = plan.roomPolygon(r);
      final edges = <Map<String, dynamic>>[];
      for (var i = 0; i < r.nodeIds.length; i++) {
        final a = r.nodeIds[i], b = r.nodeIds[(i + 1) % r.nodeIds.length];
        final w = wallBetween(a, b);
        if (w == null) continue;
        final pa = plan.nodePos(w.a), pb = plan.nodePos(w.b);
        edges.add({
          'ax': pa.dx, 'ay': pa.dy, 'bx': pb.dx, 'by': pb.dy, 't': w.thickness, 'h': w.height, 'color': w.color,
          'openings': [
            for (final o in plan.openings.where((o) => o.wallId == w.id))
              {...o.toJson(), 'cx': pa.dx + (pb.dx - pa.dx) * o.t, 'cy': pa.dy + (pb.dy - pa.dy) * o.t}
          ],
        });
      }
      final items = [
        for (final it in plan.items)
          if (pointInPolygon(it.pos, poly)) it.toJson()
      ];
      var minX = double.infinity, maxX = -double.infinity;
      for (final p in poly) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
      }
      final lp = labelPoint(poly);
      clipboard = {
        'kind': 'room', 'level': plan.level.id, 'project': projectId, 'name': r.name, 'floor': r.floor,
        'wallFinish': r.wallFinish, 'wallColor': r.wallColor, 'finishHeight': r.finishHeight,
        'cx': lp.dx, 'cy': lp.dy, 'width': maxX - minX, 'edges': edges, 'items': items,
      };
      return r.name;
    }
    return null;
  }

  /// Izreži odabrano (kopiraj pa obriši).
  String? cutSelection() {
    final what = copySelection();
    if (what != null) deleteSelection();
    return what;
  }

  /// Zalijepi na aktivnu etažu. Na istoj etaži istog projekta pomakne kopiju u stranu,
  /// na drugoj etaži zalijepi na isto mjesto (npr. kupaonica iznad kupaonice).
  String? paste() {
    final cb = clipboard;
    if (cb == null) return null;
    final sameSpot = cb['level'] == plan.level.id && cb['project'] == projectId;
    String? result;
    mutate(() {
      if (cb['kind'] == 'item') {
        for (final j in (cb['items'] as List).cast<Map<String, dynamic>>()) {
          final it = PlacedItem.fromJson({...j, 'id': newId('i')});
          plan.items.add(it);
          if (sameSpot) {
            final q = it.pos + Offset(it.w * 0.5 + 0.3, it.d * 0.5 + 0.3);
            it.pos = collisions ? (resolveItemPos(plan, it, q) ?? q) : q;
          } else if (collisions) {
            it.pos = resolveItemPos(plan, it, it.pos) ?? it.pos;
          }
          selection = Selection(SelKind.item, it.id);
          result = it.name;
        }
        return;
      }
      // prostorija
      final d = sameSpot ? Offset((cb['width'] as num).toDouble() + 1.0, 0) : Offset.zero;
      Offset pt(num x, num y) => Offset(x.toDouble(), y.toDouble()) + d;
      final edges = (cb['edges'] as List).cast<Map<String, dynamic>>();
      for (final e in edges) {
        addWall(pt(e['ax'] as num, e['ay'] as num), pt(e['bx'] as num, e['by'] as num), thickness: (e['t'] as num).toDouble());
      }
      // svojstva zidova i otvori
      for (final e in edges) {
        final a = pt(e['ax'] as num, e['ay'] as num), b = pt(e['bx'] as num, e['by'] as num);
        for (final w in plan.walls) {
          final wa = plan.nodePos(w.a), wb = plan.nodePos(w.b);
          if (distToSegment(wa, a, b) < 0.02 && distToSegment(wb, a, b) < 0.02) {
            w.height = (e['h'] as num).toDouble();
            if (e['color'] is int) w.color = e['color'] as int;
          }
        }
        for (final oj in (e['openings'] as List).cast<Map<String, dynamic>>()) {
          final c = pt(oj['cx'] as num, oj['cy'] as num);
          final w = wallNear(c, tol: 0.05);
          if (w == null) continue;
          final wa = plan.nodePos(w.a), wb = plan.nodePos(w.b);
          final len = (wb - wa).distance;
          final t = projectT(c, wa, wb);
          final exists = plan.openings.any((o) => o.wallId == w.id && (o.t - t).abs() * len < 0.3);
          if (exists) continue;
          final o = Opening.fromJson({...oj, 'id': newId('o'), 'wallId': w.id, 't': t});
          o.t = clampOpeningT(len, o.width, t);
          plan.openings.add(o);
        }
      }
      for (final j in (cb['items'] as List).cast<Map<String, dynamic>>()) {
        final it = PlacedItem.fromJson({...j, 'id': newId('i')});
        it.pos += d;
        plan.items.add(it);
      }
      _syncRooms();
      final c = pt(cb['cx'] as num, cb['cy'] as num);
      for (final r in plan.rooms) {
        if (pointInPolygon(c, plan.roomPolygon(r))) {
          r.name = cb['name'] as String;
          if (cb['floor'] is String) r.floor = cb['floor'] as String;
          if (cb['wallFinish'] is String) r.wallFinish = cb['wallFinish'] as String;
          r.wallColor = cb['wallColor'] as int?;
          r.finishHeight = (cb['finishHeight'] as num?)?.toDouble() ?? 0;
          selection = Selection(SelKind.room, r.id);
          break;
        }
      }
      result = cb['name'] as String;
    });
    return result;
  }

  /// Brisanje prostorije uklanja njezine zidove koje ne dijeli s drugima.
  void _deleteRoomWalls(String roomId) {
    final r = plan.roomById(roomId);
    if (r == null) return;
    final shared = <String>{};
    for (final o in plan.rooms) {
      if (o.id == roomId) continue;
      for (var i = 0; i < o.nodeIds.length; i++) {
        final w = wallBetween(o.nodeIds[i], o.nodeIds[(i + 1) % o.nodeIds.length]);
        if (w != null) shared.add(w.id);
      }
    }
    final remove = <String>{};
    for (var i = 0; i < r.nodeIds.length; i++) {
      final w = wallBetween(r.nodeIds[i], r.nodeIds[(i + 1) % r.nodeIds.length]);
      if (w != null && !shared.contains(w.id)) remove.add(w.id);
    }
    plan.walls.removeWhere((w) => remove.contains(w.id));
  }

  void _cleanup() {
    final wallIds = {for (final w in plan.walls) w.id};
    plan.openings.removeWhere((o) => !wallIds.contains(o.wallId));
    final used = <String>{for (final w in plan.walls) ...[w.a, w.b]};
    plan.nodes.removeWhere((id, _) => !used.contains(id));
  }

  // ------------------------------------------------------------ statistika

  /// Koliko prostorija graniči sa zidom (1 = vanjski zid, 2 = unutarnji).
  int wallSides(Wall w) {
    var n = 0;
    for (final r in plan.rooms) {
      final ids = r.nodeIds;
      for (var i = 0; i < ids.length; i++) {
        final a = ids[i], b = ids[(i + 1) % ids.length];
        if ((a == w.a && b == w.b) || (a == w.b && b == w.a)) {
          n++;
          break;
        }
      }
    }
    return n;
  }

  PlanStats get stats => _stats ??= _computeStats();

  /// Provjera prolaza i otvaranja na aktivnoj etaži.
  List<ClearanceIssue> get issues => _issues ??= checkClearances(plan);
  List<ClearanceIssue>? _issues;

  /// Prikaži upozorenja o prolazima na tlocrtu.
  bool showIssues = true;
  void setShowIssues(bool v) {
    showIssues = v;
    notifyListeners();
  }

  /// Statistika cijele zgrade (sve etaže).
  PlanStats _computeStats() {
    final rooms = <RoomStat>[];
    var paint = 0.0, length = 0.0, footprint = 0.0;
    final finishes = <String, double>{};
    var doors = 0, windows = 0;
    final prev = plan.active;
    final multi = plan.levels.length > 1;
    for (var li = 0; li < plan.levels.length; li++) {
      plan.active = li;
      final lvlName = multi ? plan.level.name : '';
      for (final r in plan.rooms) {
        final poly = plan.roomPolygon(r);
        if (poly.length < 3) continue;
        rooms.add(RoomStat(r, roomNetArea(plan, r), polygonPerimeter(poly), floorById(r.floor), lvlName, li));
      }
      for (final w in plan.walls) {
        final len = plan.wallLength(w);
        length += len;
        var area = len * w.height;
        for (final o in plan.openings.where((o) => o.wallId == w.id)) {
          area -= o.width * o.height;
        }
        area = math.max(0, area);
        for (final (r, _) in roomsBeside(w)) {
          if (r.wallFinish == 'paint') {
            paint += area;
            continue;
          }
          final part = r.finishHeight <= 0 ? 1.0 : (r.finishHeight / w.height).clamp(0.0, 1.0);
          finishes[r.wallFinish] = (finishes[r.wallFinish] ?? 0) + area * part;
          paint += area * (1 - part);
        }
      }
      final res = li == prev ? null : detectFaces(plan);
      final outs = res?.outlines ?? outlines;
      final outIds = res?.outlineIds ?? outlineIds;
      for (var i = 0; i < outs.length; i++) {
        footprint += offsetArea(outs[i], edgeHalfThickness(plan, outIds[i]), inward: false);
      }
      doors += plan.openings.where((o) => o.type == OpeningType.door || o.type == OpeningType.balcony).length;
      windows += plan.openings.where((o) => o.type == OpeningType.window).length;
    }
    plan.active = prev;
    return PlanStats(
      rooms: rooms,
      footprint: footprint,
      paintArea: paint,
      finishAreas: finishes,
      wallLength: length,
      doors: doors,
      windows: windows,
    );
  }

  /// Podaci etaže [i] za 3D: obrisi zgrade i strana zidova prema interijeru.
  (List<List<Offset>>, Map<String, int>) levelSceneData(int i) {
    final prev = plan.active;
    plan.active = i;
    final outs = i == prev ? outlines : detectFaces(plan).outlines;
    final sides = <String, int>{for (final w in plan.walls) w.id: wallSides(w)};
    plan.active = prev;
    return (outs, sides);
  }

  // --------------------------------------------------------- nacrt (slika)

  Future<void> loadImageBytes(Uint8List bytes, String mime) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    bgImage = img;
    plan.image = PlanImage(
      dataUrl: 'data:${mime.isEmpty ? 'image/png' : mime};base64,${base64Encode(bytes)}',
      origin: Offset.zero,
      metersPerPixel: 15 / img.width,
      widthPx: img.width,
      heightPx: img.height,
    );
    _changed();
  }

  /// Slike nacrta stigle su naknadno (iz IndexedDB-a) – dekodiraj i osvježi prikaz.
  void imagesAttached() {
    _decodePlanImage().then((_) {
      if (_disposed) return;
      revision++;
      notifyListeners();
    });
  }

  Future<void> _decodePlanImage() async {
    final im = plan.image;
    if (im == null) {
      bgImage = null;
      return;
    }
    try {
      final bytes = base64Decode(im.dataUrl.substring(im.dataUrl.indexOf(',') + 1));
      final codec = await ui.instantiateImageCodec(bytes);
      bgImage = (await codec.getNextFrame()).image;
    } catch (_) {
      bgImage = null;
    }
  }

  void calibrateImage(Offset p1, Offset p2, double meters) {
    final im = plan.image;
    final dist = (p2 - p1).distance;
    if (im == null || dist <= 0 || meters <= 0) return;
    final pixelDist = dist / im.metersPerPixel;
    final newMpp = meters / pixelDist;
    final p1Px = (p1 - im.origin) / im.metersPerPixel;
    im.metersPerPixel = newMpp;
    im.origin = p1 - p1Px * newMpp;
  }

  void setImageOpacity(double v) {
    plan.image?.opacity = v;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveNow);
  }

  void removeImage() {
    plan.image = null;
    bgImage = null;
    _changed();
  }

  // ------------------------------------------------------- spremanje / učitavanje

  String exportJson() => const JsonEncoder.withIndent('  ').convert(plan.toJson());

  void rename(String name) => mutate(() => plan.name = name);

  /// Zamijeni sadržaj (npr. predložak) – sve u jednoj promjeni, može se poništiti.
  // ---------------------------------------------------------------- etaže

  /// Prebaci se na etažu [i] (tlocrt, 3D i statistika prate aktivnu etažu).
  void switchLevel(int i) {
    if (i == plan.active || i < 0 || i >= plan.levels.length) return;
    plan.active = i;
    selection = Selection.none;
    if (tool == Tool.place || tool == Tool.calibrate) tool = Tool.select;
    placing = null;
    _syncRooms();
    bgImage = null;
    _decodePlanImage().then((_) {
      if (!_disposed) notifyListeners();
    });
    revision++;
    _stats = null;
    _issues = null;
    notifyListeners();
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _saveNow);
  }

  static String levelNameFor(int floorNo) {
    if (floorNo == 0) return 'Prizemlje';
    if (floorNo < 0) return floorNo == -1 ? 'Podrum' : 'Podrum ${-floorNo}';
    return '$floorNo. kat';
  }

  /// Dodaj etažu iznad najviše ili ispod najniže. [copyShell]: preuzmi vanjske zidove susjedne etaže.
  void addLevel({required bool above, bool copyShell = true}) {
    mutate(() {
      final ref = above ? plan.levels.last : plan.levels.first;
      final g = plan.groundIndex;
      final floorNo = above ? plan.levels.length - 1 - g + 1 : -(g + 1);
      final lvl = Level(id: newId('L'), name: levelNameFor(floorNo), height: ref.height);
      if (copyShell) {
        // preuzmi obodne zidove (one uz koje je prostorija samo s jedne strane) i čvorove
        final prev = plan.active;
        plan.active = plan.levels.indexOf(ref);
        final res = detectFaces(plan);
        final outerIds = <String>{};
        for (final ids in res.outlineIds) {
          for (var k = 0; k < ids.length; k++) {
            final a = ids[k], b = ids[(k + 1) % ids.length];
            for (final w in ref.walls) {
              if ((w.a == a && w.b == b) || (w.a == b && w.b == a)) outerIds.add(w.id);
            }
          }
        }
        final idMap = <String, String>{};
        String mapNode(String id) => idMap.putIfAbsent(id, () {
              final nid = newId('n');
              lvl.nodes[nid] = PlanNode(nid, ref.nodes[id]!.pos);
              return nid;
            });
        for (final w in ref.walls.where((w) => outerIds.contains(w.id))) {
          if (!ref.nodes.containsKey(w.a) || !ref.nodes.containsKey(w.b)) continue;
          lvl.walls.add(w.copyWith(id: newId('w'), a: mapNode(w.a), b: mapNode(w.b))..height = lvl.height);
        }
        plan.active = prev;
      }
      if (above) {
        plan.levels.add(lvl);
      } else {
        plan.levels.insert(0, lvl);
      }
      plan.restackLevels();
      plan.active = plan.levels.indexOf(lvl);
      selection = Selection.none;
      bgImage = null;
    });
  }

  void deleteLevel(int i) {
    if (plan.levels.length <= 1) return;
    mutate(() {
      final a = plan.active;
      plan.levels.removeAt(i);
      plan.active = (a > i ? a - 1 : (a == i ? i - 1 : a)).clamp(0, plan.levels.length - 1);
      plan.restackLevels();
      selection = Selection.none;
    });
    bgImage = null;
    _decodePlanImage().then((_) {
      if (!_disposed) notifyListeners();
    });
  }

  void renameLevel(int i, String name) {
    if (name.trim().isEmpty) return;
    mutate(() => plan.levels[i].name = name.trim());
  }

  void setLevelHeight(int i, double h) {
    mutate(() {
      final l = plan.levels[i];
      final old = l.height;
      l.height = h.clamp(2.0, 6.0);
      for (final w in l.walls) {
        if ((w.height - old).abs() < 0.001) w.height = l.height;
      }
      plan.restackLevels();
    });
  }

  void replaceWith(void Function(PlanController c) build) {
    mutate(() {
      final name = plan.name;
      final image = plan.image;
      plan = Plan(name: name, image: image);
      build(this);
      selection = Selection.none;
    });
  }
}
