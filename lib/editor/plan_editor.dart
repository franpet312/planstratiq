import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/geometry.dart';
import '../models/plan.dart';
import '../state/plan_controller.dart';
import 'plan_painter.dart';

enum _DragKind { pan, node, wall, room, item, opening }

class _Drag {
  _Drag(
    this.kind, {
    required this.startWorld,
    required this.startScreen,
    this.startPan = Offset.zero,
    this.id = '',
    this.startNodes = const {},
    this.startPos = Offset.zero,
    this.normal = Offset.zero,
  });

  final _DragKind kind;
  final Offset startWorld;
  final Offset startScreen;
  final Offset startPan;
  final String id;
  final Map<String, Offset> startNodes;
  final Offset startPos;
  final Offset normal;
}

/// 2D uređivač tlocrta: crtanje zidova i soba, pomicanje zidova,
/// vrata/prozori, postavljanje namještaja, kalibracija nacrta.
class PlanEditor extends StatefulWidget {
  const PlanEditor({super.key, required this.c});
  final PlanController c;

  @override
  State<PlanEditor> createState() => PlanEditorState();
}

class PlanEditorState extends State<PlanEditor> {
  double scale = 55; // piksela po metru
  Offset pan = const Offset(80, 80);
  Offset? hover;
  Offset? wallStart;
  Offset? roomStart;
  Offset? roomEnd;
  Offset? calibA;
  _Drag? drag;
  bool _fitted = false;
  Size _size = Size.zero;
  final focusNode = FocusNode(debugLabel: 'plan-editor');

  PlanController get c => widget.c;
  Plan get plan => c.plan;

  Offset toWorld(Offset screen) => (screen - pan) / scale;

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  /// Uklopi cijeli tlocrt u prikaz.
  void fit() {
    if (_size.isEmpty) return;
    final pts = <Offset>[
      for (final n in plan.nodes.values) n.pos,
      for (final i in plan.items) i.pos,
    ];
    final im = plan.image;
    if (im != null) {
      pts.add(im.origin);
      pts.add(im.origin + Offset(im.widthPx * im.metersPerPixel, im.heightPx * im.metersPerPixel));
    }
    if (pts.isEmpty) {
      setState(() {
        scale = 55;
        pan = Offset(_size.width / 2, _size.height / 2);
      });
      return;
    }
    var minX = pts.first.dx, maxX = minX, minY = pts.first.dy, maxY = minY;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final bw = math.max(maxX - minX, 2.0) + 2, bh = math.max(maxY - minY, 2.0) + 2;
    setState(() {
      scale = math.min(_size.width / bw, _size.height / bh).clamp(8.0, 400.0);
      final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
      pan = Offset(_size.width / 2, _size.height / 2) - center * scale;
    });
  }

  void cancelTool() {
    wallStart = null;
    roomStart = null;
    roomEnd = null;
    calibA = null;
    if (c.tool == Tool.place) c.setTool(Tool.select);
    setState(() {});
  }

  // ------------------------------------------------------------- hvatanje

  Offset _gridSnap(Offset p, [double step = 0.05]) =>
      Offset(roundTo(p.dx, step), roundTo(p.dy, step));

  /// Hvatanje na postojeće čvorove, zatim na kutove 0/45/90° i korak 5 cm.
  Offset _snap(Offset w, {Offset? from, String? excludeNode}) {
    final tol = 12 / scale;
    for (final n in plan.nodes.values) {
      if (n.id == excludeNode) continue;
      if ((n.pos - w).distance < tol) return n.pos;
    }
    if (from != null) {
      final d = w - from;
      var len = d.distance;
      if (len == 0) return w;
      var ang = math.atan2(d.dy, d.dx);
      const step = math.pi / 4;
      final snapped = (ang / step).roundToDouble() * step;
      if ((ang - snapped).abs() < 5 * math.pi / 180) ang = snapped;
      len = roundTo(len, 0.05);
      return from + Offset(math.cos(ang), math.sin(ang)) * len;
    }
    // poravnanje s čvorovima po osi (x ili y)
    var x = roundTo(w.dx, 0.05), y = roundTo(w.dy, 0.05);
    for (final n in plan.nodes.values) {
      if (n.id == excludeNode) continue;
      if ((n.pos.dx - w.dx).abs() < tol) x = n.pos.dx;
      if ((n.pos.dy - w.dy).abs() < tol) y = n.pos.dy;
    }
    return Offset(x, y);
  }

