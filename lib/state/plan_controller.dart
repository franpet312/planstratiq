import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset, Rect;
import 'package:web/web.dart' as web;

import '../models/catalog.dart';
import '../models/geometry.dart';
import '../models/plan.dart';

enum Tool { select, wall, room, door, window, calibrate, place }

enum SelKind { none, wall, node, opening, item, room }

class Selection {
  const Selection(this.kind, this.id);
  static const none = Selection(SelKind.none, '');
  final SelKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is Selection && other.kind == kind && other.id == id;
  @override
  int get hashCode => Object.hash(kind, id);
}

/// Centralno stanje projekta: tlocrt, alat, odabir, undo/redo, spremanje.
class PlanController extends ChangeNotifier {
  static const _storageKey = 'planstratiq.autosave.v1';

  Plan plan = Plan();
  Tool tool = Tool.select;
  Selection selection = Selection.none;
  CatalogItem? placing;
  ui.Image? bgImage;

  /// Raste pri svakoj promjeni geometrije – 3D prikaz prema tome osvježava scenu.
  int revision = 0;

  final List<String> _undo = [];
  final List<String> _redo = [];
  String? _pending;
  Timer? _saveTimer;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  Future<void> init() async {
    try {
      final saved = web.window.localStorage.getItem(_storageKey);
      if (saved != null && saved.isNotEmpty) {
        await importJson(saved, keepHistory: false);
        return;
      }
    } catch (_) {/* oštećen autosave – krećemo s demo kućom */}
    loadDemo();
  }

  // ---------------------------------------------------------------- povijest

  String _snapshot() => jsonEncode(plan.toJson(includeImage: false));

  void _restore(String s) {
    final img = plan.image;
    plan = Plan.fromJson(jsonDecode(s) as Map<String, dynamic>);
    plan.image = img;
    if (!_selectionValid()) selection = Selection.none;
  }

  void beginChange() => _pending ??= _snapshot();

