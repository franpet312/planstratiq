import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'clearance.dart';
import 'plan.dart';

/// Vodovod i odvodnja: vertikale odvoda, priključci sanitarija i okvirne trase.
/// Pravila su uobičajene preporuke: WC (Ø110) do ~1 m od vertikale, ostali odvodi (Ø50)
/// s padom 2 % – na dulju udaljenost treba više mjesta u podu.

const plumbingShapes = {'drain_stack', 'floor_drain', 'water_manifold', 'manhole'};

/// Sanitarni potrošači: (naziv, promjer odvoda u mm, najveća preporučena udaljenost do vertikale u m).
const fixtures = <String, (String, int, double)>{
  'toilet': ('WC', 110, 1.0),
  'shower': ('Tuš', 50, 4.0),
  'bath': ('Kada', 50, 4.0),
  'vanity': ('Umivaonik', 50, 5.0),
  'kitchen': ('Sudoper', 50, 6.0),
  'washer': ('Perilica rublja', 50, 5.0),
  'dishwasher': ('Perilica posuđa', 50, 6.0),
  'floor_drain': ('Podni slivnik', 50, 4.0),
};

const drainPricePerM = 28.0; // cijev, fazoni, ugradnja
const fixturePrice = 70.0; // priključak vode i odvoda po potrošaču

/// Je li objekt sanitarni potrošač (kuhinjski niz samo ako ima sudoper – isto pravilo kao u 3D-u).
bool isFixture(PlacedItem it) {
  if (!fixtures.containsKey(it.shape)) return false;
  if (it.shape == 'kitchen') return it.w >= 1.7 && it.legs != 'plain';
  return true;
}

/// Vertikale odvoda iz svih etaža (vertikala prolazi kroz cijelu kuću).
List<Offset> drainStacks(Plan plan) => [
      for (final l in plan.levels)
        for (final it in l.items)
          if (it.shape == 'drain_stack') it.pos
    ];

class DrainRun {
  DrainRun(this.item, this.from, this.corner, this.to, this.length, this.dn);
  final PlacedItem item;
  final Offset from, corner, to;
  final double length;
  final int dn;
}

/// Mjesto priključka odvoda: stražnja strana objekta (uz zid).
Offset drainPoint(PlacedItem it) {
  final cs = math.cos(it.rotation), sn = math.sin(it.rotation);
  final back = -it.d / 2 + math.min(0.12, it.d / 4);
  return Offset(it.pos.dx - back * sn, it.pos.dy + back * cs);
}

/// Trase odvoda aktivne etaže: svaki potrošač do najbliže vertikale (pod pravim kutom).
List<DrainRun> drainRuns(Plan plan) {
  final stacks = drainStacks(plan);
  if (stacks.isEmpty) return const [];
  final out = <DrainRun>[];
  for (final it in plan.items) {
    final f = fixtures[it.shape];
    if (f == null) continue;
    if (!isFixture(it)) continue;
    final p = drainPoint(it);
    Offset? best;
    var bd = double.infinity;
    for (final s in stacks) {
      final d = (s.dx - p.dx).abs() + (s.dy - p.dy).abs();
      if (d < bd) {
        bd = d;
        best = s;
      }
    }
    final s = best!;
    // lomi se uz dulju stranu najprije (trasa uz zid)
    final corner = (s.dx - p.dx).abs() > (s.dy - p.dy).abs() ? Offset(s.dx, p.dy) : Offset(p.dx, s.dy);
    out.add(DrainRun(it, p, corner, s, bd, f.$2));
  }
  return out;
}

/// Upozorenja za odvodnju aktivne etaže.
List<ClearanceIssue> checkPlumbing(Plan plan) {
  final out = <ClearanceIssue>[];
  final has = plan.items.where(isFixture).toList();
  if (has.isEmpty) return out;
  if (drainStacks(plan).isEmpty) {
    out.add(ClearanceIssue(
        'Na tlocrtu nema vertikale odvoda, a ima sanitarija (${has.length}). Dodaj „Vertikala odvoda” iz kategorije Vodovod i odvodnja '
        'uz zid kupaonice – pokaže se trasa i udaljenost svakog odvoda.',
        has.first.pos,
        serious: false));
    return out;
  }
  for (final r in drainRuns(plan)) {
    final f = fixtures[r.item.shape]!;
    if (r.length <= f.$3) continue;
    final drop = r.length * 0.02 * 100;
    final wc = r.item.shape == 'toilet';
    out.add(ClearanceIssue(
        wc
            ? '${f.$1} je ${r.length.toStringAsFixed(1).replaceAll('.', ',')} m od vertikale odvoda (preporuka do 1 m za cijev Ø110). '
                'Pomakni WC uz vertikalu ili dodaj novu vertikalu${r.length > 3 ? ' – ovako bi trebala pumpa (WC s usitnjivačem)' : ''}.'
            : '${f.$1} je ${r.length.toStringAsFixed(1).replaceAll('.', ',')} m od vertikale: uz pad 2 % odvod se spusti ${drop.round()} cm, '
                'pa pod treba podići ili cijev voditi stropom etaže ispod.',
        r.from,
        itemId: r.item.id,
        serious: wc && r.length > 3));
  }
  return out;
}

/// Okvirna cijena odvodnje i priključaka cijele kuće.
(int, double, double) plumbingTotals(Plan plan) {
  final prev = plan.active;
  var n = 0;
  var len = 0.0;
  for (var i = 0; i < plan.levels.length; i++) {
    plan.active = i;
    for (final r in drainRuns(plan)) {
      n++;
      len += r.length;
    }
  }
  plan.active = prev;
  // vertikale: visina kuće
  final stacks = plan.levels.expand((l) => l.items).where((it) => it.shape == 'drain_stack').length;
  final h = plan.levels.fold<double>(0, (a, l) => a + l.height + 0.25);
  len += stacks * h;
  return (n, len, len * drainPricePerM + n * fixturePrice);
}
