import 'dart:math' as math;
import 'dart:ui' show Offset;

double dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

/// Parametar t projekcije točke p na pravac a→b (0 = a, 1 = b), nije ograničen.
double projectT(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = dot(ab, ab);
  if (l2 == 0) return 0;
  return dot(p - a, ab) / l2;
}

double distToSegment(Offset p, Offset a, Offset b) {
  final t = projectT(p, a, b).clamp(0.0, 1.0);
  return (p - (a + (b - a) * t)).distance;
}

Offset rotate(Offset v, double r) {
  final c = math.cos(r), s = math.sin(r);
  return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
}

bool pointInPolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

double polygonArea(List<Offset> poly) {
  var s = 0.0;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    s += poly[j].dx * poly[i].dy - poly[i].dx * poly[j].dy;
  }
  return s.abs() / 2;
}

Offset centroid(List<Offset> poly) {
  if (poly.isEmpty) return Offset.zero;
  var x = 0.0, y = 0.0;
  for (final p in poly) {
    x += p.dx;
    y += p.dy;
  }
  return Offset(x / poly.length, y / poly.length);
}

double roundTo(double v, double step) => (v / step).roundToDouble() * step;
