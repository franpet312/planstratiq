import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'clearance.dart';
import 'collision.dart';
import 'geometry.dart';
import 'plan.dart';
import 'roof.dart';
import 'stairs.dart';

/// Provjera stubišta: visina iznad glave (ploča i kosi strop iznad), objekti i zidovi
/// na katu nad otvorom te udobnost (pravilo koraka 2h + b ≈ 63 cm).

const minHeadroom = 2.0;
const _spiralSweep = math.pi * 1.5;

/// Napredak uz stubište 0 (dno) … 1 (vrh) za lokalnu točku, ili null ako točka nije na stubama.
/// Isto kao stairProgress u 3D engineu.
double? stairProgressLocal(PlacedItem it, double lx, double lz) {
  final w = it.w, d = it.d;
  if (lx.abs() > w / 2 || lz.abs() > d / 2) return null;
  if (it.shape == 'stairs_l') {
    final fw = stairLFlight(w, d);
    final l1 = math.max(0.3, d - fw), l2 = math.max(0.3, w - fw);
    final r1 = l1 / (l1 + l2);
    if (lx >= w / 2 - fw) {
      if (lz > -d / 2 + fw) return r1 * (d / 2 - lz) / l1;
      return r1;
    }
    if (lz <= -d / 2 + fw) return r1 + (1 - r1) * (w / 2 - fw - lx) / l2;
    return null;
  }
  if (it.shape == 'stairs_spiral') {
    final r = math.min(w, d) / 2;
    if (math.sqrt(lx * lx + lz * lz) > r || math.sqrt(lx * lx + lz * lz) < 0.12) return null;
    var a = math.atan2(lx, lz);
    if (a < 0) a += math.pi * 2;
    if (a > _spiralSweep) return null;
    return a / _spiralSweep;
  }
  return (d / 2 - lz) / d;
}

/// Duljina hodne linije stubišta (m).
double stairWalkLength(PlacedItem it) {
  switch (it.shape) {
    case 'stairs_l':
      final fw = stairLFlight(it.w, it.d);
      return math.max(0.3, it.d - fw) + math.max(0.3, it.w - fw);
    case 'stairs_spiral':
      return math.min(it.w, it.d) / 2 * 0.6 * _spiralSweep;
    default:
      return it.d;
  }
}

/// Etaža neposredno iznad [lvl] (po koti poda), ili null.
Level? levelAbove(Plan plan, Level lvl) {
  Level? best;
  for (final l in plan.levels) {
    if (l.elevation > lvl.elevation + 0.5 && (best == null || l.elevation < best.elevation)) best = l;
  }
  return best;
}

bool _segHitsPoly(Offset a, Offset b, List<Offset> poly) {
  if (pointInPolygon(a, poly) || pointInPolygon(b, poly)) return true;
  for (var i = 0; i < poly.length; i++) {
    final c = poly[i], d = poly[(i + 1) % poly.length];
    if (_segX(a, b, c, d)) return true;
  }
  return false;
}

