import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../models/catalog.dart';
import '../models/geometry.dart';
import '../models/plan.dart';
import '../state/plan_controller.dart';
import 'plan_painter.dart';

enum _DragKind { pan, node, wall, room, item, rotate, opening, image }

class _Drag {
  _Drag(this.kind,
      {required this.startWorld,
      required this.startScreen,
      this.startPan = Offset.zero,
      this.id = '',
      this.startNodes = const {},
      this.startPos = Offset.zero,
      this.normal = Offset.zero,
      this.startRot = 0});

  final _DragKind kind;
  final Offset startWorld;
  final Offset startScreen;
  final Offset startPan;
  final String id;
  final Map<String, Offset> startNodes;
  final Offset startPos;
  final Offset normal;
  final double startRot;
  bool moved = false;
}

/// 2D uređivač tlocrta.
class PlanEditor extends StatefulWidget {
  const PlanEditor({super.key, required this.c, this.onEmptyAction, this.zoom});
  final PlanController c;

  /// Trenutno mjerilo (piksela po metru) za prikaz mjerila u sučelju.
  final ValueNotifier<double>? zoom;

  /// Akcije praznog projekta: 'room', 'image', 'template'.
  final void Function(String action)? onEmptyAction;

  @override
  State<PlanEditor> createState() => PlanEditorState();
}

class PlanEditorState extends State<PlanEditor> {
  double scale = 50;
  Offset pan = const Offset(80, 80);
  Offset? cursor;
  Offset? wallStart;
  String? chainStartNode;
  Offset? roomStart;
  Offset? roomEnd;
  Offset? measureA;
  Offset? measureB;
  Offset? calibA;
  String typed = '';
  Selection hover = Selection.none;
  List<(Offset, Offset)> guides = [];
  (CatalogItem, Offset)? dropGhost;
  _Drag? drag;
  bool _fitted = false;
  Size _size = Size.zero;
  final focusNode = FocusNode(debugLabel: 'plan-editor');

  // dodir: više prstiju
  final Map<int, Offset> _touches = {};
  double? _pinchDist;
  double _pinchScale = 1;
  Offset _pinchFocusWorld = Offset.zero;

  PlanController get c => widget.c;
  Plan get plan => c.plan;
  Offset toWorld(Offset screen) => (screen - pan) / scale;

