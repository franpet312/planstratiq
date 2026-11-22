import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/catalog.dart';
import '../models/geometry.dart';
import '../models/materials.dart';
import '../models/plan.dart';
import '../models/topology.dart';
import '../state/plan_controller.dart';

/// Sve što je potrebno za crtanje tlocrta – iz uređivača ili za pregled.
class PlanPaintState {
  PlanPaintState({
    required this.plan,
    required this.scale,
    required this.pan,
    this.bgImage,
    this.selection = Selection.none,
    this.hover = Selection.none,
    this.tool = Tool.select,
    this.preview = false,
    this.printMode = false,
    this.cursor,
    this.wallStart,
    this.wallEnd,
    this.typedLength,
    this.roomStart,
    this.roomEnd,
    this.measureA,
    this.measureB,
    this.calibA,
    this.placing,
    this.guides = const [],
    this.walker,
    this.dropGhost,
  });

  final Plan plan;
  final double scale;
  final Offset pan;
  final ui.Image? bgImage;
  final Selection selection;
  final Selection hover;
  final Tool tool;
  final bool preview;

  /// Za izvoz slike: bijela podloga, bez mreže i oznaka uređivanja.
  final bool printMode;
  final Offset? cursor;
  final Offset? wallStart;
  final Offset? wallEnd;
  final String? typedLength;
  final Offset? roomStart;
  final Offset? roomEnd;
  final Offset? measureA;
  final Offset? measureB;
  final Offset? calibA;
  final CatalogItem? placing;
  final List<(Offset, Offset)> guides;
  final (Offset, double)? walker;
  final (CatalogItem, Offset)? dropGhost;
}

/// Za svaki zid: broj prostorija uz njega i normala prema unutra.
class _WallInfo {
  int sides = 0;
  Offset? inward;
}

class PlanPainter extends CustomPainter {
  PlanPainter(this.st);
  final PlanPaintState st;

  Plan get plan => st.plan;
  double get scale => st.scale;
  Offset s(Offset w) => w * scale + st.pan;

  late Map<String, _WallInfo> _info;