  void endChange() {
    final before = _pending;
    _pending = null;
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
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _autosave);
  }

  void _autosave() {
    try {
      web.window.localStorage.setItem(_storageKey, jsonEncode(plan.toJson()));
    } catch (_) {
      // Prevelika slika nacrta za localStorage – spremi bez nje.
      try {
        web.window.localStorage
            .setItem(_storageKey, jsonEncode(plan.toJson(includeImage: false)));
      } catch (_) {}
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

  // ------------------------------------------------------------- geometrija

  String nodeAt(Offset p, {double tol = 0.02}) {
    for (final n in plan.nodes.values) {
      if ((n.pos - p).distance <= tol) return n.id;
    }
    final n = PlanNode(newId('n'), p);
    plan.nodes[n.id] = n;
    return n.id;
  }

  bool _hasWall(String a, String b) => plan.walls
      .any((w) => (w.a == a && w.b == b) || (w.a == b && w.b == a));

  /// Dodaje zid između dvije točke (spaja se na postojeće čvorove).
  void addWall(Offset p1, Offset p2, {double thickness = 0.2}) {
    if ((p2 - p1).distance < 0.05) return;
    final a = nodeAt(p1), b = nodeAt(p2);
    if (a == b || _hasWall(a, b)) return;
    final w = Wall(id: newId('w'), a: a, b: b, thickness: thickness);
    plan.walls.add(w);
    selection = Selection(SelKind.wall, w.id);
  }

  Room addRoomRect(Rect r, {String? name, int? floorColor}) {
    final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
    final ids = [for (final p in corners) nodeAt(p, tol: 0.05)];
    for (var i = 0; i < 4; i++) {
      final a = ids[i], b = ids[(i + 1) % 4];
      if (!_hasWall(a, b)) {
        plan.walls.add(Wall(id: newId('w'), a: a, b: b));
      }
    }
    final room = Room(
      id: newId('r'),
      name: name ?? 'Soba ${plan.rooms.length + 1}',
      nodeIds: ids,
      floorColor: floorColor ?? 0xFFD8C3A5,
    );
    plan.rooms.add(room);
    selection = Selection(SelKind.room, room.id);
    return room;
  }

  static double clampOpeningT(double length, double width, double t) {
    final m = (width / 2 + 0.05) / length;
    if (m >= 0.5) return 0.5;
    return t.clamp(m, 1 - m);
  }

  Opening? addOpening(String wallId, OpeningType type, double t) {
    final w = plan.wallById(wallId);
    if (w == null) return null;
    final len = plan.wallLength(w);
    final o = Opening.preset(wallId, type, t);
    if (len < o.width + 0.1) return null;
    o.t = clampOpeningT(len, o.width, t);
    plan.openings.add(o);
    selection = Selection(SelKind.opening, o.id);
    return o;
  }

  Opening? addOpeningNear(Offset p, OpeningType type, {double tol = 0.3}) {
    Wall? best;
    var bestD = tol;
    for (final w in plan.walls) {
      final d = distToSegment(p, plan.nodePos(w.a), plan.nodePos(w.b));
      if (d < bestD) {
        bestD = d;
        best = w;
      }
    }
    if (best == null) return null;
    final t = projectT(p, plan.nodePos(best.a), plan.nodePos(best.b));
    return addOpening(best.id, type, t);
  }

  void slideOpening(String id, Offset p) {
    final o = plan.openingById(id);
    final w = o == null ? null : plan.wallById(o.wallId);
    if (o == null || w == null) return;
    final len = plan.wallLength(w);
    final t = projectT(p, plan.nodePos(w.a), plan.nodePos(w.b));
    o.t = clampOpeningT(len, o.width, roundTo(t * len, 0.05) / len);
  }

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
      modelUrl: c.modelUrl,
      retailer: c.retailer,
    );
    plan.items.add(it);
    selection = Selection(SelKind.item, it.id);
    return it;
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

  void applyToAllWalls({double? thickness, double? height, int? color}) {
    mutate(() {
      for (final w in plan.walls) {
        if (thickness != null) w.thickness = thickness;
        if (height != null) w.height = height;
        if (color != null) w.color = color;
      }
    });
  }

  void updateOpening(String id,
      {OpeningType? type,
      double? width,
      double? height,
      double? sill,
      double? offsetFromStart}) {
    final o = plan.openingById(id);
    final w = o == null ? null : plan.wallById(o.wallId);
    if (o == null || w == null) return;
    mutate(() {
      final len = plan.wallLength(w);
      if (type != null && type != o.type) {
        o.type = type;
        if (type == OpeningType.door) o.sill = 0;
        if (type == OpeningType.window && o.sill == 0) o.sill = 0.9;
      }
      if (width != null) o.width = width.clamp(0.3, math.max(0.3, len - 0.1));
      if (height != null) o.height = height.clamp(0.2, w.height);
      if (sill != null) o.sill = sill.clamp(0.0, w.height - o.height);
      if (offsetFromStart != null) o.t = offsetFromStart / len;
      o.t = clampOpeningT(len, o.width, o.t);
    });
  }

  void updateItem(String id,
      {double? w, double? d, double? h, double? rotation, int? color, String? name}) {
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
      final copy = PlacedItem.fromJson({
        ...it.toJson(),
        'id': newId('i'),
        'x': it.pos.dx + 0.3,
        'y': it.pos.dy + 0.3,
      });
      plan.items.add(copy);
      selection = Selection(SelKind.item, copy.id);
    });
  }

  void updateRoom(String id, {String? name, int? floorColor}) {
    final r = plan.roomById(id);
    if (r == null) return;
    mutate(() {
      if (name != null) r.name = name;
      if (floorColor != null) r.floorColor = floorColor;
    });
  }

  void deleteSelection() {
    final s = selection;
    if (s.kind == SelKind.none) return;
    mutate(() {
      switch (s.kind) {
        case SelKind.wall:
          plan.walls.removeWhere((w) => w.id == s.id);
        case SelKind.node:
          plan.walls.removeWhere((w) => w.a == s.id || w.b == s.id);
          plan.rooms.removeWhere((r) => r.nodeIds.contains(s.id));
          plan.nodes.remove(s.id);
        case SelKind.opening:
          plan.openings.removeWhere((o) => o.id == s.id);
        case SelKind.item:
          plan.items.removeWhere((i) => i.id == s.id);
        case SelKind.room:
          plan.rooms.removeWhere((r) => r.id == s.id);
        case SelKind.none:
          break;
      }
      _cleanup();
      selection = Selection.none;
    });
  }

  void _cleanup() {
    final wallIds = {for (final w in plan.walls) w.id};
    plan.openings.removeWhere((o) => !wallIds.contains(o.wallId));
    final used = <String>{
      for (final w in plan.walls) ...[w.a, w.b],
      for (final r in plan.rooms) ...r.nodeIds,
    };
    plan.nodes.removeWhere((id, _) => !used.contains(id));
    plan.rooms
        .removeWhere((r) => r.nodeIds.any((id) => !plan.nodes.containsKey(id)));
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
      // Pretpostavka dok se ne kalibrira: nacrt je širok 15 m.
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

  /// Kalibracija: dvije točke na nacrtu i njihova stvarna udaljenost.
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
    _saveTimer = Timer(const Duration(milliseconds: 800), _autosave);
  }

  void removeImage() {
    plan.image = null;
    bgImage = null;
    _changed();
  }

  // ------------------------------------------------------- spremanje / učitavanje

  String exportJson() => const JsonEncoder.withIndent('  ').convert(plan.toJson());

  Future<void> importJson(String s, {bool keepHistory = false}) async {
    final p = Plan.fromJson(jsonDecode(s) as Map<String, dynamic>);
    plan = p;
    if (!keepHistory) {
      _undo.clear();
      _redo.clear();
    }
    selection = Selection.none;
    await _decodePlanImage();
    _changed();
  }

  void newPlan() {
    plan = Plan();
    bgImage = null;
    selection = Selection.none;
    _undo.clear();
    _redo.clear();
    tool = Tool.select;
    _changed();
  }

  void rename(String name) => mutate(() => plan.name = name);

  /// Primjer kuće ~10 × 8 m s četiri prostorije i okućnicom.
  void loadDemo() {
    plan = Plan(name: 'Demo kuća');
    bgImage = null;
    _undo.clear();
    _redo.clear();

    addRoomRect(const Rect.fromLTRB(0, 0, 6, 5), name: 'Dnevni boravak', floorColor: 0xFFC8A98A);
    addRoomRect(const Rect.fromLTRB(6, 0, 10, 5), name: 'Spavaća soba', floorColor: 0xFFD9C3A3);
    addRoomRect(const Rect.fromLTRB(0, 5, 6, 8), name: 'Kuhinja', floorColor: 0xFFD6D3CC);
    addRoomRect(const Rect.fromLTRB(6, 5, 10, 8), name: 'Kupaonica', floorColor: 0xFFB9C7CF);

    // Vanjski zidovi deblji.
    for (final w in plan.walls) {
      final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
      final outer = (a.dx == 0 && b.dx == 0) ||
          (a.dx == 10 && b.dx == 10) ||
          (a.dy == 0 && b.dy == 0) ||
          (a.dy == 8 && b.dy == 8);
      if (outer) w.thickness = 0.3;
    }

    addOpeningNear(const Offset(1.2, 0), OpeningType.window);
    addOpeningNear(const Offset(5.0, 0), OpeningType.window);
    addOpeningNear(const Offset(8, 0), OpeningType.window);
    addOpeningNear(const Offset(10, 6.5), OpeningType.window);
    addOpeningNear(const Offset(0, 6.5), OpeningType.window);
    addOpeningNear(const Offset(5.3, 8), OpeningType.door); // ulaz
    addOpeningNear(const Offset(6, 3.8), OpeningType.door);
    addOpeningNear(const Offset(2.2, 5), OpeningType.door);
    addOpeningNear(const Offset(6, 6.8), OpeningType.door);

    void put(String id, double x, double y, [double rotDeg = 0]) {
      final c = catalogById(id);
      if (c != null) placeItem(c, Offset(x, y), rotation: rotDeg * math.pi / 180);
    }

    // Dnevni boravak
    put('rug', 2.9, 2.4, 90);
    put('sofa_3', 2.9, 3.9, 180);
    put('coffee_table', 2.9, 2.7);
    put('tv_unit', 2.9, 0.45);
    put('armchair', 0.8, 2.4, 270);
    put('bookshelf', 5.6, 1.6, 90);
    put('plant', 0.5, 0.6);
    put('floor_lamp', 4.3, 4.3);
    // Spavaća
    put('bed_160', 8.0, 1.4);
    put('nightstand', 6.9, 0.4);
    put('nightstand', 9.1, 0.4);
    put('wardrobe_150', 8.4, 4.45, 180);
    // Kuhinja
    put('kitchen_block', 1.5, 7.55, 180);
    put('fridge', 0.5, 5.5, 270);
    put('dining_table', 4.1, 6.4);
    put('chair', 3.6, 5.8);
    put('chair', 4.6, 5.8);
    put('chair', 3.6, 7.0, 180);
    put('chair', 4.6, 7.0, 180);
    // Kupaonica
    put('bathtub', 8.9, 7.45);
    put('toilet', 9.5, 5.6, 0);
    put('vanity', 7.6, 5.4, 0);
    // Okućnica
    put('deck', 3.0, -2.0);
    put('garden_table', 3.0, -2.0);
    put('lounger', 7.0, -2.2, 90);
    put('umbrella', 4.6, -2.6);
    put('tree', -3.5, -2.5);
    put('tree_small', 12.5, 2.0);
    put('hedge', -2.0, 10.5);
    put('hedge', 0.0, 10.5);
    put('path', 3.0, 10.2);
    put('car', 8.2, 11.5, 90);
    put('pool', 3.0, -7.5);

    selection = Selection.none;
    _changed();
  }
}
