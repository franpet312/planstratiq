import 'dart:math' as math;
import 'dart:ui' show Offset;

double dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
double cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

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

Offset closestOnSegment(Offset p, Offset a, Offset b) {
  final t = projectT(p, a, b).clamp(0.0, 1.0);
  return a + (b - a) * t;
}

/// Sjecište dužina a-b i c-d. Vraća (t, u) parametre ili null.
(double, double)? segmentIntersection(Offset a, Offset b, Offset c, Offset d) {
  final r = b - a, s = d - c;
  final den = cross(r, s);
  if (den.abs() < 1e-12) return null;
  final t = cross(c - a, s) / den;
  final u = cross(c - a, r) / den;
  if (t < 0 || t > 1 || u < 0 || u > 1) return null;
  return (t, u);
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

/// Površina s predznakom (u y-dolje koordinatama unutarnje prostorije su pozitivne).
double signedArea(List<Offset> poly) {
  var s = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i], b = poly[(i + 1) % poly.length];
    s += a.dx * b.dy - b.dx * a.dy;
  }
  return s / 2;
}

double polygonArea(List<Offset> poly) => signedArea(poly).abs();

double polygonPerimeter(List<Offset> poly) {
  var s = 0.0;
  for (var i = 0; i < poly.length; i++) {
    s += (poly[(i + 1) % poly.length] - poly[i]).distance;
  }
  return s;
}

Offset centroid(List<Offset> poly) {
  if (poly.isEmpty) return Offset.zero;
  final a = signedArea(poly);
  if (a.abs() < 1e-9) {
    var x = 0.0, y = 0.0;
    for (final p in poly) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / poly.length, y / poly.length);
  }
  var cx = 0.0, cy = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final p = poly[i], q = poly[(i + 1) % poly.length];
    final f = p.dx * q.dy - q.dx * p.dy;
    cx += (p.dx + q.dx) * f;
    cy += (p.dy + q.dy) * f;
  }
  return Offset(cx / (6 * a), cy / (6 * a));
}

/// Točka unutar poligona dobra za natpis (centroid ako je unutra, inače
/// najbolja točka na vodoravnoj liniji kroz sredinu).
Offset labelPoint(List<Offset> poly) {
  final c = centroid(poly);
  if (pointInPolygon(c, poly)) return c;
  final xs = <double>[];
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i], b = poly[(i + 1) % poly.length];
    if ((a.dy > c.dy) != (b.dy > c.dy)) {
      xs.add(a.dx + (c.dy - a.dy) / (b.dy - a.dy) * (b.dx - a.dx));
    }
  }
  xs.sort();
  var best = c, bestW = -1.0;
  for (var i = 0; i + 1 < xs.length; i += 2) {
    final w = xs[i + 1] - xs[i];
    if (w > bestW) {
      bestW = w;
      best = Offset((xs[i] + xs[i + 1]) / 2, c.dy);
    }
  }
  return best;
}

double roundTo(double v, double step) => (v / step).roundToDouble() * step;

String fmtM(double v, [int decimals = 2]) => v.toStringAsFixed(decimals).replaceAll('.', ',');
String fmtM2(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} m²';
String fmtEur(double v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '$b €';
}
