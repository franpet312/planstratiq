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

/// Terase i nadstrešnice: prislanjaju se uz vanjsku stranu zida (kao balkon).
const terraceShapes = {'terrace', 'terrace_wood', 'terrace_tile'};
const terraceRoofShapes = {'terrace_roof', 'terrace_glass', 'pergola'};

/// Oblici na koje se smije staviti namještaj (ne sudaraju se s drugim objektima).
bool isFloorLike(String shape) => floorShapes.contains(shape);

/// Rasvjeta koja visi sa stropa – ne sudara se s namještajem na podu.
const ceilingShapes = {'chandelier', 'chandelier_ring', 'pendant', 'pendant_row', 'ceiling_light', 'light_point', 'roof_window', 'dormer', 'terrace_roof', 'terrace_glass', 'pergola'};

/// Električne instalacije na zidu (utičnice, prekidači…) i njihova visina od poda (m).
const electricWall = {'socket': 0.3, 'socket_double': 0.3, 'socket_high': 1.1, 'switch': 1.1, 'tv_socket': 0.3, 'lan_socket': 0.3};
const electricShapes = {'socket', 'socket_double', 'socket_high', 'switch', 'tv_socket', 'lan_socket', 'light_point'};

/// Površine na koje se može staviti stolna lampa.
const surfaceShapes = {'table', 'table_round', 'dresser', 'tv_stand', 'kitchen', 'island', 'vanity', 'shelf', 'bench'};

/// „Sloj” objekta: pod, strop, zid (zidna lampa na ~1,8 m) ili na površini (stolna lampa).
String collisionLayer(String shape) {
  if (ceilingShapes.contains(shape)) return 'ceiling';
  if (shape == 'wall_lamp' || shape == 'ac_indoor' || shape == 'boiler') return 'wall';
  if (electricWall.containsKey(shape)) return 'electric';
  if (shape == 'table_lamp') return 'top';
  return 'floor';
}

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
    case 'lamp_arc':
      // luk prolazi iznad sjedala; sudara se samo teška baza straga
      final cs = math.cos(r), sn = math.sin(r);
      final bz = -it.d / 2 + 0.18;
      return Obb(p + Offset(-sn * bz, cs * bz), 0.19, 0.19, r);
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
  final la = collisionLayer(a.shape), lb = collisionLayer(b.shape);
  if (la != lb) {
    // stolna lampa smije na stol/komodu, ali ne u kauč ili krevet
    if (la == 'top') return surfaceShapes.contains(b.shape);
    if (lb == 'top') return surfaceShapes.contains(a.shape);
    return true; // strop/zid/pod se međusobno ne diraju
  }
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

// ---------------------------------------------------------------- udaljenosti do prepreka

/// Udaljenost uz zraku [o] + t·[d] (d jedinični) do ulaska u [b], ili null.
double? rayObb(Offset o, Offset d, Obb b) {
  final rel = o - b.c;
  final lo = Offset(dot(rel, b.ux), dot(rel, b.uz));
  final ld = Offset(dot(d, b.ux), dot(d, b.uz));
  var tmin = -double.infinity, tmax = double.infinity;
  for (final (p, v, h) in [(lo.dx, ld.dx, b.hw), (lo.dy, ld.dy, b.hd)]) {
    if (v.abs() < 1e-12) {
      if (p < -h || p > h) return null;
      continue;
    }
    var t1 = (-h - p) / v, t2 = (h - p) / v;
    if (t1 > t2) (t1, t2) = (t2, t1);
    tmin = math.max(tmin, t1);
    tmax = math.min(tmax, t2);
    if (tmin > tmax) return null;
  }
  if (tmax < 0) return null;
  return tmin >= 0 ? tmin : null; // počinje unutra => nije razmak
}

/// Razmak od jedne strane objekta do najbliže prepreke.
class Gap {
  Gap(this.side, this.from, this.to, this.distance);

  /// 'back' | 'front' | 'left' | 'right' (u odnosu na objekt; straga je strana uz zid)
  final String side;
  final Offset from, to;
  final double distance;
}

/// Razmaci od četiri strane objekta do zidova i drugog namještaja (do [maxDist] m).
List<Gap> itemGaps(Plan plan, PlacedItem it, {double maxDist = 6}) {
  final me = itemObb(it);
  if (me == null) return const [];
  final obstacles = <Obb>[for (final w in plan.walls) wallObb(plan, w)];
  for (final o in plan.items) {
    if (o.id == it.id || isFloorLike(o.shape) || collisionLayer(o.shape) != collisionLayer(it.shape)) continue;
    final ob = itemObb(o);
    if (ob != null) obstacles.add(ob);
  }
  final out = <Gap>[];
  for (final (side, dir, half, across) in [
    ('back', -me.uz, me.hd, me.ux),
    ('front', me.uz, me.hd, me.ux),
    ('left', -me.ux, me.hw, me.uz),
    ('right', me.ux, me.hw, me.uz),
  ]) {
    // tri zrake (sredina i blizu rubova) – najkraća vrijedi
    double? best;
    Offset? bestFrom;
    final span = (identical(across, me.ux) ? me.hw : me.hd) * 0.8;
    for (final k in [0.0, -1.0, 1.0]) {
      final from = me.c + dir * half + across * (span * k);
      for (final ob in obstacles) {
        final t = rayObb(from, dir, ob);
        if (t != null && t <= maxDist && (best == null || t < best - 1e-6)) {
          best = t;
          bestFrom = from;
        }
      }
    }
    if (best != null) out.add(Gap(side, bestFrom!, bestFrom + dir * best, best));
  }
  return out;
}
