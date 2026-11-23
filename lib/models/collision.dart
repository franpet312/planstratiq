import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'catalog.dart';
import 'geometry.dart';
import 'plan.dart';

/// Sudaranje objekata na tlocrtu: namještaj ne ulazi u zidove ni u drugi namještaj.
///
/// Objekti su orijentirani pravokutnici (OBB). Preklapanje se razrješava
/// najmanjim pomakom (SAT – teorem razdvajajuće osi).

/// Oblici balkona (podloga s ogradom, prislonjena uz vanjski zid).
const balconyShapes = {'balcony', 'balcony_rail', 'balcony_wall'};

/// Oblici na koje se smije staviti namještaj (ne sudaraju se s drugim objektima).
bool isFloorLike(String shape) => floorShapes.contains(shape);

const _tuckable = {'chair', 'stool', 'pouf'};
const _tuckInto = {'table', 'table_round', 'island', 'kitchen', 'vanity'};

class Obb {
  Obb(this.c, this.hw, this.hd, double rot)
      : ux = Offset(math.cos(rot), math.sin(rot)),
        uz = Offset(-math.sin(rot), math.cos(rot));
  Obb.axes(this.c, this.hw, this.hd, this.ux, this.uz);

  final Offset c;
  final double hw, hd;
  final Offset ux, uz;

  double radius(Offset n) => hw * dot(ux, n).abs() + hd * dot(uz, n).abs();
}

/// Tlocrtni otisak objekta za sudaranje (krošnje i suncobrani – samo deblo/stup).
Obb? itemObb(PlacedItem it, [Offset? pos, double? rot]) {
  final p = pos ?? it.pos;
  final r = rot ?? it.rotation;
  switch (it.shape) {
    case 'tree':
    case 'umbrella':
      return Obb(p, 0.15, 0.15, r);
    case 'carport':
      return null;
  }
  return Obb(p, it.w / 2, it.d / 2, r);
}

Obb wallObb(Plan plan, Wall w) {
  final a = plan.nodePos(w.a), b = plan.nodePos(w.b);
  final v = b - a;
  final len = v.distance;
  final ux = len > 1e-9 ? v / len : const Offset(1, 0);
  return Obb.axes((a + b) / 2, len / 2, w.thickness / 2, ux, Offset(-ux.dy, ux.dx));
}

/// Pomak koji odmiče [a] od [b], ili null ako se ne preklapaju (dodir je dopušten).
Offset? separation(Obb a, Obb b, {double eps = 0.004}) {
  var best = double.infinity;
  Offset? mtv;
  for (final n in [a.ux, a.uz, b.ux, b.uz]) {
    final d = dot(b.c - a.c, n);
    final o = a.radius(n) + b.radius(n) - d.abs();
    if (o <= eps) return null;
    if (o < best) {
      best = o;
      mtv = n * (d > 0 ? -(o + 0.002) : (o + 0.002));
    }
  }
  return mtv;
}

bool _pairExempt(PlacedItem a, PlacedItem b) {
  if (isFloorLike(a.shape) || isFloorLike(b.shape)) return true;
  if (a.shape == 'carport' || b.shape == 'carport') return true;
  if (_tuckable.contains(a.shape) && _tuckInto.contains(b.shape)) return true;
  if (_tuckable.contains(b.shape) && _tuckInto.contains(a.shape)) return true;
  return false;
}

/// Prepreke s kojima se objekt sudara na aktivnoj etaži.
List<Obb> obstaclesFor(Plan plan, PlacedItem it) {
  final out = <Obb>[];
  for (final w in plan.walls) {
    out.add(wallObb(plan, w));
  }
  for (final o in plan.items) {
    if (o.id == it.id || _pairExempt(it, o)) continue;
    final ob = itemObb(o);
    if (ob != null) out.add(ob);
  }
  return out;
}

/// Prva pozicija blizu [want] na kojoj se objekt ni s čim ne preklapa, ili null.
Offset? resolveItemPos(Plan plan, PlacedItem it, Offset want, {double? rot}) {
  final obstacles = obstaclesFor(plan, it);
  var p = want;
  for (var iter = 0; iter < 10; iter++) {
    final me = itemObb(it, p, rot);
    if (me == null) return p;
    Offset? push;
    var pushLen = 0.0;
    for (final ob in obstacles) {
      final s = separation(me, ob);
      if (s != null && s.distance > pushLen) {
        push = s;
        pushLen = s.distance;
      }
    }
    if (push == null) return p;
    p += push;
  }
  return null;
}

/// Preklapa li se objekt na zadanom mjestu s nečim.
bool itemOverlaps(Plan plan, PlacedItem it, {Offset? pos, double? rot}) {
  final me = itemObb(it, pos, rot);
  if (me == null) return false;
  return obstaclesFor(plan, it).any((ob) => separation(me, ob) != null);
}
