import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/catalog.dart';
import '../models/geometry.dart';
import '../models/plan.dart';
import '../state/plan_controller.dart';

const _bg = Color(0xFFFAFAF7);
const _accent = Color(0xFF1E6FD9);

class PlanPainter extends CustomPainter {
  PlanPainter({
    required this.c,
    required this.scale,
    required this.pan,
    this.hover,
    this.wallStart,
    this.wallEnd,
    this.roomStart,
    this.roomEnd,
    this.calibA,
  });

  final PlanController c;
  final double scale;
  final Offset pan;
  final Offset? hover;
  final Offset? wallStart;
  final Offset? wallEnd;
  final Offset? roomStart;
  final Offset? roomEnd;
  final Offset? calibA;

  Plan get plan => c.plan;
  Offset s(Offset w) => w * scale + pan;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);
    _grid(canvas, size);
    _image(canvas);
    _rooms(canvas);
    _items(canvas, floorOnly: true);
    _walls(canvas);
    _openings(canvas);
    _items(canvas, floorOnly: false);
    _dimensions(canvas);
    _nodes(canvas);
    _previews(canvas);
  }

  // ---------------------------------------------------------------- mreža
  void _grid(Canvas canvas, Size size) {
    final tl = (Offset.zero - pan) / scale;
    final br = (Offset(size.width, size.height) - pan) / scale;
    void lines(double step, Paint p) {
      for (var x = (tl.dx / step).floorToDouble() * step; x <= br.dx; x += step) {
        canvas.drawLine(s(Offset(x, tl.dy)), s(Offset(x, br.dy)), p);
      }
      for (var y = (tl.dy / step).floorToDouble() * step; y <= br.dy; y += step) {
        canvas.drawLine(s(Offset(tl.dx, y)), s(Offset(br.dx, y)), p);
      }
    }

    if (scale > 90) lines(0.1, Paint()..color = const Color(0xFFF0F0EA));
    if (scale > 20) lines(0.5, Paint()..color = const Color(0xFFE8E8E1));
    lines(1, Paint()..color = const Color(0xFFDADAD2));
    lines(5, Paint()
      ..color = const Color(0xFFC9C9C0)
      ..strokeWidth = 1.2);
  }

  void _image(Canvas canvas) {
    final im = plan.image, img = c.bgImage;
    if (im == null || img == null) return;
    final dst = Rect.fromLTWH(
      s(im.origin).dx,
      s(im.origin).dy,
      im.widthPx * im.metersPerPixel * scale,
      im.heightPx * im.metersPerPixel * scale,
    );
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    canvas.drawImageRect(img, src, dst,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, im.opacity)
          ..filterQuality = FilterQuality.medium);
  }

  // ---------------------------------------------------------------- sobe
  void _rooms(Canvas canvas) {
    for (final r in plan.rooms) {
      final poly = plan.roomPolygon(r);
      if (poly.length < 3) continue;
      final path = Path()..addPolygon([for (final p in poly) s(p)], true);
      final sel = c.selection == Selection(SelKind.room, r.id);
      canvas.drawPath(path, Paint()..color = Color(r.floorColor).withAlpha(sel ? 150 : 95));
      if (sel) {
        canvas.drawPath(
            path,
            Paint()
              ..color = _accent
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }
      final ctr = s(centroid(poly));
      _text(canvas, r.name, ctr - const Offset(0, 8), size: 13, weight: FontWeight.w600);
      _text(canvas, '${polygonArea(poly).toStringAsFixed(1)} m²', ctr + const Offset(0, 9),
          size: 11, color: const Color(0xFF666660));
    }
  }

  // ---------------------------------------------------------------- zidovi
  List<Offset> _wallQuad(Wall w, {double extra = 0}) {
    final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
    final len = (b - a).distance;
    if (len == 0) return [a, a, a, a];
    final dir = (b - a) / len;
    final n = Offset(-dir.dy, dir.dx) * (w.thickness / 2 + extra);
    return [a + n, b + n, b - n, a - n];
  }

  void _walls(Canvas canvas) {
    for (final w in plan.walls) {
      final sel = c.selection == Selection(SelKind.wall, w.id);
      final q = _wallQuad(w);
      final path = Path()..addPolygon([for (final p in q) s(p)], true);
      canvas.drawPath(path, Paint()..color = sel ? _accent : const Color(0xFF2F3437));
      // spojevi – kružić u čvoru da kutovi izgledaju zatvoreno
      for (final id in [w.a, w.b]) {
        canvas.drawCircle(s(plan.nodePos(id)), w.thickness / 2 * scale,
            Paint()..color = sel ? _accent : const Color(0xFF2F3437));
      }
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
      final n = Offset(-dir.dy, dir.dx);
      final center = a + dir * (o.t * len);
      final hw = o.width / 2;
      final ht = w.thickness / 2 + 0.01;
      final p0 = center - dir * hw, p1 = center + dir * hw;
      final gap = [p0 + n * ht, p1 + n * ht, p1 - n * ht, p0 - n * ht];
      final sel = c.selection == Selection(SelKind.opening, o.id);
      canvas.drawPath(Path()..addPolygon([for (final p in gap) s(p)], true),
          Paint()..color = o.type == OpeningType.window ? const Color(0xFFDCEEFF) : _bg);
      final line = Paint()
        ..color = sel ? _accent : const Color(0xFF2F3437)
        ..strokeWidth = sel ? 2.2 : 1.3
        ..style = PaintingStyle.stroke;
      if (o.type == OpeningType.door) {
        // krilo + luk otvaranja
        final leafEnd = p0 + n * o.width;
        canvas.drawLine(s(p0), s(leafEnd), line);
        final a0 = math.atan2(n.dy, n.dx);
        var sweep = math.atan2(dir.dy, dir.dx) - a0;
        while (sweep > math.pi) {
          sweep -= 2 * math.pi;
        }
        while (sweep < -math.pi) {
          sweep += 2 * math.pi;
        }
        canvas.drawArc(Rect.fromCircle(center: s(p0), radius: o.width * scale), a0, sweep,
            false, line..strokeWidth = sel ? 2.0 : 1.0);
      } else {
        canvas.drawLine(s(p0 + n * (ht * 0.4)), s(p1 + n * (ht * 0.4)), line);
        canvas.drawLine(s(p0 - n * (ht * 0.4)), s(p1 - n * (ht * 0.4)), line);
        canvas.drawLine(s(p0 + n * ht), s(p0 - n * ht), line);
        canvas.drawLine(s(p1 + n * ht), s(p1 - n * ht), line);
      }
    }
  }

  void _dimensions(Canvas canvas) {
    for (final w in plan.walls) {
      final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
      final len = (b - a).distance;
      if (len * scale < 45) continue;
      final sel = c.selection == Selection(SelKind.wall, w.id);
      final dir = (b - a) / len;
      final n = Offset(-dir.dy, dir.dx);
      var ang = math.atan2(dir.dy, dir.dx);
      if (ang > math.pi / 2) ang -= math.pi;
      if (ang < -math.pi / 2) ang += math.pi;
      final at = s((a + b) / 2) + n * (w.thickness / 2 * scale + 11);
      _text(canvas, '${len.toStringAsFixed(2)} m', at,
          angle: ang,
          size: sel ? 12.0 : 10.0,
          color: sel ? _accent : const Color(0xFF55554F),
          weight: sel ? FontWeight.w700 : FontWeight.w500,
          bg: true);
    }
  }

  void _nodes(Canvas canvas) {
    if (c.tool != Tool.select && c.tool != Tool.wall) return;
    final selWall = c.selection.kind == SelKind.wall ? plan.wallById(c.selection.id) : null;
    for (final n in plan.nodes.values) {
      final sel = c.selection == Selection(SelKind.node, n.id) ||
          (selWall != null && (selWall.a == n.id || selWall.b == n.id));
      final p = s(n.pos);
      canvas.drawCircle(p, sel ? 5.5 : 3.2, Paint()..color = Colors.white);
      canvas.drawCircle(
          p,
          sel ? 5.5 : 3.2,
          Paint()
            ..color = sel ? _accent : const Color(0xFF8A8A84)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  // ---------------------------------------------------------------- namještaj
  static const _floorShapes = {'rug', 'deck', 'pool'};

  void _items(Canvas canvas, {required bool floorOnly}) {
    for (final it in plan.items) {
      if (_floorShapes.contains(it.shape) != floorOnly) continue;
      _itemRect(canvas, it.pos, it.rotation, it.w, it.d, Color(it.color), it.name,
          selected: c.selection == Selection(SelKind.item, it.id), shape: it.shape);
    }
  }

  void _itemRect(Canvas canvas, Offset pos, double rot, double w, double d, Color color,
      String label,
      {bool selected = false, bool ghost = false, String shape = 'box'}) {
    canvas.save();
    canvas.translate(s(pos).dx, s(pos).dy);
    canvas.rotate(rot);
    final r = Rect.fromCenter(center: Offset.zero, width: w * scale, height: d * scale);
    final round = shape == 'tree' || shape == 'plant' || shape == 'umbrella' || shape == 'lamp';
    final fill = Paint()..color = color.withAlpha(ghost ? 90 : 205);
    final stroke = Paint()
      ..color = selected ? _accent : const Color(0xFF3B3B36).withAlpha(ghost ? 120 : 200)
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2.4 : 1;
    if (round) {
      canvas.drawOval(r, fill);
      canvas.drawOval(r, stroke);
    } else {
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(2));
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, stroke);
      // stražnja strana (uz zid) deblja linija
      if (!_floorShapes.contains(shape)) {
        canvas.drawLine(r.topLeft, r.topRight,
            Paint()
              ..color = const Color(0xFF3B3B36).withAlpha(ghost ? 120 : 220)
              ..strokeWidth = 3);
      }
    }
    if (w * scale > 46 && d * scale > 18) {
      final lum = color.computeLuminance();
      _text(canvas, label, Offset.zero,
          size: 10,
          color: lum > 0.45 ? const Color(0xFF2B2B28) : Colors.white,
          maxWidth: w * scale - 6);
    }
    canvas.restore();
  }

  // ---------------------------------------------------------------- pregledi
  void _previews(Canvas canvas) {
    final preview = Paint()
      ..color = _accent.withAlpha(150)
      ..strokeWidth = 0.2 * scale
      ..strokeCap = StrokeCap.round;
    if (c.tool == Tool.wall && wallStart != null && wallEnd != null) {
      canvas.drawLine(s(wallStart!), s(wallEnd!), preview);
      final len = (wallEnd! - wallStart!).distance;
      _text(canvas, '${len.toStringAsFixed(2)} m', s(wallEnd!) + const Offset(18, -16),
          size: 12, color: _accent, weight: FontWeight.w700, bg: true);
    }
    if (c.tool == Tool.wall && wallStart == null && hover != null) {
      canvas.drawCircle(s(hover!), 4, Paint()..color = _accent);
    }
    if (c.tool == Tool.room && roomStart != null && roomEnd != null) {
      final r = Rect.fromPoints(s(roomStart!), s(roomEnd!));
      canvas.drawRect(r, Paint()..color = _accent.withAlpha(40));
      canvas.drawRect(
          r,
          Paint()
            ..color = _accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.2 * scale);
      final wm = (roomEnd!.dx - roomStart!.dx).abs(), hm = (roomEnd!.dy - roomStart!.dy).abs();
      _text(canvas, '${wm.toStringAsFixed(2)} × ${hm.toStringAsFixed(2)} m\n${(wm * hm).toStringAsFixed(1)} m²',
          r.center,
          size: 12, color: _accent, weight: FontWeight.w700, bg: true);
    }
    if (c.tool == Tool.calibrate && calibA != null && hover != null) {
      final p = Paint()
        ..color = const Color(0xFFD93B1E)
        ..strokeWidth = 2;
      canvas.drawLine(s(calibA!), s(hover!), p);
      canvas.drawCircle(s(calibA!), 5, p);
    }
    if (c.tool == Tool.place && c.placing != null && hover != null) {
      final CatalogItem it = c.placing!;
      _itemRect(canvas, Offset(roundTo(hover!.dx, 0.05), roundTo(hover!.dy, 0.05)), 0, it.w,
          it.d, Color(it.color), it.name,
          ghost: true, shape: it.shape);
    }
  }

  void _text(Canvas canvas, String t, Offset at,
      {double size = 11,
      Color color = const Color(0xFF333330),
      double angle = 0,
      bool bg = false,
      FontWeight weight = FontWeight.w500,
      double? maxWidth}) {
    final tp = TextPainter(
      text: TextSpan(
          text: t, style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.15)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    if (angle != 0) canvas.rotate(angle);
    final o = Offset(-tp.width / 2, -tp.height / 2);
    if (bg) {
      canvas.drawRRect(RRect.fromRectAndRadius((o & tp.size).inflate(2.5), const Radius.circular(3)),
          Paint()..color = const Color(0xE6FFFFFF));
    }
    tp.paint(canvas, o);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PlanPainter oldDelegate) => true;
}
