import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'geometry.dart';
import 'plan.dart';

/// Geometrija krova u Dartu (ista kao u 3D engineu, web/planstratiq3d.js → _buildRoofs), da se zna
/// visina kosog stropa u svakoj točki potkrovlja: upozorenja, opremanje, korisna površina.

const _wt = 0.15; // pola debljine vanjskog zida (obris je po osi zida)

class _Plane {
  const _Plane(this.a, this.b, this.c);
  final double a, b, c;
  double at(double u, double v) => a * u + b * v + c;
}

class _Rect {
  _Rect(this.x0, this.y0, this.x1, this.y1, this.planes);
  final double x0, y0, x1, y1; // proširen do vanjskog lica zida (+prepust)
  final List<_Plane> planes;
  bool contains(double u, double v) => u >= x0 - 1e-3 && u <= x1 + 1e-3 && v >= y0 - 1e-3 && v <= y1 + 1e-3;
  double height(double u, double v) => planes.fold(double.infinity, (m, p) => math.min(m, p.at(u, v)));
}

class _Part {
  _Part(this.ca, this.sa, this.rects, this.shed);
  final double ca, sa;
  final List<_Rect> rects;
  final bool shed;
}

/// Krov nad najvišom etažom. [heightAt] daje visinu krovne plohe iznad vrha zida (tj. iznad baze krova).
class RoofShape {
  RoofShape._(this.parts, this.type);
  final List<_Part> parts;
  final String type;

  /// Visina krovne plohe iznad baze krova u točki tlocrta, ili null ako točka nije ispod krova.
  double? heightAt(Offset p) {
    if (type == 'flat') return null;
    double? best;
    for (final part in parts) {
      final u = p.dx * part.ca + p.dy * part.sa, v = -p.dx * part.sa + p.dy * part.ca;
      for (final r in part.rects) {
        if (!part.shed && !r.contains(u, v)) continue;
        final h = r.height(u, v);
        if (best == null || h > best) best = h;
      }
    }
    return best;
  }

  static RoofShape build(List<List<Offset>> outlines, {required String type, required double pitch, required double overhang, required bool turn}) {
    final t = math.tan(pitch.clamp(5, 60) * math.pi / 180);
    final ov = overhang.clamp(0, 1.5).toDouble();
    final parts = <_Part>[];
    for (final poly in outlines) {
      if (poly.length < 3) continue;
      var ang = 0.0, best = 0.0;
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i], b = poly[(i + 1) % poly.length];
        final l = (b - a).distance;
        if (l > best) {
          best = l;
          ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
        }
      }
      final ca = math.cos(ang), sa = math.sin(ang);
      final lp = [for (final q in poly) Offset(q.dx * ca + q.dy * sa, -q.dx * sa + q.dy * ca)];
      var rectilinear = true;
      for (var i = 0; i < lp.length; i++) {
        final a = lp[i], b = lp[(i + 1) % lp.length];
        final dx = (b.dx - a.dx).abs(), dy = (b.dy - a.dy).abs();
        if (math.min(dx, dy) >= 0.03 * math.max(math.max(dx, dy), 1e-6) + 0.005) rectilinear = false;
      }
      var rects = rectilinear ? _rectCover(lp) : <(double, double, double, double)>[];
      if (rects.isEmpty) {
        var x0 = double.infinity, x1 = -double.infinity, y0 = double.infinity, y1 = -double.infinity;
        for (final q in lp) {
          x0 = math.min(x0, q.dx);
          x1 = math.max(x1, q.dx);
          y0 = math.min(y0, q.dy);
          y1 = math.max(y1, q.dy);
        }
        rects = [(x0, y0, x1, y1)];
      }
      bool inside(double u, double v) => pointInPolygon(Offset(u, v), lp);
      bool exterior((double, double, double, double) r, String side) {
        final (x0, y0, x1, y1) = r;
        for (var k = 0; k <= 8; k++) {
          final f = 0.02 + 0.96 * k / 8;
          final (u, v) = switch (side) {
            'x0' => (x0 - 0.2, y0 + (y1 - y0) * f),
            'x1' => (x1 + 0.2, y0 + (y1 - y0) * f),
            'y0' => (x0 + (x1 - x0) * f, y0 - 0.2),
            _ => (x0 + (x1 - x0) * f, y1 + 0.2),
          };
          if (inside(u, v)) return false;
        }
        return true;
      }