  @override
  void paint(Canvas canvas, Size size) {
    _info = _wallInfo();
    if (!st.preview && !st.printMode) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Pal.paper);
      _grid(canvas, size);
      _image(canvas);
      _ghostBelow(canvas);
    }
    _rooms(canvas);
    _items(canvas, floor: true);
    _items(canvas, floor: false);
    _walls(canvas);
    _openings(canvas);
    if (!st.preview) {
      _exteriorDimensions(canvas);
      _selectedWallDimension(canvas);
    }
    _roomLabels(canvas);
    if (!st.preview && !st.printMode) {
      _selectionOverlay(canvas);
      _nodes(canvas);
      _previews(canvas);
      _walker(canvas);
    }
  }

  Map<String, _WallInfo> _wallInfo() {
    final info = <String, _WallInfo>{for (final w in plan.walls) w.id: _WallInfo()};
    final byKey = <String, Wall>{};
    for (final w in plan.walls) {
      byKey['${w.a}|${w.b}'] = w;
      byKey['${w.b}|${w.a}'] = w;
    }
    for (final r in plan.rooms) {
      final ids = r.nodeIds;
      for (var i = 0; i < ids.length; i++) {
        final a = ids[i], b = ids[(i + 1) % ids.length];
        final w = byKey['$a|$b'];
        if (w == null) continue;
        final inf = info[w.id]!;
        inf.sides++;
        final d = plan.nodePos(b) - plan.nodePos(a);
        final len = d.distance;
        if (len > 0) inf.inward = Offset(-d.dy, d.dx) / len;
      }
    }
    return info;
  }

  // ---------------------------------------------------------------- mreža
  void _grid(Canvas canvas, Size size) {
    final tl = (Offset.zero - st.pan) / scale;
    final br = (Offset(size.width, size.height) - st.pan) / scale;
    void lines(double step, Color c, [double w = 1]) {
      final p = Paint()
        ..color = c
        ..strokeWidth = w;
      for (var x = (tl.dx / step).floorToDouble() * step; x <= br.dx; x += step) {
        canvas.drawLine(s(Offset(x, tl.dy)), s(Offset(x, br.dy)), p);
      }
      for (var y = (tl.dy / step).floorToDouble() * step; y <= br.dy; y += step) {
        canvas.drawLine(s(Offset(tl.dx, y)), s(Offset(br.dx, y)), p);
      }
    }

    if (scale > 110) lines(0.1, const Color(0xFFE8ECEA));
    if (scale > 28) lines(0.5, const Color(0xFFE2E7E4));
    lines(1, const Color(0xFFD7DDDA));
    lines(5, const Color(0xFFC8D0CC), 1.2);
  }

  /// Prozirni obris etaže ispod – pomaže poravnati nosive zidove kata.
  void _ghostBelow(Canvas canvas) {
    final below = plan.levelBelow;
    if (below == null || below.walls.isEmpty) return;
    final p = Paint()
      ..color = const Color(0x553A6EA5)
      ..strokeCap = StrokeCap.butt
      ..style = PaintingStyle.stroke;
    for (final w in below.walls) {
      final a = below.nodes[w.a]?.pos, b = below.nodes[w.b]?.pos;
      if (a == null || b == null) continue;
      p.strokeWidth = math.max(1.0, w.thickness * scale);
      canvas.drawLine(s(a), s(b), p);
    }
    final dash = Paint()
      ..color = const Color(0x993A6EA5)
      ..strokeWidth = 1;
    for (final o in below.openings) {
      Wall? w;
      for (final x in below.walls) {
        if (x.id == o.wallId) w = x;
      }
      if (w == null) continue;
      final a = below.nodes[w.a]?.pos, b = below.nodes[w.b]?.pos;
      if (a == null || b == null) continue;
      final d = b - a;
      final len = d.distance;
      if (len < 0.01) continue;
      final u = d / len;
      final c = a + u * (o.t * len);
      canvas.drawLine(s(c - u * (o.width / 2)), s(c + u * (o.width / 2)), dash);
    }
  }

  void _image(Canvas canvas) {
    final im = plan.image, img = st.bgImage;
    if (im == null || img == null) return;
    final o = s(im.origin);
    final dst = Rect.fromLTWH(o.dx, o.dy, im.widthPx * im.metersPerPixel * scale, im.heightPx * im.metersPerPixel * scale);
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, im.opacity)
          ..filterQuality = FilterQuality.medium);
  }

  // ---------------------------------------------------------------- prostorije
  void _rooms(Canvas canvas) {
    for (final r in plan.rooms) {
      final poly = plan.roomPolygon(r);
      if (poly.length < 3) continue;
      final path = Path()..addPolygon([for (final p in poly) s(p)], true);
      final mat = floorById(r.floor);
      final sel = st.selection == Selection(SelKind.room, r.id);
      final hov = st.hover == Selection(SelKind.room, r.id);
      canvas.drawPath(path, Paint()..color = Color.lerp(Colors.white, Color(mat.color), st.preview ? 0.35 : 0.22)!);
      if (!st.preview && scale > 30) _floorPattern(canvas, path, poly, mat);
      if (sel || hov) canvas.drawPath(path, Paint()..color = Pal.accent.withAlpha(sel ? 34 : 18));
    }
  }

  void _floorPattern(Canvas canvas, Path clip, List<Offset> poly, FloorMaterial mat) {
    var minX = poly.first.dx, maxX = minX, minY = poly.first.dy, maxY = minY;
    for (final p in poly) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final paint = Paint()
      ..color = Color(mat.color).withAlpha(55)
      ..strokeWidth = 0.8;
    canvas.save();
    canvas.clipPath(clip);
    switch (mat.texture) {
      case 'wood':
        const step = 0.2;
        for (var y = (minY / step).floorToDouble() * step; y <= maxY; y += step) {
          canvas.drawLine(s(Offset(minX, y)), s(Offset(maxX, y)), paint);
        }
      case 'tile':
      case 'largeTile':
      case 'stone':
        final step = mat.texture == 'tile' ? 0.3 : 0.6;
        for (var y = (minY / step).floorToDouble() * step; y <= maxY; y += step) {
          canvas.drawLine(s(Offset(minX, y)), s(Offset(maxX, y)), paint);
        }
        for (var x = (minX / step).floorToDouble() * step; x <= maxX; x += step) {
          canvas.drawLine(s(Offset(x, minY)), s(Offset(x, maxY)), paint);
        }
      default:
        break;
    }
    canvas.restore();
  }

  void _roomLabels(Canvas canvas) {
    for (final r in plan.rooms) {
      final poly = plan.roomPolygon(r);
      if (poly.length < 3) continue;
      final area = roomNetArea(plan, r);
      final at = s(labelPoint(poly));
      final pxArea = area * scale * scale;
      if (pxArea < (st.preview ? 900 : 2600)) continue;
      final sel = st.selection == Selection(SelKind.room, r.id);
      final color = sel ? Pal.accentDeep : Pal.ink;
      if (st.preview) {
        _text(canvas, r.name, at, AppText.ui(size: 9, weight: FontWeight.w600, color: Pal.inkSoft), halo: true);
        continue;
      }
      final big = pxArea > 12000 && scale > 30;
      final fs = (scale * 0.26).clamp(9.0, 13.0);
      _text(canvas, r.name, at - Offset(0, fs * 0.75), AppText.ui(size: fs, weight: FontWeight.w600, color: color),
          halo: true, maxWidth: math.sqrt(pxArea) * 1.4);
      _text(canvas, 'P = ${fmtM2(area)}', at + Offset(0, fs * 0.55), AppText.narrow(size: fs - 1, color: color), halo: true);
      if (big) {
        _text(canvas, floorById(r.floor).name, at + const Offset(0, 22), AppText.narrow(size: 10, color: Pal.muted), halo: true);
      }
    }
  }

  // ---------------------------------------------------------------- zidovi
  List<Offset> _wallQuad(Wall w, Map<String, int> degree) {
    final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
    final len = (b - a).distance;
    if (len == 0) return [a, a, a, a];
    final dir = (b - a) / len;
    final n = Offset(-dir.dy, dir.dx) * (w.thickness / 2);
    final ea = (degree[w.a] ?? 0) > 1 ? dir * (w.thickness / 2) : Offset.zero;
    final eb = (degree[w.b] ?? 0) > 1 ? dir * (w.thickness / 2) : Offset.zero;
    return [a - ea + n, b + eb + n, b + eb - n, a - ea - n];
  }

  void _walls(Canvas canvas) {
    final degree = <String, int>{};
    for (final w in plan.walls) {
      degree[w.a] = (degree[w.a] ?? 0) + 1;
      degree[w.b] = (degree[w.b] ?? 0) + 1;
    }
    final outer = Path(), inner = Path();
    for (final w in plan.walls) {
      final q = [for (final p in _wallQuad(w, degree)) s(p)];
      final isOuter = (_info[w.id]?.sides ?? 0) <= 1 && w.thickness >= 0.2;
      (isOuter ? outer : inner).addPolygon(q, true);
    }
    canvas.drawPath(inner, Paint()..color = Pal.inkSoft);
    canvas.drawPath(outer, Paint()..color = Pal.wall);
    if (!st.preview && scale > 25) {
      final b = outer.getBounds();
      canvas.save();
      canvas.clipPath(outer);
      final hatch = Paint()
        ..color = Colors.white.withAlpha(40)
        ..strokeWidth = 1;
      const gap = 7.0;
      for (var x = b.left - b.height; x < b.right; x += gap) {
        canvas.drawLine(Offset(x, b.bottom), Offset(x + b.height, b.top), hatch);
      }
      canvas.restore();
    }
    for (final w in plan.walls) {
      final sel = st.selection == Selection(SelKind.wall, w.id);
      final hov = st.hover == Selection(SelKind.wall, w.id);
      if (!sel && !hov) continue;
      final q = [for (final p in _wallQuad(w, degree)) s(p)];
      canvas.drawPath(Path()..addPolygon(q, true), Paint()..color = sel ? Pal.accent : Pal.accent.withAlpha(120));
    }
  }

  void _openings(Canvas canvas) {
    for (final o in plan.openings) {
      final w = plan.wallById(o.wallId);
      if (w == null) continue;
      final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
      final len = (b - a).distance;
      if (len == 0) continue;
      final dir = (b - a) / len;
      var n = Offset(-dir.dy, dir.dx);
      final info = _info[w.id];
      if (info?.inward != null && info!.sides == 1 && dot(info.inward!, n) < 0) n = -n;
      if (o.swingOut) n = -n;
      final center = a + dir * (o.t * len);
      final hw = o.width / 2;
      final ht = w.thickness / 2 + 0.006;
      final p0 = center - dir * hw, p1 = center + dir * hw;
      final gap = [p0 + n * ht, p1 + n * ht, p1 - n * ht, p0 - n * ht];
      final sel = st.selection == Selection(SelKind.opening, o.id);
      final hov = st.hover == Selection(SelKind.opening, o.id);
      final col = sel ? Pal.accent : (hov ? Pal.accent.withAlpha(170) : Pal.ink);
      final glassy = o.type == OpeningType.window || o.type == OpeningType.balcony;
      canvas.drawPath(Path()..addPolygon([for (final p in gap) s(p)], true),
          Paint()..color = glassy ? const Color(0xFFF7FAFA) : Pal.paper);
      final line = Paint()
        ..color = col
        ..strokeWidth = sel ? 1.8 : 1.1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(s(p0 + n * ht), s(p0 - n * ht), line);
      canvas.drawLine(s(p1 + n * ht), s(p1 - n * ht), line);
      switch (o.type) {
        case OpeningType.door:
          final hinge = o.flip ? p1 : p0;
          final other = o.flip ? p0 : p1;
          final h0 = hinge + n * ht;
          canvas.drawLine(s(h0), s(h0 + n * o.width),
              Paint()
                ..color = col
                ..strokeWidth = sel ? 2.4 : 1.8);
          final a0 = math.atan2(n.dy, n.dx);
          final d2 = other - hinge;
          var sweep = math.atan2(d2.dy, d2.dx) - a0;
          while (sweep > math.pi) {
            sweep -= 2 * math.pi;
          }
          while (sweep < -math.pi) {
            sweep += 2 * math.pi;
          }
          canvas.drawArc(Rect.fromCircle(center: s(h0), radius: o.width * scale), a0, sweep, false,
              Paint()
                ..color = col.withAlpha(150)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 0.8);
        case OpeningType.window:
          final g = Paint()
            ..color = col
            ..strokeWidth = 0.9;
          canvas.drawLine(s(p0 + n * ht), s(p1 + n * ht), g);
          canvas.drawLine(s(p0 - n * ht), s(p1 - n * ht), g);
          canvas.drawLine(s(p0), s(p1), Paint()
            ..color = col
            ..strokeWidth = 1.4);
        case OpeningType.balcony:
          final g = Paint()
            ..color = col
            ..strokeWidth = 1.2;
          canvas.drawLine(s(p0 + n * (ht * 0.35)), s(center + dir * 0.05 + n * (ht * 0.35)), g);
          canvas.drawLine(s(center - dir * 0.05 - n * (ht * 0.35)), s(p1 - n * (ht * 0.35)), g);
          final t = Paint()
            ..color = col
            ..strokeWidth = 0.7;
          canvas.drawLine(s(p0 + n * ht), s(p1 + n * ht), t);
          canvas.drawLine(s(p0 - n * ht), s(p1 - n * ht), t);
        case OpeningType.passage:
          _dashed(canvas, s(p0), s(p1), Paint()
            ..color = col.withAlpha(140)
            ..strokeWidth = 1);
      }
    }
  }

  // ---------------------------------------------------------------- kote
  void _dimLine(Canvas canvas, Offset a, Offset b, Offset outward, double offsetPx, String label,
      {Color color = Pal.inkSoft, bool extension = true, double faceOffsetPx = 0}) {
    final sa = s(a), sb = s(b);
    final o = outward * offsetPx;
    final la = sa + o, lb = sb + o;
    final p = Paint()
      ..color = color
      ..strokeWidth = 0.8;
    if (extension) {
      final f = outward * (faceOffsetPx + 3);
      canvas.drawLine(sa + f, la + outward * 4, p);
      canvas.drawLine(sb + f, lb + outward * 4, p);
    }
    canvas.drawLine(la, lb, p);
    final d = lb - la;
    final len = d.distance;
    if (len < 1) return;
    final u = d / len;
    final tick = Offset(u.dx + u.dy, u.dy - u.dx) * 3.6;
    final tp2 = Paint()
      ..color = color
      ..strokeWidth = 1.3;
    canvas.drawLine(la - tick, la + tick, tp2);
    canvas.drawLine(lb - tick, lb + tick, tp2);
    var ang = math.atan2(u.dy, u.dx);
    if (ang > math.pi / 2 + 0.01) ang -= math.pi;
    if (ang < -math.pi / 2 - 0.01) ang += math.pi;
    final tp = _layout(label, AppText.narrow(size: 10.5, color: color));
    if (tp.width + 8 > len) return;
    final side = outward.dy.abs() > 0.5 ? outward * 7 : outward * 9;
    _paintText(canvas, tp, (la + lb) / 2 + side, angle: ang, halo: true);
  }

  void _exteriorDimensions(Canvas canvas) {
    if (scale < 16) return;
    for (final w in plan.walls) {
      final info = _info[w.id]!;
      if (info.sides != 1 || info.inward == null) continue;
      final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
      final len = (b - a).distance;
      if (len * scale < 26) continue;
      _dimLine(canvas, a, b, -info.inward!, w.thickness / 2 * scale + 22, fmtM(len), faceOffsetPx: w.thickness / 2 * scale);
    }
    if (plan.walls.isEmpty) return;
    var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
    var maxT = 0.0;
    for (final w in plan.walls) {
      for (final id in [w.a, w.b]) {
        final p = plan.nodePos(id);
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
      maxT = math.max(maxT, w.thickness);
    }
    final off = maxT / 2 * scale + 48;
    if ((maxX - minX) * scale > 60) {
      _dimLine(canvas, Offset(minX, minY), Offset(maxX, minY), const Offset(0, -1), off, fmtM(maxX - minX),
          color: Pal.ink, extension: false);
    }
    if ((maxY - minY) * scale > 60) {
      _dimLine(canvas, Offset(minX, minY), Offset(minX, maxY), const Offset(-1, 0), off, fmtM(maxY - minY),
          color: Pal.ink, extension: false);
    }
  }

  void _selectedWallDimension(Canvas canvas) {
    for (final w in plan.walls) {
      final sel = st.selection == Selection(SelKind.wall, w.id) || st.hover == Selection(SelKind.wall, w.id);
      if (!sel) continue;
      final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
      final len = (b - a).distance;
      if (len == 0) continue;
      final dir = (b - a) / len;
      final n = _info[w.id]?.inward ?? Offset(-dir.dy, dir.dx);
      _dimLine(canvas, a, b, n, w.thickness / 2 * scale + 16, '${fmtM(len)} m',
          color: Pal.accent, faceOffsetPx: w.thickness / 2 * scale);
    }
  }

  // ---------------------------------------------------------------- namještaj
  void _items(Canvas canvas, {required bool floor}) {
    for (final it in plan.items) {
      if (floorShapes.contains(it.shape) != floor) continue;
      _drawItem(canvas, it.pos, it.rotation, it.w, it.d, it.shape, Color(it.color),
          hovered: st.hover == Selection(SelKind.item, it.id));
    }
  }

  void _drawItem(Canvas canvas, Offset pos, double rot, double w, double d, String shape, Color color,
      {bool hovered = false, bool ghost = false}) {
    canvas.save();
    final c = s(pos);
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rot);
    if (ghost) canvas.saveLayer(null, Paint()..color = Colors.white.withAlpha(160));
    ItemSymbols(canvas, w * scale, d * scale, scale, color, shape, preview: st.preview).draw();
    if (hovered) {
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: w * scale + 4, height: d * scale + 4),
          Paint()
            ..color = Pal.accent.withAlpha(150)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
    }
    if (ghost) canvas.restore();
    canvas.restore();
  }

  // ---------------------------------------------------------------- odabir
  void _selectionOverlay(Canvas canvas) {
    if (st.selection.kind != SelKind.item) return;
    final it = plan.itemById(st.selection.id);
    if (it == null) return;
    canvas.save();
    final c = s(it.pos);
    canvas.translate(c.dx, c.dy);
    canvas.rotate(it.rotation);
    final r = Rect.fromCenter(center: Offset.zero, width: it.w * scale + 6, height: it.d * scale + 6);
    final p = Paint()
      ..color = Pal.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawRect(r, p);
    final hy = r.top - 22;
    canvas.drawLine(Offset(0, r.top), Offset(0, hy + 6), p);
    canvas.drawCircle(Offset(0, hy), 6.5, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(0, hy), 6.5, p);
    canvas.drawCircle(Offset(0, hy), 2, Paint()..color = Pal.accent);
    for (final k in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final kr = Rect.fromCenter(center: k, width: 6, height: 6);
      canvas.drawRect(kr, Paint()..color = Colors.white);
      canvas.drawRect(kr, p);
    }
    canvas.restore();
    _text(canvas, '${(it.w * 100).round()} × ${(it.d * 100).round()} cm', c + rotate(Offset(0, it.d * scale / 2 + 16), 0),
        AppText.narrow(size: 10.5, color: Pal.accentDeep, weight: FontWeight.w600),
        halo: true);
  }

  /// Položaj ručice za rotaciju odabranog objekta (u koordinatama ekrana).
  static Offset rotationHandle(PlacedItem it, double scale, Offset pan) {
    final c = it.pos * scale + pan;
    return c + rotate(Offset(0, -(it.d * scale + 6) / 2 - 22), it.rotation);
  }

  void _nodes(Canvas canvas) {
    if (st.tool != Tool.select && st.tool != Tool.wall) return;
    final selWall = st.selection.kind == SelKind.wall ? plan.wallById(st.selection.id) : null;
    for (final n in plan.nodes.values) {
      final sel = st.selection == Selection(SelKind.node, n.id) || (selWall != null && (selWall.a == n.id || selWall.b == n.id));
      final hov = st.hover == Selection(SelKind.node, n.id);
      if (!sel && !hov && (st.tool != Tool.wall || scale < 25)) continue;
      final p = s(n.pos);
      final r = sel || hov ? 5.0 : 2.6;
      canvas.drawCircle(p, r, Paint()..color = Colors.white);
      canvas.drawCircle(
          p,
          r,
          Paint()
            ..color = sel || hov ? Pal.accent : Pal.muted
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4);
    }
  }

  // ---------------------------------------------------------------- pregledi
  void _previews(Canvas canvas) {
    final accent = Paint()
      ..color = Pal.accent
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final g in st.guides) {
      _dashed(canvas, s(g.$1), s(g.$2), Paint()
        ..color = Pal.accent.withAlpha(150)
        ..strokeWidth = 1);
    }
    if (st.tool == Tool.wall && st.wallStart != null && st.wallEnd != null) {
      final a = st.wallStart!, b = st.wallEnd!;
      final len = (b - a).distance;
      if (len > 0) {
        final dir = (b - a) / len;
        final n = Offset(-dir.dy, dir.dx) * 0.1;
        final q = [s(a + n), s(b + n), s(b - n), s(a - n)];
        canvas.drawPath(Path()..addPolygon(q, true), Paint()..color = Pal.accent.withAlpha(90));
        canvas.drawPath(Path()..addPolygon(q, true), accent);
        _dimLine(canvas, a, b, Offset(-dir.dy, dir.dx), 18, '${fmtM(len)} m', color: Pal.accent, extension: false);
        final ang = (math.atan2(-dir.dy, dir.dx) * 180 / math.pi).round();
        _text(canvas, '${(ang + 360) % 360}°', s(b) + const Offset(18, 18), AppText.narrow(size: 10, color: Pal.accent), halo: true);
      }
    }
    if ((st.tool == Tool.wall || st.tool == Tool.room) && st.cursor != null) {
      final p = s(st.wallEnd ?? st.roomEnd ?? st.cursor!);
      canvas.drawLine(p - const Offset(9, 0), p + const Offset(9, 0), accent);
      canvas.drawLine(p - const Offset(0, 9), p + const Offset(0, 9), accent);
    }
    if (st.typedLength != null && st.cursor != null) {
      final at = s(st.wallEnd ?? st.cursor!) + const Offset(30, -26);
      final tp = _layout('${st.typedLength!.replaceAll('.', ',')} m   Enter', AppText.narrow(size: 13, weight: FontWeight.w700, color: Colors.white));
      final r = Rect.fromCenter(center: at, width: tp.width + 16, height: tp.height + 8);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), Paint()..color = Pal.accent);
      _paintText(canvas, tp, at);
    }
    if (st.tool == Tool.room && st.roomStart != null && st.roomEnd != null) {
      final r = Rect.fromPoints(s(st.roomStart!), s(st.roomEnd!));
      canvas.drawRect(r, Paint()..color = Pal.accent.withAlpha(30));
      canvas.drawRect(
          r,
          Paint()
            ..color = Pal.accent.withAlpha(140)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(2, 0.2 * scale));
      final wm = (st.roomEnd!.dx - st.roomStart!.dx).abs(), hm = (st.roomEnd!.dy - st.roomStart!.dy).abs();
      _text(canvas, '${fmtM(wm)} × ${fmtM(hm)} m', r.center - const Offset(0, 8),
          AppText.narrow(size: 13, weight: FontWeight.w700, color: Pal.accentDeep),
          halo: true);
      _text(canvas, fmtM2(wm * hm), r.center + const Offset(0, 9), AppText.narrow(size: 12, color: Pal.accentDeep), halo: true);
    }
    if (st.tool == Tool.measure && st.measureA != null) {
      final b = st.measureB ?? st.cursor;
      if (b != null) {
        final a = st.measureA!;
        final d = b - a;
        final len = d.distance;
        if (len > 0) {
          final u = d / len;
          _dimLine(canvas, a, b, Offset(-u.dy, u.dx), 0, '${fmtM(len)} m', color: Pal.accent, extension: false);
          canvas.drawCircle(s(a), 3.5, Paint()..color = Pal.accent);
          canvas.drawCircle(s(b), 3.5, Paint()..color = Pal.accent);
        }
      }
    }
    if (st.tool == Tool.calibrate && st.calibA != null && st.cursor != null) {
      final p = Paint()
        ..color = Pal.danger
        ..strokeWidth = 1.6;
      canvas.drawLine(s(st.calibA!), s(st.cursor!), p);
      canvas.drawCircle(s(st.calibA!), 4, p);
    }
    if (st.tool == Tool.place && st.placing != null && st.cursor != null) {
      final it = st.placing!;
      _drawItem(canvas, st.cursor!, 0, it.w, it.d, it.shape, Color(it.color), ghost: true);
    }
    if (st.dropGhost != null) {
      final (it, p) = st.dropGhost!;
      _drawItem(canvas, p, 0, it.w, it.d, it.shape, Color(it.color), ghost: true);
    }
  }

  void _walker(Canvas canvas) {
    final w = st.walker;
    if (w == null) return;
    final (pos, yaw) = w;
    final c = s(pos);
    final dir = Offset(math.sin(yaw), -math.cos(yaw));
    final l = rotate(dir, -0.55) * 52, r = rotate(dir, 0.55) * 52;
    final cone = Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx + l.dx, c.dy + l.dy)
      ..lineTo(c.dx + r.dx, c.dy + r.dy)
      ..close();
    canvas.drawPath(cone, Paint()..shader = ui.Gradient.radial(c, 52, [Pal.accent.withAlpha(120), Pal.accent.withAlpha(0)]));
    canvas.drawCircle(c, 8, Paint()..color = Colors.white);
    canvas.drawCircle(c, 6, Paint()..color = Pal.accent);
  }

  // ---------------------------------------------------------------- pomoćno
  void _dashed(Canvas canvas, Offset a, Offset b, Paint p, {double dash = 5, double gap = 4}) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final u = d / len;
    for (var t = 0.0; t < len; t += dash + gap) {
      canvas.drawLine(a + u * t, a + u * math.min(t + dash, len), p);
    }
  }

  TextPainter _layout(String t, TextStyle style, {double? maxWidth}) => TextPainter(
        text: TextSpan(text: t, style: style),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth ?? double.infinity);

  void _paintText(Canvas canvas, TextPainter tp, Offset at, {double angle = 0, bool halo = false}) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    if (angle != 0) canvas.rotate(angle);
    final o = Offset(-tp.width / 2, -tp.height / 2);
    if (halo) {
      canvas.drawRRect(RRect.fromRectAndRadius((o & tp.size).inflate(2), const Radius.circular(3)),
          Paint()..color = Colors.white.withAlpha(205));
    }
    tp.paint(canvas, o);
    canvas.restore();
  }

  void _text(Canvas canvas, String t, Offset at, TextStyle style, {bool halo = false, double? maxWidth}) =>
      _paintText(canvas, _layout(t, style, maxWidth: maxWidth), at, halo: halo);

  @override
  bool shouldRepaint(covariant PlanPainter oldDelegate) => true;
}

