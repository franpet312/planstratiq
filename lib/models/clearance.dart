import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'collision.dart';
import 'plan.dart';

/// Provjera prolaza i otvaranja: vrata koja se ne mogu otvoriti, ladice i ormari bez mjesta,
/// krevet bez pristupa i preuski prolazi. Mjere su uobičajene preporuke za opremanje stana.
class ClearanceIssue {
  ClearanceIssue(this.message, this.at, {this.zone, this.itemId, this.serious = true});
  final String message;
  final Offset at;

  /// Područje koje mora biti slobodno (4 točke) – crta se na tlocrtu.
  final List<Offset>? zone;
  final String? itemId;

  /// Ozbiljno (nešto se ne može koristiti) ili samo preporuka.
  final bool serious;
}

/// Koliko mjesta ispred objekta treba za otvaranje (m) i čega.
(double, String)? frontNeed(String shape) => switch (shape) {
      'wardrobe' => (0.6, 'vrata ormara'),
      'dresser' => (0.5, 'ladice'),
      'fridge' => (0.6, 'vrata hladnjaka'),
      'dishwasher' => (0.6, 'vrata perilice posuđa'),
      'stove' => (0.6, 'vrata pećnice'),
      'washer' => (0.6, 'vrata perilice'),
      'tall' => (0.5, 'vrata ormarića'),
      'vitrine' => (0.45, 'vrata vitrine'),
      'kitchen' => (0.9, 'kuhinjske elemente'),
      'shower' => (0.6, 'tuš'),
      'toilet' => (0.55, 'WC'),
      'vanity' => (0.6, 'umivaonik'),
      _ => null,
    };

const _blocking = {
  'bed', 'bunk', 'crib', 'sofa', 'sofa_corner', 'table', 'table_round', 'island', 'wardrobe', 'dresser', 'shelf', 'vitrine',
  'tv_stand', 'kitchen', 'tall', 'fridge', 'stove', 'dishwasher', 'washer', 'bath', 'shower', 'toilet', 'vanity', 'bench',
  'fireplace', 'chair', 'stool', 'pouf', 'plant', 'lamp', 'stairs', 'stairs_l', 'stairs_spiral', 'tv', 'box',
};

Obb _rect(Offset c, Offset ux, Offset uz, double hw, double hd) => Obb.axes(c, hw, hd, ux, uz);

List<Offset> _corners(Obb b) => [
      b.c - b.ux * b.hw - b.uz * b.hd,
      b.c + b.ux * b.hw - b.uz * b.hd,
      b.c + b.ux * b.hw + b.uz * b.hd,
      b.c - b.ux * b.hw + b.uz * b.hd,
    ];

String _name(PlacedItem it) {
  final n = it.name.split(',').first.trim();
  return n.isEmpty ? 'Objekt' : n;
}

