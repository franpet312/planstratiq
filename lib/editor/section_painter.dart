import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/collision.dart';
import '../models/geometry.dart';
import '../models/headroom.dart';
import '../models/plan.dart';
import '../models/roof.dart';
import '../models/stairs.dart';

/// Vertikalni presjek kuće po crti presjeka A–A: presječeni zidovi (s otvorima), ploče, teren,
/// krov, stubišta, namještaj kroz koji prolazi crta, kote visina i oznake etaža.
///
/// Koordinate presjeka: s – udaljenost duž crte (m), z – visina iznad terena (m).

const slab = 0.25;

class _Cut {
  _Cut(this.s0, this.s1, this.z0, this.z1);
  final double s0, s1, z0, z1;
}

class _Gap {
  _Gap(this.s0, this.s1, this.z0, this.z1, this.type);
  final double s0, s1, z0, z1;
  final OpeningType type;
}

class SectionGeometry {
  final walls = <_Cut>[];
  final gaps = <_Gap>[];
  final slabs = <_Cut>[];
  final items = <(_Cut, int)>[];
  final stairs = <List<Offset>>[]; // (s, z)
  final labels = <(double, double, String)>[];
  final levels = <(double, double, String)>[]; // kota poda, visina, naziv
  final roofOuter = <List<Offset>>[];
  final roofInner = <List<Offset>>[];
  final terrain = <Offset>[]; // (s, z) teren duž crte
  double sMin = 0, sMax = 1, zMin = -0.6, zMax = 3;
  double length = 1;
}

/// Presjecište crte (p + u·s) s dužinom c→d: (s, t na dužini) ili null.
(double, double)? _hit(Offset p, Offset u, Offset c, Offset d) {
  final e = d - c;
  final den = cross(u, e);
  if (den.abs() < 1e-9) return null;
  final w = c - p;
  final s = cross(w, e) / den;
  final t = cross(w, u) / den;
  if (t < -1e-6 || t > 1 + 1e-6) return null;
  return (s, t);
}

/// Intervali crte unutar poligona.
List<(double, double)> _inside(Offset p, Offset u, List<Offset> poly) {
  final ss = <double>[];
  for (var i = 0; i < poly.length; i++) {
    final h = _hit(p, u, poly[i], poly[(i + 1) % poly.length]);
    if (h != null) ss.add(h.$1);
  }
  ss.sort();
  final out = <(double, double)>[];
  for (var i = 0; i + 1 < ss.length; i++) {
    final m = (ss[i] + ss[i + 1]) / 2;
    if (ss[i + 1] - ss[i] > 1e-4 && pointInPolygon(p + u * m, poly)) out.add((ss[i], ss[i + 1]));
  }
  return out;
}