  Selection _hitTest(Offset w) {
    final tol = 8 / scale;
    for (final it in plan.items.reversed) {
      final local = rotate(w - it.pos, -it.rotation);
      if (local.dx.abs() <= it.w / 2 && local.dy.abs() <= it.d / 2) {
        // velike podne površine (bazen/deck/tepih) imaju niži prioritet
        if (const {'rug', 'deck', 'pool'}.contains(it.shape)) continue;
        return Selection(SelKind.item, it.id);
      }
    }
    for (final o in plan.openings) {
      final wall = plan.wallById(o.wallId);
      if (wall == null) continue;
      final a = plan.nodePos(wall.a), b = plan.nodePos(wall.b);
      final len = (b - a).distance;
      final sAlong = projectT(w, a, b) * len;
      if ((sAlong - o.t * len).abs() <= o.width / 2 &&
          distToSegment(w, a, b) <= wall.thickness / 2 + tol) {
        return Selection(SelKind.opening, o.id);
      }
    }
    for (final n in plan.nodes.values) {
      if ((n.pos - w).distance <= 10 / scale) return Selection(SelKind.node, n.id);
    }
    for (final wall in plan.walls) {
      if (distToSegment(w, plan.nodePos(wall.a), plan.nodePos(wall.b)) <=
          wall.thickness / 2 + tol) {
        return Selection(SelKind.wall, wall.id);
      }
    }
    for (final it in plan.items.reversed) {
      final local = rotate(w - it.pos, -it.rotation);
      if (local.dx.abs() <= it.w / 2 && local.dy.abs() <= it.d / 2) {
        return Selection(SelKind.item, it.id);
      }
    }
    for (final r in plan.rooms.reversed) {
      final poly = plan.roomPolygon(r);
      if (poly.length >= 3 && pointInPolygon(w, poly)) return Selection(SelKind.room, r.id);
    }
    return Selection.none;
  }

  // ------------------------------------------------------------- pokazivač

  void _onDown(PointerDownEvent e) {
    focusNode.requestFocus();
    final w = toWorld(e.localPosition);
    final middle = (e.buttons & kMiddleMouseButton) != 0;
    final right = (e.buttons & kSecondaryMouseButton) != 0;
    if (middle || (right && c.tool == Tool.select)) {
      drag = _Drag(_DragKind.pan, startWorld: w, startScreen: e.localPosition, startPan: pan);
      return;
    }
    if (right) {
      cancelTool();
      return;
    }
    switch (c.tool) {
      case Tool.select:
        _selectDown(e, w);
      case Tool.wall:
        final p = _snap(w, from: wallStart);
        final start = wallStart;
        if (start == null) {
          wallStart = p;
        } else if ((p - start).distance < 0.05) {
          wallStart = null; // klik na istu točku završava niz zidova
        } else {
          c.mutate(() => c.addWall(start, p));
          wallStart = p;
        }
      case Tool.room:
        roomStart = _snap(w);
        roomEnd = roomStart;
      case Tool.door:
        c.mutate(() => c.addOpeningNear(w, OpeningType.door));
      case Tool.window:
        c.mutate(() => c.addOpeningNear(w, OpeningType.window));
      case Tool.calibrate:
        _calibClick(w);
      case Tool.place:
        final item = c.placing;
        if (item != null) {
          c.mutate(() => c.placeItem(item, _gridSnap(w)));
          c.setTool(Tool.select);
        }
    }
    setState(() {});
  }

  void _selectDown(PointerDownEvent e, Offset w) {
    final hit = _hitTest(w);
    c.select(hit);
    switch (hit.kind) {
      case SelKind.none:
        drag = _Drag(_DragKind.pan, startWorld: w, startScreen: e.localPosition, startPan: pan);
      case SelKind.node:
        c.beginChange();
        drag = _Drag(_DragKind.node, startWorld: w, startScreen: e.localPosition, id: hit.id);
      case SelKind.wall:
        final wall = plan.wallById(hit.id)!;
        final a = plan.nodePos(wall.a), b = plan.nodePos(wall.b);
        final len = (b - a).distance;
        if (len == 0) return;
        final dir = (b - a) / len;
        c.beginChange();
        drag = _Drag(_DragKind.wall,
            startWorld: w,
            startScreen: e.localPosition,
            id: hit.id,
            startNodes: {wall.a: a, wall.b: b},
            normal: Offset(-dir.dy, dir.dx));
      case SelKind.room:
        final r = plan.roomById(hit.id)!;
        c.beginChange();
        drag = _Drag(_DragKind.room,
            startWorld: w,
            startScreen: e.localPosition,
            id: hit.id,
            startNodes: {for (final id in r.nodeIds) id: plan.nodePos(id)});
      case SelKind.item:
        c.beginChange();
        drag = _Drag(_DragKind.item,
            startWorld: w,
            startScreen: e.localPosition,
            id: hit.id,
            startPos: plan.itemById(hit.id)!.pos);
      case SelKind.opening:
        c.beginChange();
        drag = _Drag(_DragKind.opening, startWorld: w, startScreen: e.localPosition, id: hit.id);
    }
  }