List<ClearanceIssue> checkClearances(Plan plan, {double? Function(Offset)? ceilingAt}) {
  final issues = <ClearanceIssue>[];
  // 0) potkrovlje: objekt viši od kosog stropa iznad sebe
  if (ceilingAt != null) {
    for (final it in plan.items) {
      final layer = collisionLayer(it.shape);
      if (layer != 'floor' || isFloorLike(it.shape) || it.h < 0.3) continue;
      final ob = itemObb(it);
      if (ob == null) continue;
      double? low;
      Offset? at;
      for (final p in [..._corners(ob), ob.c]) {
        final h = ceilingAt(p);
        if (h != null && (low == null || h < low)) {
          low = h;
          at = p;
        }
      }
      if (low != null && it.h > low + 0.01) {
        issues.add(ClearanceIssue(
            '${_name(it)} je viši od kosog stropa: strop je tu ${(low * 100).round()} cm, a objekt ${(it.h * 100).round()} cm. Pomakni ga prema sljemenu ili odaberi niži.',
            at!,
            zone: _corners(ob),
            itemId: it.id));
      }
    }
  }
  final items = [
    for (final it in plan.items)
      if (_blocking.contains(it.shape) && collisionLayer(it.shape) == 'floor') (it, itemObb(it)!)
  ];
  final walls = [for (final w in plan.walls) (w, wallObb(plan, w))];

  // 1) vrata: ispred i iza vrata mora biti slobodno barem širina krila (zakretanje)
  for (final o in plan.openings) {
    if (o.type == OpeningType.window || o.sill > 0.3) continue;
    final w = plan.wallById(o.wallId);
    if (w == null) continue;
    final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
    final len = (b - a).distance;
    if (len < 1e-6) continue;
    final ux = (b - a) / len, n = Offset(-ux.dy, ux.dx);
    final c = a + (b - a) * o.t;
    final depth = o.type == OpeningType.door ? math.min(o.width, 0.9) : 0.6;
    for (final side in [1.0, -1.0]) {
      final zc = c + n * side * (w.thickness / 2 + depth / 2);
      final zone = _rect(zc, ux, n, o.width / 2 - 0.02, depth / 2 - 0.02);
      for (final (it, ob) in items) {
        if (separation(zone, ob, eps: 0.01) != null) {
          final what = o.type == OpeningType.door ? 'vrata se ne mogu otvoriti' : 'prolaz je zatvoren';
          issues.add(ClearanceIssue('${_name(it)} stoji ispred otvora – $what.', zc, zone: _corners(zone), itemId: it.id));
          break;
        }
      }
    }
  }

  // 2) ladice, ormari, uređaji: mjesto ispred za otvaranje
  for (final (it, ob) in items) {
    final need = frontNeed(it.shape);
    if (need == null) continue;
    final (depth, what) = need;
    final zc = ob.c + ob.uz * (ob.hd + depth / 2 + 0.01);
    final zone = _rect(zc, ob.ux, ob.uz, ob.hw - 0.03, depth / 2 - 0.01);
    String? blocker;
    for (final (o2, ob2) in items) {
      if (o2.id == it.id) continue;
      if ({'chair', 'stool', 'pouf'}.contains(o2.shape)) continue; // stolica se odmakne
      if (separation(zone, ob2, eps: 0.01) != null) {
        blocker = _name(o2);
        break;
      }
    }
    if (blocker == null) {
      for (final (_, wb) in walls) {
        if (separation(zone, wb, eps: 0.01) != null) {
          blocker = 'zid';
          break;
        }
      }
    }
    if (blocker != null) {
      issues.add(ClearanceIssue('${_name(it)}: $what se ne mogu otvoriti – smeta $blocker (treba ${(depth * 100).round()} cm ispred).', zc,
          zone: _corners(zone), itemId: it.id));
    }
  }

  // 3) krevet: s barem jedne duže strane treba 60 cm za ustajanje i namještanje
  for (final (it, _) in items) {
    if (it.shape != 'bed') continue;
    final gaps = {for (final g in itemGaps(plan, it, maxDist: 3)) g.side: g.distance};
    final l = gaps['left'] ?? 3.0, r = gaps['right'] ?? 3.0;
    if (math.max(l, r) < 0.55) {
      issues.add(ClearanceIssue(
          '${_name(it)}: s obje strane manje od 60 cm (lijevo ${(l * 100).round()}, desno ${(r * 100).round()} cm) – teško se ustaje i namješta.',
          it.pos,
          itemId: it.id));
    }
  }

  // 4) preuski prolazi između većeg namještaja i zida/namještaja (preporuka ≥ 70 cm)
  final seen = <Offset>[];
  for (final (it, ob) in items) {
    if (it.w * it.d < 0.45 || {'chair', 'stool', 'pouf', 'plant', 'lamp', 'tv'}.contains(it.shape)) continue;
    for (final g in itemGaps(plan, it, maxDist: 0.7)) {
      if (g.side == 'back' || g.distance < 0.22 || g.distance >= 0.6) continue;
      final mid = (g.from + g.to) / 2;
      if (seen.any((p) => (p - mid).distance < 0.6)) continue;
      // samo ako je s druge strane veliki objekt ili zid (ne stolica)
      seen.add(mid);
      issues.add(ClearanceIssue('Uzak prolaz kod: ${_name(it)} – ${(g.distance * 100).round()} cm (za prolaz treba barem 60–70 cm).', mid,
          itemId: it.id, serious: false));
    }
  }
  return issues;
}