SectionGeometry buildSection(Plan plan, SectionLine sec, RoofShape? roof, {double Function(Offset)? terrainAt}) {
  final g = SectionGeometry();
  final d = sec.b - sec.a;
  final len = d.distance;
  if (len < 0.1) return g;
  // crta se produži preko krajeva tako da presjek uvijek obuhvati cijelu kuću na tom pravcu
  final u0 = d / len;
  final u = sec.flip ? -u0 : u0;
  final o = sec.flip ? sec.b : sec.a;
  var lo = double.infinity, hi = -double.infinity;
  final top = plan.levels.isEmpty ? null : plan.levels.reduce((a, b) => a.elevation >= b.elevation ? a : b);

  // otvori u pločama: stubišta s etaže ispod probijaju ploču etaže iznad
  final holes = <Level, List<(double, double)>>{};
  for (final lvl in plan.levels) {
    final up = levelAbove(plan, lvl);
    if (up == null) continue;
    for (final it in lvl.items) {
      if (!stairShapes.contains(it.shape)) continue;
      holes.putIfAbsent(up, () => []).addAll(_inside(o, u, stairOutline(it)));
    }
  }
  List<(double, double)> minus((double, double) iv, List<(double, double)> hs) {
    var out = [iv];
    for (final (h0, h1) in hs) {
      out = [
        for (final (a, b) in out) ...[
          if (h0 > a) (a, math.min(b, h0)),
          if (h1 < b) (math.max(a, h1), b),
        ]
      ].where((e) => e.$2 - e.$1 > 1e-3).toList();
    }
    return out;
  }

  for (final lvl in plan.levels) {
    final z0 = lvl.elevation;
    Offset np(String id) => lvl.nodes[id]?.pos ?? Offset.zero;
    double wallTop(Offset p) {
      if (lvl.attic && roof != null && identical(lvl, top)) {
        final h = roof.heightAt(p);
        if (h != null) return z0 + lvl.kneeWall + h;
      }
      return z0 + lvl.height;
    }

    var any = false;
    // zidovi
    for (final w in lvl.walls) {
      final a = np(w.a), b = np(w.b);
      final h = _hit(o, u, a, b);
      if (h == null) continue;
      final (s, t) = h;
      final wl = (b - a).distance;
      if (wl < 1e-6) continue;
      final wu = (b - a) / wl;
      final sin = cross(u, wu).abs();
      if (sin < 0.08) continue; // crta ide uzduž zida
      final half = math.min(w.thickness / 2 / sin, w.thickness * 1.5);
      final p = o + u * s;
      g.walls.add(_Cut(s - half, s + half, z0, wallTop(p)));
      lo = math.min(lo, s - half);
      hi = math.max(hi, s + half);
      any = true;
      for (final op in lvl.openings) {
        if (op.wallId != w.id) continue;
        if ((t * wl - op.t * wl).abs() > op.width / 2) continue;
        g.gaps.add(_Gap(s - half, s + half, z0 + op.sill, z0 + op.sill + op.height, op.type));
      }
    }
    // ploče ispod prostorija i natpisi prostorija
    for (final r in lvl.rooms) {
      final poly = [for (final id in r.nodeIds) np(id)];
      if (poly.length < 3) continue;
      for (final (s0, s1) in _inside(o, u, poly)) {
        for (final (a0, a1) in minus((s0, s1), holes[lvl] ?? const [])) {
          g.slabs.add(_Cut(a0, a1, z0 - slab, z0));
        }
        if (s1 - s0 > 1.2) g.labels.add(((s0 + s1) / 2, z0 + 1.25, r.name));
        lo = math.min(lo, s0);
        hi = math.max(hi, s1);
        any = true;
        // strop zadnje etaže kad nema potkrovlja (tavan ili ravni krov)
        if (identical(lvl, top) && !lvl.attic) g.slabs.add(_Cut(s0, s1, z0 + lvl.height, z0 + lvl.height + slab));
      }
    }
    // namještaj kroz koji prolazi crta
    for (final it in lvl.items) {
      if (electricShapes.contains(it.shape) || const {'rug', 'rug_round', 'path', 'floor_drain', 'dormer', 'roof_window'}.contains(it.shape)) continue;
      final b = itemObb(it);
      if (b == null) continue;
      final corners = [
        b.c - b.ux * b.hw - b.uz * b.hd,
        b.c + b.ux * b.hw - b.uz * b.hd,
        b.c + b.ux * b.hw + b.uz * b.hd,
        b.c - b.ux * b.hw + b.uz * b.hd,
      ];
      final iv = _inside(o, u, corners);
      if (iv.isEmpty) continue;
      final (s0, s1) = iv.first;
      lo = math.min(lo, s0);
      hi = math.max(hi, s1);
      if (stairShapes.contains(it.shape)) {
        // profil stubišta: stepenice po napretku uz stubište
        final up = levelAbove(plan, lvl);
        final rise = (up?.elevation ?? (z0 + 2.85)) - z0;
        final n = math.max(2, (rise / 0.18).ceil());
        final cs = math.cos(it.rotation), sn = math.sin(it.rotation);
        final pts = <Offset>[];
        for (var s = s0; s <= s1 + 1e-6; s += 0.02) {
          final p = o + u * s - it.pos;
          final lx = p.dx * cs + p.dy * sn, lz = -p.dx * sn + p.dy * cs;
          final k = stairProgressLocal(it, lx, lz);
          if (k == null) continue;
          final step = ((k * n).floor() + 1).clamp(1, n) / n;
          pts.add(Offset(s, z0 + step * rise));
        }
        if (pts.length > 1) g.stairs.add(pts);
        continue;
      }
      double base = 0;
      final h = it.h;
      if (ceilingShapes.contains(it.shape)) base = lvl.height - h;
      if (const {'wall_lamp', 'ac_indoor', 'boiler', 'water_manifold'}.contains(it.shape)) base = it.shape == 'water_manifold' ? 0.35 : 1.4;
      if (it.shape == 'drain_stack') {
        g.items.add((_Cut(s0, s1, z0, z0 + lvl.height), it.color));
        continue;
      }
      if (isFloorLike(it.shape) && !balconyShapes.contains(it.shape)) continue;
      g.items.add((_Cut(s0, s1, z0 + base, z0 + base + math.min(h, lvl.height)), it.color));
    }
    if (any) g.levels.add((z0, lvl.attic ? lvl.kneeWall : lvl.height, lvl.name));
  }
  if (!lo.isFinite) {
    lo = 0;
    hi = len;
  }
  // krov
  if (roof != null && top != null && roof.type != 'flat') {
    final zb = top.elevation + (top.attic ? top.kneeWall : top.height);
    var outer = <Offset>[], inner = <Offset>[];
    for (var s = lo - 2.5; s <= hi + 2.5; s += 0.04) {
      final h = roof.heightAt(o + u * s);
      if (h == null) {
        if (outer.length > 1) {
          g.roofOuter.add(outer);
          g.roofInner.add(inner);
        }
        outer = [];
        inner = [];
        continue;
      }
      outer.add(Offset(s, zb + h));
      inner.add(Offset(s, zb + h - 0.2));
    }
    if (outer.length > 1) {
      g.roofOuter.add(outer);
      g.roofInner.add(inner);
    }
  }
  var zTop = 0.0;
  for (final w in g.walls) {
    zTop = math.max(zTop, w.z1);
  }
  for (final s in g.slabs) {
    zTop = math.max(zTop, s.z1);
  }
  for (final r in g.roofOuter) {
    for (final p in r) {
      zTop = math.max(zTop, p.dy);
      lo = math.min(lo, p.dx);
      hi = math.max(hi, p.dx);
    }
  }
  var zLow = 0.0;
  for (final l in g.levels) {
    zLow = math.min(zLow, l.$1 - slab);
  }
  g.sMin = lo - 1.0;
  g.sMax = hi + 1.0;
  for (var s = g.sMin; s <= g.sMax + 1e-6; s += 0.05) {
    final z = terrainAt?.call(o + u * s) ?? 0;
    g.terrain.add(Offset(s, z));
    zLow = math.min(zLow, z);
    zTop = math.max(zTop, z);
  }
  g.zMin = zLow - 0.8;
  g.zMax = zTop + 0.6;
  g.length = len;
  return g;
}

