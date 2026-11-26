import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'geometry.dart';
import 'plan.dart';

/// Unutarnji rub prostorije uz jedan zid: od kuta do kuta, s normalom prema unutra
/// i slobodnim dijelovima (bez vrata; prozori posebno označeni).
class RoomSide {
  RoomSide(this.wall, this.a, this.b, this.inward, this.thickness);
  final Wall wall;

  /// Točke na unutarnjem licu zida (kutovi prostorije).
  final Offset a, b;
  final Offset inward;
  final double thickness;
  double get length => (b - a).distance;
  Offset get dir => (b - a) / math.max(1e-9, length);

  /// Prekidi duž stranice [od, do] (m od a): vrata/prolazi (pod) i prozori (iznad radne ploče).
  final doors = <(double, double)>[];
  final windows = <(double, double, double)>[]; // od, do, visina parapeta

  /// Najdulji dio bez vrata.
  (double, double) longestFree({double minLen = 0}) {
    final cuts = [...doors]..sort((x, y) => x.$1.compareTo(y.$1));
    var best = (0.0, 0.0), cur = 0.0;
    for (final (s, e) in cuts) {
      if (s - cur > best.$2 - best.$1) best = (cur, s);
      cur = math.max(cur, e);
    }
    if (length - cur > best.$2 - best.$1) best = (cur, length);
    return best;
  }

  Offset at(double t, double offset) => a + dir * t + inward * offset;
}

/// Stranice prostorije redom (kao u poligonu prostorije).
List<RoomSide> roomSides(Plan plan, Room r) {
  final poly = plan.roomPolygon(r);
  final ids = r.nodeIds;
  final n = ids.length;
  final walls = <Wall?>[];
  for (var i = 0; i < n; i++) {
    final a = ids[i], b = ids[(i + 1) % n];
    walls.add(plan.walls.where((w) => (w.a == a && w.b == b) || (w.a == b && w.b == a)).firstOrNull);
  }
  // unutarnje lice: pomak ruba za pola debljine prema unutra; kutovi = sjecišta susjednih pomaknutih pravaca
  final lines = <(Offset, Offset, Offset)>[]; // točka, smjer, normal
  for (var i = 0; i < n; i++) {
    final p = poly[i], q = poly[(i + 1) % n];
    final d = (q - p) / math.max(1e-9, (q - p).distance);
    var nrm = Offset(-d.dy, d.dx);
    final mid = (p + q) / 2;
    if (!pointInPolygon(mid + nrm * 0.05, poly)) nrm = -nrm;
    final t = (walls[i]?.thickness ?? 0) / 2;
    lines.add((p + nrm * t, d, nrm));
  }
  Offset meet(int i, int j) {
    final (p1, d1, _) = lines[i];
    final (p2, d2, _) = lines[j];
    final den = d1.dx * d2.dy - d1.dy * d2.dx;
    if (den.abs() < 1e-9) return p2;
    final t = ((p2.dx - p1.dx) * d2.dy - (p2.dy - p1.dy) * d2.dx) / den;
    return p1 + d1 * t;
  }

  final out = <RoomSide>[];
  for (var i = 0; i < n; i++) {
    final w = walls[i];
    if (w == null) continue;
    final a = meet((i - 1 + n) % n, i), b = meet(i, (i + 1) % n);
    final side = RoomSide(w, a, b, lines[i].$3, w.thickness);
    final wa = plan.nodePos(w.a), wb = plan.nodePos(w.b);
    final wl = (wb - wa).distance;
    for (final o in plan.openings.where((o) => o.wallId == w.id)) {
      final c = wa + (wb - wa) * o.t;
      final tc = dot(c - side.a, side.dir);
      final s0 = tc - o.width / 2, s1 = tc + o.width / 2;
      if (o.type == OpeningType.window && o.sill >= 0.85) {
        side.windows.add((s0 - 0.05, s1 + 0.05, o.sill));
      } else {
        side.doors.add((s0 - 0.1, s1 + 0.1));
      }
    }
    if (wl > 0) out.add(side);
  }
  return out;
}