/// Simboli namještaja u tlocrtu (pogled odozgo), u stilu arhitektonskih blokova.
/// Koordinate su lokalne, u pikselima; stražnja strana objekta je gore (-y).
class ItemSymbols {
  ItemSymbols(this.c, this.w, this.d, this.ppm, this.color, this.shape, {this.preview = false});

  final Canvas c;
  final double w, d;
  final double ppm;
  final Color color;
  final String shape;
  final bool preview;

  late final Rect r = Rect.fromCenter(center: Offset.zero, width: w, height: d);
  late final Paint line = Paint()
    ..color = Pal.inkSoft
    ..style = PaintingStyle.stroke
    ..strokeWidth = preview ? 0.6 : (ppm > 60 ? 1.0 : 0.8);
  late final Paint thin = Paint()
    ..color = Pal.inkSoft.withAlpha(140)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.7;
  Paint fillOf(Color col, [double t = 0.2]) => Paint()..color = Color.lerp(Colors.white, col, t)!;
  Paint get fill => fillOf(color);
  double m(double meters) => meters * ppm;

  void box([Rect? rr, double radius = 1.5, Paint? f]) {
    final rect = RRect.fromRectAndRadius(rr ?? r, Radius.circular(radius));
    c.drawRRect(rect, f ?? fill);
    c.drawRRect(rect, line);
  }

