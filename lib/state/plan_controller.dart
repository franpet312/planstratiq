import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset, Rect;

import '../models/catalog.dart';
import '../models/geometry.dart';
import '../models/materials.dart';
import '../models/plan.dart';
import '../models/topology.dart';

enum Tool { select, wall, room, door, window, balcony, passage, measure, calibrate, place }

extension ToolX on Tool {
  OpeningType? get openingType => switch (this) {
        Tool.door => OpeningType.door,
        Tool.window => OpeningType.window,
        Tool.balcony => OpeningType.balcony,
        Tool.passage => OpeningType.passage,
        _ => null,
      };
}

enum SelKind { none, wall, node, opening, item, room }

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
  RoomStat(this.room, this.area, this.perimeter, this.material);
  final Room room;
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
    required this.wallLength,
    required this.doors,
    required this.windows,
  });

  final List<RoomStat> rooms;
  final double footprint;
  final double paintArea;
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

  /// Vanjski obris zgrade (za bruto površinu i prikaz).
  List<List<Offset>> outlines = [];

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
    final img = plan.image;
    plan = Plan.fromJson(jsonDecode(s) as Map<String, dynamic>);
    plan.image = img;
    _syncRooms();
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
    );
    plan.items.add(it);
    selection = Selection(SelKind.item, it.id);
    return it;
  }

  /// Postavi objekt i, ako je blizu zida, okreni ga leđima prema zidu i prisloni.
  PlacedItem placeItemSmart(CatalogItem c, Offset p) {
    var rot = 0.0;
    var pos = p;
    if (c.zone == CatalogZone.interior && !floorShapes.contains(c.shape)) {
      final w = wallNear(p, tol: c.d / 2 + 0.45);
      if (w != null) {
        final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
        final q = closestOnSegment(p, a, b);
        final away = p - q;
        if (away.distance > 1e-6) {
          final n = away / away.distance;
          // stražnja strana objekta (lokalno -y) okrenuta je prema zidu (-n)
          rot = roundTo(math.atan2(-n.dx, n.dy), math.pi / 12);
          pos = q + n * (w.thickness / 2 + c.d / 2 + 0.01);
        }
      }
    }
    return placeItem(c, Offset(roundTo(pos.dx, 0.01), roundTo(pos.dy, 0.01)), rotation: rot);
  }

  void setNodePos(String id, Offset p) => plan.nodes[id]?.pos = p;
  void setItemPos(String id, Offset p) => plan.itemById(id)?.pos = p;

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
      if (height != null) plan.wallHeight = height;
    });
  }

  void updateOpening(String id,
      {OpeningType? type,
      double? width,
      double? height,
      double? sill,
      double? offsetFromStart,
      bool? flip,
      bool? swingOut}) {
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
          ..sill = p.sill;
      }
      if (width != null) o.width = width.clamp(0.3, math.max(0.3, len - 0.1));
      if (height != null) o.height = height.clamp(0.2, w.height);
      if (sill != null) o.sill = sill.clamp(0.0, math.max(0.0, w.height - o.height));
      if (offsetFromStart != null) o.t = offsetFromStart / len;
      if (flip != null) o.flip = flip;
      if (swingOut != null) o.swingOut = swingOut;
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
    mutate(() => it.rotation = (it.rotation + delta) % (2 * math.pi));
  }

  void duplicateItem(String id) {
    final it = plan.itemById(id);
    if (it == null) return;
    mutate(() {
      final copy =
          PlacedItem.fromJson({...it.toJson(), 'id': newId('i'), 'x': it.pos.dx + 0.3, 'y': it.pos.dy + 0.3});
      plan.items.add(copy);
      selection = Selection(SelKind.item, copy.id);
    });
  }

  void updateRoom(String id, {String? name, String? floor}) {
    final r = plan.roomById(id);
    if (r == null) return;
    mutate(() {
      if (name != null) r.name = name;
      if (floor != null) r.floor = floor;
    });
  }

  void setAllFloors(String floor) => mutate(() {
        for (final r in plan.rooms) {
          r.floor = floor;
        }
      });

  void setRoof(bool v) => mutate(() => plan.roof = v);

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
        case SelKind.none:
          break;
      }
      _cleanup();
      selection = Selection.none;
    });
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

  PlanStats _computeStats() {
    final rooms = <RoomStat>[];
    for (final r in plan.rooms) {
      final poly = plan.roomPolygon(r);
      if (poly.length < 3) continue;
      rooms.add(RoomStat(r, polygonArea(poly), polygonPerimeter(poly), floorById(r.floor)));
    }
    var paint = 0.0, length = 0.0;
    for (final w in plan.walls) {
      final len = plan.wallLength(w);
      length += len;
      final sides = wallSides(w);
      var area = len * w.height;
      for (final o in plan.openings.where((o) => o.wallId == w.id)) {
        area -= o.width * o.height;
      }
      paint += math.max(0, area) * sides;
    }
    return PlanStats(
      rooms: rooms,
      footprint: outlines.fold(0.0, (a, p) => a + polygonArea(p)),
      paintArea: paint,
      wallLength: length,
      doors: plan.openings.where((o) => o.type == OpeningType.door || o.type == OpeningType.balcony).length,
      windows: plan.openings.where((o) => o.type == OpeningType.window).length,
    );
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