      var ux0 = double.infinity, ux1 = -double.infinity, vy0 = double.infinity, vy1 = -double.infinity;
      for (final (x0, y0, x1, y1) in rects) {
        ux0 = math.min(ux0, x0);
        ux1 = math.max(ux1, x1);
        vy0 = math.min(vy0, y0);
        vy1 = math.max(vy1, y1);
      }
      final shedAlongV = (vy1 - vy0 <= ux1 - ux0) != turn;
      final out = <_Rect>[];
      for (var idx = 0; idx < rects.length; idx++) {
        final r0 = rects[idx];
        final (x0, y0, x1, y1) = (r0.$1 - _wt, r0.$2 - _wt, r0.$3 + _wt, r0.$4 + _wt);
        final e = (
          exterior(r0, 'x0') ? ov : 0.0,
          exterior(r0, 'y0') ? ov : 0.0,
          exterior(r0, 'x1') ? ov : 0.0,
          exterior(r0, 'y1') ? ov : 0.0,
        );
        final longU = (x1 - x0 >= y1 - y0) != turn;
        final lower = idx * 0.004;
        final planes = <_Plane>[];
        if (type == 'shed') {
          planes.add(shedAlongV ? _Plane(0, -t, (vy1 + _wt) * t - lower) : _Plane(-t, 0, (ux1 + _wt) * t - lower));
        } else {
          if (longU || type == 'hip') {
            planes.add(_Plane(0, t, -y0 * t - lower));
            planes.add(_Plane(0, -t, y1 * t - lower));
          }
          if (!longU || type == 'hip') {
            planes.add(_Plane(t, 0, -x0 * t - lower));
            planes.add(_Plane(-t, 0, x1 * t - lower));
          }
        }
        out.add(_Rect(x0 - e.$1, y0 - e.$2, x1 + e.$3, y1 + e.$4, planes));
        if (type == 'shed') break;
      }
      parts.add(_Part(ca, sa, out, type == 'shed'));
    }
    return RoofShape._(parts, type);
  }
}

List<(double, double, double, double)> _rectCover(List<Offset> lp) {
  double snap(double v) => (v * 100).round() / 100;
  final xs = {for (final q in lp) snap(q.dx)}.toList()..sort();
  final ys = {for (final q in lp) snap(q.dy)}.toList()..sort();
  final nx = xs.length - 1, ny = ys.length - 1;
  if (nx < 1 || ny < 1 || nx * ny > 900) return const [];
  final cell = [
    for (var i = 0; i < nx; i++) [for (var j = 0; j < ny; j++) pointInPolygon(Offset((xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2), lp)]
  ];
  final cand = <(int, int, int, int)>[];
  for (var j0 = 0; j0 < ny; j0++) {
    for (var j1 = j0; j1 < ny; j1++) {
      var i = 0;
      bool ok(int ii) {
        for (var j = j0; j <= j1; j++) {
          if (!cell[ii][j]) return false;
        }
        return true;
      }

      while (i < nx) {
        if (!ok(i)) {
          i++;
          continue;
        }
        var k = i;
        while (k + 1 < nx && ok(k + 1)) {
          k++;
        }
        cand.add((i, k, j0, j1));
        i = k + 1;
      }
    }
  }
  bool contains((int, int, int, int) a, (int, int, int, int) b) => a.$1 <= b.$1 && a.$2 >= b.$2 && a.$3 <= b.$3 && a.$4 >= b.$4;
  final maximal = cand.where((c) => !cand.any((d) => d != c && contains(d, c) && !contains(c, d))).toList();
  double area((int, int, int, int) c) => (xs[c.$2 + 1] - xs[c.$1]) * (ys[c.$4 + 1] - ys[c.$3]);
  final covered = [for (var i = 0; i < nx; i++) List.filled(ny, false)];
  final out = <(double, double, double, double)>[];
  for (var guard = 0; guard < 40; guard++) {
    (int, int, int, int)? bestC;
    var bestGain = 0.0;
    for (final c in maximal) {
      var gain = 0.0;
      for (var i = c.$1; i <= c.$2; i++) {
        for (var j = c.$3; j <= c.$4; j++) {
          if (!covered[i][j]) gain += (xs[i + 1] - xs[i]) * (ys[j + 1] - ys[j]);
        }
      }
      if (gain > bestGain + 1e-9 || ((gain - bestGain).abs() < 1e-9 && bestC != null && area(c) > area(bestC))) {
        bestGain = gain;
        bestC = c;
      }
    }
    if (bestC == null || bestGain < 1e-6) break;
    for (var i = bestC.$1; i <= bestC.$2; i++) {
      for (var j = bestC.$3; j <= bestC.$4; j++) {
        covered[i][j] = true;
      }
    }
    out.add((xs[bestC.$1], ys[bestC.$3], xs[bestC.$2 + 1], ys[bestC.$4 + 1]));
  }
  return out;
}

/// Svijetla visina kosog stropa iznad poda potkrovlja (unutarnja obloga je 20 cm ispod pokrova).
double? atticCeilingAt(RoofShape roof, Level attic, Offset p) {
  final h = roof.heightAt(p);
  if (h == null) return null;
  return attic.kneeWall + h - 0.2;
}