/// Crtanje presjeka u pravokutnik [area] (px). [pxPerM] je mjerilo; ako je null, presjek se prilagodi.
void paintSection(Canvas canvas, Rect area, SectionGeometry g, {double? pxPerM, String title = 'Presjek A–A', bool print = false}) {
  final sw = g.sMax - g.sMin, zh = g.zMax - g.zMin;
  final k = pxPerM ?? math.min((area.width - 90) / sw, (area.height - 40) / zh);
  final ox = area.left + 60 + ((area.width - 90) - sw * k) / 2;
  final oy = area.bottom - 20 - ((area.height - 40) - zh * k) / 2;
  Offset P(double s, double z) => Offset(ox + (s - g.sMin) * k, oy - (z - g.zMin) * k);
  Rect R(double s0, double z0, double s1, double z1) => Rect.fromPoints(P(s0, z0), P(s1, z1));

  final ink = Paint()..color = const Color(0xFF26292B);
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = const Color(0xFF26292B);

  // teren (prati nagib izvan zaravni)
  final terr = g.terrain.isEmpty ? [Offset(g.sMin, 0), Offset(g.sMax, 0)] : g.terrain;
  final groundPath = Path()..moveTo(P(terr.first.dx, g.zMin).dx, P(terr.first.dx, g.zMin).dy);
  for (final t in terr) {
    final q = P(t.dx, t.dy);
    groundPath.lineTo(q.dx, q.dy);
  }
  groundPath.lineTo(P(terr.last.dx, g.zMin).dx, P(terr.last.dx, g.zMin).dy);
  groundPath.close();
  canvas.drawPath(groundPath, Paint()..color = const Color(0xFFEDE6D8));
  final soil = Paint()
    ..color = const Color(0xFFB4A68A)
    ..strokeWidth = 0.8;
  for (var i = 0; i < terr.length; i += 7) {
    final a = P(terr[i].dx, terr[i].dy);
    canvas.drawLine(a + const Offset(0, 3), a + const Offset(6, 9), soil);
  }

  // namještaj (svijetlo, iza svega)
  for (final (c, col) in g.items) {
    final r = R(c.s0, c.z0, c.s1, c.z1);
    canvas.drawRect(r, Paint()..color = Color(col).withAlpha(90));
    canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = const Color(0xFF8A9096));
  }

  // ploče
  final slabPaint = Paint()..color = const Color(0xFF7C7871);
  for (final c in g.slabs) {
    canvas.drawRect(R(c.s0, c.z0, c.s1, c.z1), slabPaint);
  }

  // krov (presjek pokrova + obloga)
  for (var i = 0; i < g.roofOuter.length; i++) {
    final o = g.roofOuter[i], n = g.roofInner[i];
    final path = Path()..moveTo(P(o.first.dx, o.first.dy).dx, P(o.first.dx, o.first.dy).dy);
    for (final p in o.skip(1)) {
      final q = P(p.dx, p.dy);
      path.lineTo(q.dx, q.dy);
    }
    for (final p in n.reversed) {
      final q = P(p.dx, p.dy);
      path.lineTo(q.dx, q.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFB7603F));
    canvas.save();
    canvas.clipPath(path);
    final hatch = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 0.8;
    final b = path.getBounds();
    for (var x = b.left - b.height; x < b.right; x += 5) {
      canvas.drawLine(Offset(x, b.bottom), Offset(x + b.height, b.top), hatch);
    }
    canvas.restore();
    canvas.drawPath(path, stroke);
  }

  // presječeni zidovi (crno) s otvorima
  for (final w in g.walls) {
    canvas.drawRect(R(w.s0, w.z0, w.s1, w.z1), ink);
  }
  for (final gp in g.gaps) {
    final r = R(gp.s0 - 0.01, gp.z0, gp.s1 + 0.01, gp.z1);
    canvas.drawRect(r, Paint()..color = Colors.white);
    if (gp.type == OpeningType.window || gp.type == OpeningType.balcony) {
      // okno: dvije tanke crte po sredini zida
      final cx = r.center.dx;
      final thin = Paint()
        ..color = const Color(0xFF2F6FA8)
        ..strokeWidth = 0.9;
      canvas.drawLine(Offset(cx - 1.5, r.top), Offset(cx - 1.5, r.bottom), thin);
      canvas.drawLine(Offset(cx + 1.5, r.top), Offset(cx + 1.5, r.bottom), thin);
    }
    canvas.drawLine(r.topLeft, r.topRight, stroke);
    if (gp.type == OpeningType.window) canvas.drawLine(r.bottomLeft, r.bottomRight, stroke);
  }

  // stubišta
  final stairPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = const Color(0xFF8C6A45);
  for (final pts in g.stairs) {
    final path = Path();
    var prev = pts.first;
    path.moveTo(P(prev.dx, prev.dy - 0.18).dx, P(prev.dx, prev.dy - 0.18).dy);
    for (final p in pts) {
      final q = P(p.dx, p.dy);
      if ((p.dy - prev.dy).abs() > 1e-6) {
        final v = P(p.dx, prev.dy);
        path.lineTo(v.dx, v.dy);
      }
      path.lineTo(q.dx, q.dy);
      prev = p;
    }
    canvas.drawPath(path, stairPaint);
  }

  // teren crta
  final tl = Path()..moveTo(P(terr.first.dx, terr.first.dy).dx, P(terr.first.dx, terr.first.dy).dy);
  for (final t in terr.skip(1)) {
    final q = P(t.dx, t.dy);
    tl.lineTo(q.dx, q.dy);
  }
  canvas.drawPath(
      tl,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF4E4636)
        ..strokeWidth = 1.6);
  // potporni zidovi na rubu zaravni (skok terena)
  for (var i = 0; i + 1 < terr.length; i++) {
    final a = terr[i], b = terr[i + 1];
    if ((a.dy - b.dy).abs() > 0.08) {
      final x = P(a.dx, 0).dx;
      canvas.drawRect(Rect.fromLTRB(x - 2.5, P(0, math.max(a.dy, b.dy)).dy, x + 2.5, P(0, math.min(a.dy, b.dy) - 0.3).dy), Paint()..color = const Color(0xFF7C7871));
    }
  }

  TextPainter tp(String t, double size, {Color color = Pal.ink, FontWeight w = FontWeight.w500}) =>
      TextPainter(text: TextSpan(text: t, style: AppText.narrow(size: size, color: color, weight: w)), textDirection: TextDirection.ltr)
        ..layout();

  // natpisi prostorija
  for (final (s, z, name) in g.labels) {
    final t = tp(name, 10.5, color: const Color(0xFF5B6B7A));
    final at = P(s, z);
    t.paint(canvas, at - Offset(t.width / 2, t.height / 2));
  }

  // kote etaža (lijevo) i visine
  final xl = P(g.sMin, 0).dx - 4;
  void mark(double z, String txt) {
    final y = P(0, z).dy;
    final tri = Path()
      ..moveTo(xl, y)
      ..lineTo(xl - 5, y - 6)
      ..lineTo(xl + 5, y - 6)
      ..close();
    canvas.drawPath(tri, Paint()..color = Pal.ink);
    canvas.drawLine(Offset(xl - 8, y), Offset(xl + 22, y), Paint()..strokeWidth = 0.8);
    final t = tp(txt, 10, w: FontWeight.w600);
    t.paint(canvas, Offset(xl - t.width - 8, y - t.height - 1));
  }

  String kota(double z) => '${z >= 0 ? '+' : '−'}${fmtM(z.abs())}';
  mark(0, '±0,00');
  final seen = <double>{0};
  for (final (z0, h, _) in g.levels) {
    if (!seen.contains(z0)) mark(z0, kota(z0));
    seen.add(z0);
  }
  var ridge = -double.infinity;
  for (final r in g.roofOuter) {
    for (final p in r) {
      ridge = math.max(ridge, p.dy);
    }
  }
  if (ridge.isFinite) {
    final s = g.roofOuter.expand((r) => r).firstWhere((p) => p.dy == ridge).dx;
    final at = P(s, ridge);
    final t = tp('sljeme ${kota(ridge)}', 10, w: FontWeight.w600);
    t.paint(canvas, at + Offset(-t.width / 2, -t.height - 4));
  }
  // svijetle visine etaža (desno)
  final xr = P(g.sMax, 0).dx - 18;
  final dim = Paint()
    ..color = const Color(0xFF5B6B7A)
    ..strokeWidth = 0.8;
  for (final (z0, h, name) in g.levels) {
    final a = P(0, z0), b = P(0, z0 + h);
    canvas.drawLine(Offset(xr, a.dy), Offset(xr, b.dy), dim);
    canvas.drawLine(Offset(xr - 3, a.dy + 3), Offset(xr + 3, a.dy - 3), dim..strokeWidth = 1.2);
    canvas.drawLine(Offset(xr - 3, b.dy + 3), Offset(xr + 3, b.dy - 3), dim);
    dim.strokeWidth = 0.8;
    final t = tp(fmtM(h), 10, color: const Color(0xFF5B6B7A));
    canvas.save();
    canvas.translate(xr + 4, (a.dy + b.dy) / 2 + t.width / 2);
    canvas.rotate(-math.pi / 2);
    t.paint(canvas, Offset.zero);
    canvas.restore();
  }

  // naslov
  final tt = tp(title, 14, w: FontWeight.w700);
  tt.paint(canvas, area.topLeft + const Offset(8, 6));
}

class SectionPainter extends CustomPainter {
  SectionPainter(this.g, {this.title = 'Presjek A–A'});
  final SectionGeometry g;
  final String title;

  @override
  void paint(Canvas canvas, Size size) => paintSection(canvas, Offset.zero & size, g, title: title);

  @override
  bool shouldRepaint(covariant SectionPainter old) => true;
}