  void _onMove(PointerMoveEvent e) {
    final w = toWorld(e.localPosition);
    hover = w;
    final d = drag;
    if (d != null) {
      final delta = w - d.startWorld;
      switch (d.kind) {
        case _DragKind.pan:
          pan = d.startPan + (e.localPosition - d.startScreen);
        case _DragKind.node:
          c.setNodePos(d.id, _snap(w, excludeNode: d.id));
          c.liveUpdate();
        case _DragKind.wall:
          // zid se pomiče okomito na svoj smjer, u koracima od 1 cm
          final k = roundTo(dot(delta, d.normal), 0.01);
          d.startNodes.forEach((id, p) => c.setNodePos(id, p + d.normal * k));
          c.liveUpdate();
        case _DragKind.room:
          final dd = _gridSnap(delta);
          d.startNodes.forEach((id, p) => c.setNodePos(id, p + dd));
          c.liveUpdate();
        case _DragKind.item:
          c.setItemPos(d.id, d.startPos + _gridSnap(delta, 0.01));
          c.liveUpdate();
        case _DragKind.opening:
          c.slideOpening(d.id, w);
          c.liveUpdate();
      }
    } else if (c.tool == Tool.room && roomStart != null) {
      roomEnd = _snap(w);
    }
    setState(() {});
  }

  void _onUp(PointerUpEvent e) {
    final d = drag;
    drag = null;
    if (d != null && d.kind != _DragKind.pan) c.endChange();
    if (c.tool == Tool.room && roomStart != null && roomEnd != null) {
      final r = Rect.fromPoints(roomStart!, roomEnd!);
      if (r.width >= 0.5 && r.height >= 0.5) c.mutate(() => c.addRoomRect(r));
      roomStart = null;
      roomEnd = null;
    }
    setState(() {});
  }

  void _onHover(PointerHoverEvent e) => setState(() => hover = toWorld(e.localPosition));

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final f = math.exp(-e.scrollDelta.dy / 500);
      final ns = (scale * f).clamp(8.0, 400.0);
      setState(() {
        pan = e.localPosition - (e.localPosition - pan) * (ns / scale);
        scale = ns;
      });
    }
  }

  Future<void> _calibClick(Offset w) async {
    if (plan.image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prvo učitaj nacrt (slika) pa ga kalibriraj.')));
      return;
    }
    final a = calibA;
    if (a == null) {
      calibA = w;
      return;
    }
    calibA = null;
    final measured = (w - a).distance;
    final ctrl = TextEditingController(text: measured.toStringAsFixed(2));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kalibracija mjerila'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Kolika je stvarna udaljenost između te dvije točke?'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(suffixText: 'm', border: OutlineInputBorder()),
            onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s.replaceAll(',', '.'))),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Odustani')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))),
              child: const Text('Primijeni')),
        ],
      ),
    );
    if (v != null && v > 0) {
      c.mutate(() => c.calibrateImage(a, w, v));
      c.setTool(Tool.wall);
    }
    setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      cancelTool();
      c.select(Selection.none);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      c.deleteSelection();
      return KeyEventResult.handled;
    }
    if (c.selection.kind == SelKind.item) {
      if (k == LogicalKeyboardKey.keyR) {
        final shift = HardwareKeyboard.instance.isShiftPressed;
        c.rotateItem(c.selection.id, (shift ? -1 : 1) * math.pi / 2);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyD && HardwareKeyboard.instance.isControlPressed) {
        c.duplicateItem(c.selection.id);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => LayoutBuilder(builder: (context, box) {
        _size = box.biggest;
        if (!_fitted && !_size.isEmpty) {
          _fitted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => fit());
        }
        final wallEnd = (c.tool == Tool.wall && wallStart != null && hover != null)
            ? _snap(hover!, from: wallStart)
            : null;
        return Focus(
          focusNode: focusNode,
          onKeyEvent: _onKey,
          child: MouseRegion(
            cursor: switch (c.tool) {
              Tool.select => drag?.kind == _DragKind.pan
                  ? SystemMouseCursors.grabbing
                  : SystemMouseCursors.basic,
              _ => SystemMouseCursors.precise,
            },
            child: Listener(
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              onPointerHover: _onHover,
              onPointerSignal: _onSignal,
              child: ClipRect(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: PlanPainter(
                    c: c,
                    scale: scale,
                    pan: pan,
                    hover: hover,
                    wallStart: wallStart,
                    wallEnd: wallEnd,
                    roomStart: roomStart,
                    roomEnd: roomEnd,
                    calibA: calibA,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