  @override
  void didUpdateWidget(PlanEditor old) {
    super.didUpdateWidget(old);
    if (c.tool != Tool.wall) {
      wallStart = null;
      typed = '';
    }
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- pogled
  void fit() {
    if (_size.isEmpty) return;
    final pts = <Offset>[for (final n in plan.nodes.values) n.pos, for (final i in plan.items) i.pos];
    final im = plan.image;
    if (im != null) {
      pts.add(im.origin);
      pts.add(im.origin + Offset(im.widthPx * im.metersPerPixel, im.heightPx * im.metersPerPixel));
    }
    if (pts.isEmpty) {
      setState(() {
        scale = 50;
        pan = Offset(_size.width / 2, _size.height / 2) - const Offset(5, 4) * 50;
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
    final bw = math.max(maxX - minX, 3.0) + 3.2, bh = math.max(maxY - minY, 3.0) + 3.2;
    setState(() {
      const inset = 64.0; // alatna traka lijevo
      scale = math.min((_size.width - inset) / bw, _size.height / bh).clamp(6.0, 400.0);
      pan = Offset(inset + (_size.width - inset) / 2, _size.height / 2) - Offset((minX + maxX) / 2, (minY + maxY) / 2) * scale;
    });
  }

  void zoomBy(double f, [Offset? focus]) {
    final fp = focus ?? Offset(_size.width / 2, _size.height / 2);
    final ns = (scale * f).clamp(6.0, 400.0);
    setState(() {
      pan = fp - (fp - pan) * (ns / scale);
      scale = ns;
    });
  }

  void centerOn(Offset world) => setState(() => pan = Offset(_size.width / 2, _size.height / 2) - world * scale);

  void cancelTool() {
    wallStart = null;
    chainStartNode = null;
    roomStart = null;
    roomEnd = null;
    measureA = null;
    measureB = null;
    calibA = null;
    typed = '';
    guides = [];
    if (c.tool == Tool.place) c.setTool(Tool.select);
    setState(() {});
  }

  // ---------------------------------------------------------------- hvatanje
  Offset _grid(Offset p, [double step = 0.05]) => Offset(roundTo(p.dx, step), roundTo(p.dy, step));

  /// Hvatanje: čvorovi → zidovi → kutovi (s polazne točke) → poravnanje → mreža 5 cm.
  Offset _snap(Offset w, {Offset? from, String? excludeNode, bool walls = true}) {
    guides = [];
    final tol = 11 / scale;
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
      if ((ang - snapped).abs() < 6 * math.pi / 180) ang = snapped;
      len = roundTo(len, 0.05);
      final p = from + Offset(math.cos(ang), math.sin(ang)) * len;
      // poravnanje s postojećim čvorom duž osi
      for (final n in plan.nodes.values) {
        if (n.id == excludeNode) continue;
        if ((n.pos.dx - p.dx).abs() < tol && (ang - math.pi / 2).abs() % math.pi < 0.01) {
          guides = [(n.pos, Offset(n.pos.dx, p.dy))];
        }
      }
      return p;
    }
    if (walls) {
      for (final wl in plan.walls) {
        if (wl.a == excludeNode || wl.b == excludeNode) continue;
        final a = plan.nodePos(wl.a), b = plan.nodePos(wl.b);
        if (distToSegment(w, a, b) < tol + wl.thickness / 2) {
          final q = closestOnSegment(w, a, b);
          // na zidu: korak 5 cm duž zida
          final len = (b - a).distance;
          if (len > 0) {
            final t = roundTo(projectT(q, a, b) * len, 0.05) / len;
            return a + (b - a) * t.clamp(0.0, 1.0);
          }
          return q;
        }
      }
    }
    var x = roundTo(w.dx, 0.05), y = roundTo(w.dy, 0.05);
    final g = <(Offset, Offset)>[];
    for (final n in plan.nodes.values) {
      if (n.id == excludeNode) continue;
      if ((n.pos.dx - w.dx).abs() < tol) {
        x = n.pos.dx;
        g.add((n.pos, Offset(x, y)));
      }
      if ((n.pos.dy - w.dy).abs() < tol) {
        y = n.pos.dy;
        g.add((n.pos, Offset(x, y)));
      }
    }
    guides = g.take(2).toList();
    return Offset(x, y);
  }

  Selection _hitTest(Offset w, {bool includeRooms = true}) {
    final tol = 7 / scale;
    for (final it in plan.items.reversed) {
      if (floorShapes.contains(it.shape)) continue;
      final local = rotate(w - it.pos, -it.rotation);
      if (local.dx.abs() <= it.w / 2 + tol && local.dy.abs() <= it.d / 2 + tol) return Selection(SelKind.item, it.id);
    }
    for (final o in plan.openings) {
      final wall = plan.wallById(o.wallId);
      if (wall == null) continue;
      final a = plan.nodePos(wall.a), b = plan.nodePos(wall.b);
      final len = (b - a).distance;
      if ((projectT(w, a, b) * len - o.t * len).abs() <= o.width / 2 && distToSegment(w, a, b) <= wall.thickness / 2 + tol) {
        return Selection(SelKind.opening, o.id);
      }
    }
    for (final n in plan.nodes.values) {
      if ((n.pos - w).distance <= 9 / scale) return Selection(SelKind.node, n.id);
    }
    for (final wall in plan.walls) {
      if (distToSegment(w, plan.nodePos(wall.a), plan.nodePos(wall.b)) <= wall.thickness / 2 + tol) {
        return Selection(SelKind.wall, wall.id);
      }
    }
    for (final it in plan.items.reversed) {
      final local = rotate(w - it.pos, -it.rotation);
      if (local.dx.abs() <= it.w / 2 && local.dy.abs() <= it.d / 2) return Selection(SelKind.item, it.id);
    }
    if (includeRooms) {
      for (final r in plan.rooms.reversed) {
        final poly = plan.roomPolygon(r);
        if (poly.length >= 3 && pointInPolygon(w, poly)) return Selection(SelKind.room, r.id);
      }
    }
    return Selection.none;
  }

  // ---------------------------------------------------------------- pokazivač
  void _onDown(PointerDownEvent e) {
    focusNode.requestFocus();
    if (e.kind == PointerDeviceKind.touch) {
      _touches[e.pointer] = e.localPosition;
      if (_touches.length == 2) {
        _startPinch();
        return;
      }
      if (_touches.length > 2) return;
    }
    final w = toWorld(e.localPosition);
    cursor = w;
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
        _wallClick(_snap(w, from: wallStart));
      case Tool.room:
        roomStart = _snap(w);
        roomEnd = roomStart;
      case Tool.door:
      case Tool.window:
      case Tool.balcony:
      case Tool.passage:
        final t = c.tool.openingType!;
        var added = false;
        c.mutate(() => added = c.addOpeningNear(w, t, tol: 0.25 + 8 / scale) != null);
        if (!added) _toast('Klikni na zid da dodaš: ${t.label.toLowerCase()}.');
      case Tool.measure:
        final p = _snap(w);
        if (measureA == null || measureB != null) {
          measureA = p;
          measureB = null;
        } else {
          measureB = p;
        }
      case Tool.calibrate:
        _calibClick(w);
      case Tool.place:
        final item = c.placing;
        if (item != null) {
          c.mutate(() => c.placeItemSmart(item, _grid(w, 0.01)));
          if (!HardwareKeyboard.instance.isShiftPressed) c.setTool(Tool.select);
        }
    }
    setState(() {});
  }

  void _wallClick(Offset p) {
    final start = wallStart;
    if (start == null) {
      wallStart = p;
      chainStartNode = _nodeAt(p);
      typed = '';
      return;
    }
    if ((p - start).distance < 0.05) {
      wallStart = null; // dvostruki klik na istu točku završava niz
      return;
    }
    c.mutate(() => c.addWall(start, p, thickness: _defaultThickness()));
    final closing = chainStartNode != null && _nodeAt(p) == chainStartNode;
    wallStart = closing ? null : p;
    if (closing) chainStartNode = null;
    chainStartNode ??= _nodeAt(start);
    typed = '';
  }

  double _defaultThickness() {
    final s = c.selection;
    if (s.kind == SelKind.wall) return plan.wallById(s.id)?.thickness ?? 0.2;
    return 0.2;
  }

  String? _nodeAt(Offset p) {
    for (final n in plan.nodes.values) {
      if ((n.pos - p).distance < 0.02) return n.id;
    }
    return null;
  }

  void _selectDown(PointerDownEvent e, Offset w) {
    // ručica za rotaciju odabranog objekta
    if (c.selection.kind == SelKind.item) {
      final it = plan.itemById(c.selection.id);
      if (it != null && (PlanPainter.rotationHandle(it, scale, pan) - e.localPosition).distance < 12) {
        c.beginChange();
        drag = _Drag(_DragKind.rotate, startWorld: w, startScreen: e.localPosition, id: it.id, startRot: it.rotation);
        return;
      }
    }
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
            startWorld: w, startScreen: e.localPosition, id: hit.id, startNodes: {for (final id in r.nodeIds) id: plan.nodePos(id)});
      case SelKind.item:
        c.beginChange();
        drag = _Drag(_DragKind.item, startWorld: w, startScreen: e.localPosition, id: hit.id, startPos: plan.itemById(hit.id)!.pos);
      case SelKind.opening:
        c.beginChange();
        drag = _Drag(_DragKind.opening, startWorld: w, startScreen: e.localPosition, id: hit.id);
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.kind == PointerDeviceKind.touch && _touches.containsKey(e.pointer)) {
      _touches[e.pointer] = e.localPosition;
      if (_touches.length >= 2) {
        _updatePinch();
        return;
      }
    }
    final w = toWorld(e.localPosition);
    cursor = w;
    final d = drag;
    if (d != null) {
      if ((e.localPosition - d.startScreen).distance > 3) d.moved = true;
      final delta = w - d.startWorld;
      switch (d.kind) {
        case _DragKind.pan:
          pan = d.startPan + (e.localPosition - d.startScreen);
        case _DragKind.node:
          c.setNodePos(d.id, _snap(w, excludeNode: d.id));
          c.liveUpdate();
        case _DragKind.wall:
          final k = roundTo(dot(delta, d.normal), 0.01);
          d.startNodes.forEach((id, p) => c.setNodePos(id, p + d.normal * k));
          c.liveUpdate();
        case _DragKind.room:
          final dd = _grid(delta);
          d.startNodes.forEach((id, p) => c.setNodePos(id, p + dd));
          c.liveUpdate();
        case _DragKind.item:
          c.setItemPos(d.id, d.startPos + _grid(delta, 0.01));
          c.liveUpdate();
        case _DragKind.rotate:
          final it = plan.itemById(d.id);
          if (it != null) {
            final v = w - it.pos;
            var ang = math.atan2(v.dx, -v.dy);
            if (!HardwareKeyboard.instance.isShiftPressed) ang = roundTo(ang, math.pi / 12);
            it.rotation = ang % (2 * math.pi);
            c.liveUpdate();
          }
        case _DragKind.opening:
          c.slideOpening(d.id, w);
          c.liveUpdate();
        case _DragKind.image:
          break;
      }
    } else if (c.tool == Tool.room && roomStart != null) {
      roomEnd = _snap(w);
    }
    setState(() {});
  }