bool _segX(Offset p1, Offset p2, Offset p3, Offset p4) {
  double o(Offset a, Offset b, Offset c) => (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  final d1 = o(p3, p4, p1), d2 = o(p3, p4, p2), d3 = o(p1, p2, p3), d4 = o(p1, p2, p4);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

/// Problemi sa stubištima aktivne etaže.
List<ClearanceIssue> checkStairs(Plan plan, {RoofShape? roof}) {
  final out = <ClearanceIssue>[];
  final lvl = plan.level;
  final top = plan.levels.isNotEmpty && identical(plan.levels.last, lvl);
  for (final it in lvl.items) {
    if (!stairShapes.contains(it.shape)) continue;
    final name = it.name.split(',').first.trim();
    final up = levelAbove(plan, lvl);
    if (up == null) {
      out.add(ClearanceIssue('$name ne vodi nikamo: iznad ove etaže nema kata. Dodaj kat ili potkrovlje u izborniku etaža.', it.pos,
          itemId: it.id, serious: false));
      continue;
    }
    final rise = up.elevation - lvl.elevation;
    final cs = math.cos(it.rotation), sn = math.sin(it.rotation);
    Offset world(double lx, double lz) => Offset(it.pos.dx + lx * cs - lz * sn, it.pos.dy + lx * sn + lz * cs);
    final hole = stairOutline(it);

    // objekti na katu koji stoje nad otvorom
    for (final o in up.items) {
      if (stairShapes.contains(o.shape) || ceilingShapes.contains(o.shape) || electricShapes.contains(o.shape)) continue;
      final b = itemObb(o);
      if (b == null) continue;
      final corners = [
        b.c - b.ux * b.hw - b.uz * b.hd,
        b.c + b.ux * b.hw - b.uz * b.hd,
        b.c + b.ux * b.hw + b.uz * b.hd,
        b.c - b.ux * b.hw + b.uz * b.hd,
      ];
      var hit = pointInPolygon(b.c, hole);
      for (var i = 0; i < 4 && !hit; i++) {
        hit = _segHitsPoly(corners[i], corners[(i + 1) % 4], hole);
      }
      if (hit) {
        out.add(ClearanceIssue('${o.name.split(',').first.trim()} na etaži „${up.name}” stoji nad otvorom stubišta – pao bi u njega.', b.c,
            itemId: it.id));
      }
    }
    // zidovi kata preko otvora
    for (final w in up.walls) {
      final a = up.nodes[w.a]?.pos, b = up.nodes[w.b]?.pos;
      if (a == null || b == null) continue;
      if (_segHitsPoly(a, b, stairOutline(it, inset: 0.12))) {
        out.add(ClearanceIssue('Zid na etaži „${up.name}” prolazi preko otvora stubišta.', (a + b) / 2, itemId: it.id));
      }
    }

    // visina iznad glave: od stepenice do ploče/kosog stropa kata (otvor je točno obris stubišta,
    // pa je iznad stuba strop etaže iznad – kod potkrovlja kosi strop)
    if (up.attic && top == false && roof != null && identical(plan.levels.last, up)) {
      var low = double.infinity;
      Offset? at;
      for (var lx = -it.w / 2 + 0.05; lx < it.w / 2; lx += 0.1) {
        for (var lz = -it.d / 2 + 0.05; lz < it.d / 2; lz += 0.1) {
          final k = stairProgressLocal(it, lx, lz);
          if (k == null) continue;
          final p = world(lx, lz);
          final c = atticCeilingAt(roof, up, p);
          if (c == null) continue;
          final h = rise + c - k * rise;
          if (h < low) {
            low = h;
            at = p;
          }
        }
      }
      if (at != null && low < minHeadroom) {
        out.add(ClearanceIssue(
            'Iznad ${name.toLowerCase()} kosi strop potkrovlja je samo ${(low * 100).round()} cm iznad stepenice (treba bar 200 cm). '
            'Okreni stubište da izlazi prema sljemenu ili ga pomakni.',
            at,
            itemId: it.id,
            serious: low < 1.85));
      }
    }

    // udobnost: broj stepenica i pravilo koraka
    final n = math.max(2, (rise / 0.18).ceil());
    final h = rise / n;
    final g = stairWalkLength(it) / (n - 1);
    final step = 2 * h + g;
    if (it.shape == 'stairs_spiral') {
      // zavojito je po naravi strmije; upozori samo kad je gazište na hodnoj liniji premalo
      if (g < 0.15) {
        out.add(ClearanceIssue('$name je preusko za $n stepenica: gazište na hodnoj liniji samo ${(g * 100).round()} cm. Odaberi veći promjer.',
            it.pos,
            itemId: it.id,
            serious: false));
      }
    } else if (step < 0.57 || h > 0.20) {
      out.add(ClearanceIssue(
          '$name je strmo: $n stepenica po ${(h * 100).toStringAsFixed(1)} cm, gazište ${(g * 100).round()} cm '
          '(2h + b = ${(step * 100).round()} cm, ugodno 60–65 cm). Produlji stubište ili odaberi L/zavojito.',
          it.pos,
          itemId: it.id,
          serious: step < 0.52));
    } else if (step > 0.70) {
      out.add(ClearanceIssue(
          '$name je preblago (2h + b = ${(step * 100).round()} cm): gazišta po ${(g * 100).round()} cm, korak se ne poklapa. Skrati stubište.',
          it.pos,
          itemId: it.id,
          serious: false));
    }
  }
  return out;
}