  void oval([Rect? rr, Paint? f]) {
    c.drawOval(rr ?? r, f ?? fill);
    c.drawOval(rr ?? r, line);
  }

  void ln(Offset a, Offset b, [Paint? p]) => c.drawLine(a, b, p ?? line);

  void draw() {
    if (w < 2 || d < 2) {
      c.drawRect(r, line);
      return;
    }
    switch (shape) {
      case 'bed':
      case 'bunk':
        box();
        final pillowH = math.min(m(0.42), d * 0.2);
        final double2 = w > m(1.2);
        final pw = double2 ? (w - m(0.18)) / 2 : w - m(0.12);
        final top = r.top + m(0.08);
        final pf = fillOf(Colors.white, 0);
        box(Rect.fromLTWH(r.left + m(0.06), top, pw, pillowH), m(0.06), pf);
        if (double2) box(Rect.fromLTWH(r.right - m(0.06) - pw, top, pw, pillowH), m(0.06), pf);
        final fold = r.top + d * 0.36;
        ln(Offset(r.left, fold), Offset(r.right, fold));
        ln(Offset(r.right - w * 0.3, r.bottom), Offset(r.right, r.bottom - w * 0.3), thin);
        if (shape == 'bunk') c.drawRect(r.deflate(m(0.05)), thin);
      case 'sofa':
        box(r, m(0.08));
        final back = math.min(m(0.2), d * 0.25);
        final arm = math.min(m(0.18), w * 0.2);
        ln(Offset(r.left + arm, r.top + back), Offset(r.right - arm, r.top + back));
        ln(Offset(r.left + arm, r.top + back), Offset(r.left + arm, r.bottom));
        ln(Offset(r.right - arm, r.top + back), Offset(r.right - arm, r.bottom));
        final seat = w - 2 * arm;
        final n = math.max(1, (seat / m(0.7)).round());
        for (var i = 1; i < n; i++) {
          final x = r.left + arm + seat * i / n;
          ln(Offset(x, r.top + back), Offset(x, r.bottom), thin);
        }
      case 'sofa_corner':
        final sd = math.min(m(0.95), d), cw = math.min(m(0.95), w);
        final p = Path()
          ..moveTo(r.left, r.top)
          ..lineTo(r.right, r.top)
          ..lineTo(r.right, r.bottom)
          ..lineTo(r.right - cw, r.bottom)
          ..lineTo(r.right - cw, r.top + sd)
          ..lineTo(r.left, r.top + sd)
          ..close();
        c.drawPath(p, fill);
        c.drawPath(p, line);
        final b = m(0.2), arm = m(0.18);
        ln(Offset(r.left + arm, r.top + b), Offset(r.right - b, r.top + b));
        ln(Offset(r.right - b, r.top + b), Offset(r.right - b, r.bottom));
        ln(Offset(r.left + arm, r.top + b), Offset(r.left + arm, r.top + sd));
        final seat = w - arm - b;
        final n = math.max(1, (seat / m(0.75)).round());
        for (var i = 1; i < n; i++) {
          final x = r.left + arm + seat * i / n;
          if (x < r.right - cw) ln(Offset(x, r.top + b), Offset(x, r.top + sd), thin);
        }
      case 'table':
      case 'island':
        box(r, m(0.02));
        if (shape == 'island') ln(Offset(r.left, r.top + m(0.6)), Offset(r.right, r.top + m(0.6)), thin);
      case 'table_round':
      case 'trampoline':
        oval();
        if (shape == 'trampoline') c.drawOval(r.deflate(m(0.25)), thin);
      case 'rug_round':
        oval(r, fillOf(color, 0.45));
        c.drawOval(r.deflate(m(0.08)), thin);
      case 'chair':
        box(Rect.fromLTRB(r.left + w * 0.05, r.top + d * 0.12, r.right - w * 0.05, r.bottom), m(0.04));
        box(Rect.fromLTRB(r.left, r.top, r.right, r.top + math.max(2, d * 0.14)), m(0.02), fillOf(color, 0.45));
      case 'stool':
        oval();
      case 'wardrobe':
        box(r, 1);
        final y = r.top + d * 0.5;
        _dash(Offset(r.left + m(0.05), y), Offset(r.right - m(0.05), y), thin);
        final n = math.max(2, (w / m(0.12)).floor());
        for (var i = 1; i < n; i += 2) {
          final x = r.left + w * i / n;
          ln(Offset(x - m(0.05), y - d * 0.3), Offset(x + m(0.05), y + d * 0.3), thin);
        }
      case 'dresser':
      case 'tv_stand':
      case 'tall':
      case 'dishwasher':
        box(r, 1);
        ln(Offset(r.left, r.bottom - m(0.04)), Offset(r.right, r.bottom - m(0.04)), thin);
        if (shape == 'dishwasher') ln(r.topLeft, r.bottomRight, thin);
      case 'pouf':
        if ((w - d).abs() < m(0.05)) {
          oval();
        } else {
          box(r, m(0.06));
        }
      case 'bench':
        box(r, m(0.02));
        for (var i = 1; i < 3; i++) {
          ln(Offset(r.left, r.top + d * i / 3), Offset(r.right, r.top + d * i / 3), thin);
        }
      case 'vitrine':
        box(r, 1);
        c.drawRect(r.deflate(m(0.03)), thin);
        ln(Offset(0, r.bottom - m(0.03)), Offset(0, r.top + m(0.03)), thin);
      case 'crib':
        box(r, 1);
        c.drawRect(r.deflate(m(0.04)), thin);
        final bars = math.max(2, (d / m(0.1)).floor());
        for (var i = 1; i < bars; i++) {
          ln(Offset(r.left, r.top + d * i / bars), Offset(r.left + m(0.04), r.top + d * i / bars), thin);
          ln(Offset(r.right - m(0.04), r.top + d * i / bars), Offset(r.right, r.top + d * i / bars), thin);
        }
      case 'shelf':
      case 'box':
        box(r, 1);
        ln(r.topLeft, r.bottomRight, thin);
      case 'kitchen':
      case 'vanity':
        box(r, 1);
        ln(Offset(r.left, r.bottom - m(0.04)), Offset(r.right, r.bottom - m(0.04)), thin);
        if (shape == 'vanity') {
          c.drawOval(Rect.fromCenter(center: Offset(0, m(0.02)), width: math.min(w * 0.6, m(0.5)), height: d * 0.55), line);
        } else if (w >= m(1.7)) {
          final sink = Rect.fromCenter(center: Offset(-w * 0.18, 0), width: m(0.75), height: d * 0.62);
          c.drawRRect(RRect.fromRectAndRadius(sink, Radius.circular(m(0.04))), line);
          ln(Offset(sink.center.dx, sink.top), Offset(sink.center.dx, sink.bottom), thin);
          _hob(Offset(w * 0.22, 0));
        }
      case 'stove':
        box(r, 1);
        _hob(Offset.zero);
      case 'fridge':
        box(r, 1);
        ln(Offset(r.left, r.bottom - m(0.06)), Offset(r.right, r.bottom - m(0.06)));
        ln(Offset(r.left + w * 0.3, r.top + d * 0.3), Offset(r.right - w * 0.3, r.top + d * 0.3), thin);
      case 'washer':
        box(r, m(0.03));
        c.drawCircle(Offset(0, d * 0.05), math.min(w, d) * 0.32, line);
      case 'toilet':
        box(Rect.fromLTRB(r.left, r.top, r.right, r.top + d * 0.3), m(0.03));
        oval(Rect.fromLTRB(r.left + w * 0.06, r.top + d * 0.26, r.right - w * 0.06, r.bottom));
      case 'bath':
        box(r, m(0.06));
        c.drawRRect(RRect.fromRectAndRadius(r.deflate(m(0.07)), Radius.circular(m(0.25))), line);
        c.drawCircle(Offset(r.left + m(0.25), 0), m(0.03), line);
      case 'shower':
        box(r, 1);
        ln(r.topLeft, r.bottomRight, thin);
        ln(r.topRight, r.bottomLeft, thin);
        c.drawCircle(Offset.zero, m(0.04), line);
      case 'tv':
        box(r, 1);
        final sw = math.min(w * 0.8, m(1.45));
        c.drawRect(Rect.fromCenter(center: Offset(0, r.top + m(0.12)), width: sw, height: math.max(2, m(0.05))),
            Paint()..color = Pal.ink);
      case 'lamp':
        oval(r, fillOf(const Color(0xFFF3E4B8), 0.6));
        ln(Offset(r.left, 0), Offset(r.right, 0), thin);
        ln(Offset(0, r.top), Offset(0, r.bottom), thin);
      case 'plant':
        oval(r, fillOf(color, 0.35));
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          ln(Offset.zero, Offset(math.cos(a), math.sin(a)) * (math.min(w, d) * 0.42), thin);
        }
      case 'rug':
        c.drawRect(r, fillOf(color, 0.45));
        c.drawRect(r.deflate(m(0.06)), thin);
      case 'fireplace':
        box(r, 1);
        final p = Path()
          ..moveTo(r.left + w * 0.2, r.bottom)
          ..lineTo(r.left + w * 0.3, r.top + d * 0.3)
          ..lineTo(r.right - w * 0.3, r.top + d * 0.3)
          ..lineTo(r.right - w * 0.2, r.bottom);
        c.drawPath(p, line);
      case 'stairs':
        box(r, 1);
        final steps = math.max(2, (d / m(0.28)).floor());
        for (var i = 1; i < steps; i++) {
          final y = r.top + d * i / steps;
          ln(Offset(r.left, y), Offset(r.right, y), thin);
        }
        ln(Offset(0, r.bottom - m(0.15)), Offset(0, r.top + m(0.2)));
        ln(Offset(0, r.top + m(0.2)), Offset(-m(0.12), r.top + m(0.4)));
        ln(Offset(0, r.top + m(0.2)), Offset(m(0.12), r.top + m(0.4)));
      case 'tree':
      case 'cypress':
        final rad = math.min(w, d) / 2;
        final p = Path();
        final n = shape == 'tree' ? 11 : 7;
        for (var i = 0; i <= n; i++) {
          final a = i * 2 * math.pi / n;
          final pt = Offset(math.cos(a), math.sin(a)) * rad;
          if (i == 0) {
            p.moveTo(pt.dx, pt.dy);
          } else {
            p.arcToPoint(pt, radius: Radius.circular(rad * 0.35), clockwise: true);
          }
        }
        c.drawPath(p, fillOf(color, 0.4));
        c.drawPath(
            p,
            Paint()
              ..color = Color.lerp(color, Pal.ink, 0.3)!
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.9);
        c.drawCircle(Offset.zero, math.max(1.5, rad * 0.08), Paint()..color = Color.lerp(color, Pal.ink, 0.4)!);
      case 'hedge':
        box(r, math.min(w, d) / 2, fillOf(color, 0.42));
      case 'flowerbed':
        box(r, 2, fillOf(color, 0.35));
        final rnd = math.Random(7);
        final count = (w * d / 140).clamp(3, 40).toInt();
        const petals = [Color(0xFFD9667A), Color(0xFFE8C04A), Color(0xFF8E6BC6)];
        for (var i = 0; i < count; i++) {
          c.drawCircle(Offset((rnd.nextDouble() - .5) * w * .85, (rnd.nextDouble() - .5) * d * .7), math.max(1.5, m(0.05)),
              Paint()..color = petals[i % 3]);
        }
      case 'fence':
        ln(Offset(r.left, 0), Offset(r.right, 0), Paint()
          ..color = Pal.inkSoft
          ..strokeWidth = 1.6);
        final n = math.max(1, (w / m(1)).round());
        for (var i = 0; i <= n; i++) {
          c.drawRect(Rect.fromCenter(center: Offset(r.left + w * i / n, 0), width: math.max(3, m(0.08)), height: math.max(3, m(0.08))),
              Paint()..color = Pal.inkSoft);
        }
      case 'pool':
        box(r, m(0.1), Paint()..color = Pal.water);
        c.drawRRect(RRect.fromRectAndRadius(r.deflate(m(0.12)), Radius.circular(m(0.08))), thin);
        final stp = Rect.fromLTWH(r.right - m(1.2), r.top + m(0.12), m(1.0), m(0.6));
        for (var i = 1; i < 3; i++) {
          ln(Offset(stp.left, stp.top + stp.height * i / 3), Offset(stp.right, stp.top + stp.height * i / 3), thin);
        }
      case 'deck':
        box(r, 0, fillOf(color, 0.35));
        final n = math.max(2, (d / m(0.15)).floor());
        for (var i = 1; i < n; i++) {
          ln(Offset(r.left, r.top + d * i / n), Offset(r.right, r.top + d * i / n), thin);
        }
      case 'path':
        box(r, 0, fillOf(color, 0.5));
        final step = m(0.5);
        if (step > 4) {
          for (var y = r.top + step; y < r.bottom; y += step) {
            ln(Offset(r.left, y), Offset(r.right, y), thin);
          }
          for (var x = r.left + step; x < r.right; x += step) {
            ln(Offset(x, r.top), Offset(x, r.bottom), thin);
          }
        }
      case 'carport':
        _dash(r.topLeft, r.topRight, line);
        _dash(r.topRight, r.bottomRight, line);
        _dash(r.bottomRight, r.bottomLeft, line);
        _dash(r.bottomLeft, r.topLeft, line);
        for (final k in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
          c.drawRect(Rect.fromCenter(center: k, width: math.max(3, m(0.14)), height: math.max(3, m(0.14))),
              Paint()..color = Pal.inkSoft);
        }
      case 'shed':
        box(r, 0, fillOf(color, 0.3));
        ln(Offset(r.left, 0), Offset(r.right, 0));
      case 'swing':
        ln(Offset(r.left, r.top), Offset(r.left, r.bottom));
        ln(Offset(r.right, r.top), Offset(r.right, r.bottom));
        ln(Offset(r.left, 0), Offset(r.right, 0), Paint()
          ..color = Pal.inkSoft
          ..strokeWidth = 1.6);
        box(Rect.fromCenter(center: Offset(-w * 0.2, 0), width: m(0.45), height: m(0.2)));
        box(Rect.fromCenter(center: Offset(w * 0.2, 0), width: m(0.45), height: m(0.2)));
      case 'grill':
        box(r, m(0.04));
        c.drawCircle(Offset(-w * 0.15, 0), math.min(w, d) * 0.35, line);
      case 'lounger':
        box(r, m(0.04));
        ln(Offset(r.left, r.top + d * 0.32), Offset(r.right, r.top + d * 0.32));
      case 'umbrella':
        final rad = math.min(w, d) / 2;
        final p = Path();
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4 + math.pi / 8;
          final pt = Offset(math.cos(a), math.sin(a)) * rad;
          if (i == 0) {
            p.moveTo(pt.dx, pt.dy);
          } else {
            p.lineTo(pt.dx, pt.dy);
          }
        }
        p.close();
        c.drawPath(p, fillOf(color, 0.5));
        c.drawPath(p, line);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4 + math.pi / 8;
          ln(Offset.zero, Offset(math.cos(a), math.sin(a)) * rad, thin);
        }
      case 'car':
        box(r, m(0.35), fillOf(color, 0.45));
        final ws = r.top + d * 0.3, rs = r.bottom - d * 0.22;
        box(Rect.fromLTRB(r.left + w * 0.12, ws, r.right - w * 0.12, rs), m(0.15), fillOf(Pal.ink, 0.15));
      default:
        box();
    }
  }

  void _hob(Offset center) {
    final rr = math.min(m(0.075), math.min(w, d) * 0.15);
    for (final o in const [Offset(-1, -1), Offset(1, -1), Offset(-1, 1), Offset(1, 1)]) {
      c.drawCircle(center + o * m(0.13), rr, line);
    }
  }

  void _dash(Offset a, Offset b, Paint p) {
    final dv = b - a;
    final len = dv.distance;
    if (len == 0) return;
    final u = dv / len;
    for (var t = 0.0; t < len; t += 7) {
      c.drawLine(a + u * t, a + u * math.min(t + 4, len), p);
    }
  }
}