  void _onUp(PointerEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      _touches.remove(e.pointer);
      if (_touches.length < 2) _pinchDist = null;
    }
    final d = drag;
    drag = null;
    guides = [];
    if (d != null && d.kind != _DragKind.pan) {
      if (d.kind == _DragKind.node) c.mergeNodeIfClose(d.id);
      c.endChange();
    }
    if (c.tool == Tool.room && roomStart != null && roomEnd != null) {
      final r = Rect.fromPoints(roomStart!, roomEnd!);
      if (r.width >= 0.5 && r.height >= 0.5) {
        c.mutate(() => c.addRoomRect(r));
      }
      roomStart = null;
      roomEnd = null;
    }
    setState(() {});
  }

  void _onHover(PointerHoverEvent e) {
    final w = toWorld(e.localPosition);
    cursor = w;
    if (c.tool == Tool.select) {
      hover = _hitTest(w, includeRooms: true);
    } else if (c.tool.openingType != null) {
      final wl = c.wallNear(w, tol: 0.25 + 8 / scale);
      hover = wl == null ? Selection.none : Selection(SelKind.wall, wl.id);
    } else {
      hover = Selection.none;
      if (c.tool == Tool.wall) _snap(w, from: wallStart);
    }
    setState(() {});
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      if (HardwareKeyboard.instance.isControlPressed || e.kind == PointerDeviceKind.mouse) {
        zoomBy(math.exp(-e.scrollDelta.dy / 400), e.localPosition);
      } else {
        setState(() => pan -= e.scrollDelta);
      }
    } else if (e is PointerScaleEvent) {
      zoomBy(e.scale, e.localPosition);
    }
  }

  void _startPinch() {
    final pts = _touches.values.toList();
    _pinchDist = (pts[0] - pts[1]).distance;
    _pinchScale = scale;
    _pinchFocusWorld = toWorld((pts[0] + pts[1]) / 2);
    final d = drag;
    if (d != null && d.kind != _DragKind.pan) c.endChange();
    drag = null;
  }

  void _updatePinch() {
    final pts = _touches.values.toList();
    if (_pinchDist == null || _pinchDist == 0) return;
    final dist = (pts[0] - pts[1]).distance;
    final focus = (pts[0] + pts[1]) / 2;
    setState(() {
      scale = (_pinchScale * dist / _pinchDist!).clamp(6.0, 400.0);
      pan = focus - _pinchFocusWorld * scale;
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _calibClick(Offset w) async {
    if (plan.image == null) {
      _toast('Prvo učitaj sliku nacrta, zatim postavi mjerilo.');
      return;
    }
    final a = calibA;
    if (a == null) {
      calibA = w;
      return;
    }
    calibA = null;
    final ctrl = TextEditingController(text: fmtM((w - a).distance));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Postavi mjerilo nacrta'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Upiši stvarnu udaljenost između dvije točke koje si označio, npr. kotiranu duljinu zida.',
              style: AppText.ui(size: 13, color: Pal.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(suffixText: 'm', labelText: 'Stvarna udaljenost'),
            onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s.replaceAll(',', '.'))),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Odustani')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))),
              child: const Text('Postavi mjerilo')),
        ],
      ),
    );
    if (v != null && v > 0) {
      c.mutate(() => c.calibrateImage(a, w, v));
      c.setTool(Tool.wall);
      _toast('Mjerilo postavljeno. Sada precrtaj zidove klikom od kuta do kuta.');
      fit();
    }
    setState(() {});
  }

  // ---------------------------------------------------------------- tipkovnica
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // unos duljine zida tipkovnicom
    if (c.tool == Tool.wall && wallStart != null) {
      final ch = e.character;
      if (ch != null && RegExp(r'^[0-9.,]$').hasMatch(ch)) {
        setState(() => typed += ch == ',' ? '.' : ch);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.backspace && typed.isNotEmpty) {
        setState(() => typed = typed.substring(0, typed.length - 1));
        return KeyEventResult.handled;
      }
      if ((k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) && typed.isNotEmpty) {
        final len = double.tryParse(typed);
        final start = wallStart!;
        final target = cursor == null ? start + const Offset(1, 0) : _snap(cursor!, from: start);
        final dv = target - start;
        if (len != null && len > 0.05 && dv.distance > 0) {
          _wallClick(start + dv / dv.distance * len);
        }
        setState(() => typed = '');
        return KeyEventResult.handled;
      }
    }

    if (k == LogicalKeyboardKey.escape) {
      cancelTool();
      c.select(Selection.none);
      c.setTool(Tool.select);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      c.deleteSelection();
      return KeyEventResult.handled;
    }
    if (c.selection.kind == SelKind.item) {
      final id = c.selection.id;
      if (k == LogicalKeyboardKey.keyR && !ctrl) {
        c.rotateItem(id, (shift ? -1 : 1) * math.pi / 2);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyD && ctrl) {
        c.duplicateItem(id);
        return KeyEventResult.handled;
      }
      final step = shift ? 0.1 : 0.01;
      final nudge = switch (k) {
        LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
        LogicalKeyboardKey.arrowRight => Offset(step, 0),
        LogicalKeyboardKey.arrowUp => Offset(0, -step),
        LogicalKeyboardKey.arrowDown => Offset(0, step),
        _ => null,
      };
      if (nudge != null) {
        final it = plan.itemById(id)!;
        c.mutate(() => it.pos += nudge);
        return KeyEventResult.handled;
      }
    }
    if (!ctrl) {
      final t = switch (k) {
        LogicalKeyboardKey.keyV => Tool.select,
        LogicalKeyboardKey.keyW => Tool.wall,
        LogicalKeyboardKey.keyR => Tool.room,
        LogicalKeyboardKey.keyD => Tool.door,
        LogicalKeyboardKey.keyP => Tool.window,
        LogicalKeyboardKey.keyM => Tool.measure,
        _ => null,
      };
      if (t != null) {
        cancelTool();
        c.setTool(t);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.add || k == LogicalKeyboardKey.numpadAdd) {
        zoomBy(1.2);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract) {
        zoomBy(1 / 1.2);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.digit0 && !(c.tool == Tool.wall && wallStart != null)) {
        fit();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------- izgradnja
  MouseCursor get _cursor {
    final d = drag;
    if (d != null) {
      return switch (d.kind) {
        _DragKind.pan => SystemMouseCursors.grabbing,
        _DragKind.rotate => SystemMouseCursors.grabbing,
        _ => SystemMouseCursors.move,
      };
    }
    if (c.tool != Tool.select) return SystemMouseCursors.precise;
    return switch (hover.kind) {
      SelKind.none => SystemMouseCursors.grab,
      SelKind.room => SystemMouseCursors.basic,
      SelKind.opening => SystemMouseCursors.resizeLeftRight,
      _ => SystemMouseCursors.move,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.walker]),
      builder: (context, _) => LayoutBuilder(builder: (context, box) {
        _size = box.biggest;
        final z = widget.zoom;
        if (z != null && z.value != scale) {
          WidgetsBinding.instance.addPostFrameCallback((_) => z.value = scale);
        }
        if (!_fitted && !_size.isEmpty) {
          _fitted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => fit());
        }
        final wallEnd = (c.tool == Tool.wall && wallStart != null && cursor != null) ? _snapPreview() : null;
        final state = PlanPaintState(
          plan: plan,
          scale: scale,
          pan: pan,
          bgImage: c.bgImage,
          selection: c.selection,
          hover: drag == null ? hover : Selection.none,
          tool: c.tool,
          cursor: cursor,
          wallStart: wallStart,
          wallEnd: wallEnd,
          typedLength: typed.isEmpty ? null : typed,
          roomStart: roomStart,
          roomEnd: roomEnd,
          measureA: measureA,
          measureB: measureB,
          calibA: calibA,
          placing: c.tool == Tool.place ? c.placing : null,
          guides: guides,
          walker: c.walker.value,
          dropGhost: dropGhost,
        );
        return DragTarget<CatalogItem>(
          onMove: (d) {
            final rb = context.findRenderObject() as RenderBox?;
            if (rb == null) return;
            setState(() => dropGhost = (d.data, toWorld(rb.globalToLocal(d.offset + const Offset(0, 0)))));
          },
          onLeave: (_) => setState(() => dropGhost = null),
          onAcceptWithDetails: (d) {
            final p = dropGhost?.$2;
            setState(() => dropGhost = null);
            if (p != null) c.mutate(() => c.placeItemSmart(d.data, _grid(p, 0.01)));
          },
          builder: (context, cand, rej) => Focus(
            focusNode: focusNode,
            onKeyEvent: _onKey,
            child: MouseRegion(
              cursor: _cursor,
              onExit: (_) => setState(() {
                cursor = null;
                hover = Selection.none;
              }),
              child: Listener(
                onPointerDown: _onDown,
                onPointerMove: _onMove,
                onPointerUp: _onUp,
                onPointerCancel: _onUp,
                onPointerHover: _onHover,
                onPointerSignal: _onSignal,
                child: ClipRect(child: CustomPaint(size: Size.infinite, painter: PlanPainter(state))),
              ),
            ),
          ),
        );
      }),
    );
  }

  Offset _snapPreview() {
    final g = guides;
    final p = _snap(cursor!, from: wallStart);
    if (guides.isEmpty) guides = g;
    return p;
  }
}
