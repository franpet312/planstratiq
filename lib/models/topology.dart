import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'geometry.dart';
import 'plan.dart';

class FaceResult {
  FaceResult(this.faces, this.outlines, this.outlineIds);

  /// Unutarnje zatvorene površine (prostorije) kao liste ID-jeva čvorova.
  final List<List<String>> faces;

  /// Vanjski obrisi (po jedan za svaku povezanu skupinu zidova).
  final List<List<Offset>> outlines;

  /// ID-jevi čvorova vanjskih obrisa (isti poredak kao [outlines]).
  final List<List<String>> outlineIds;
}

/// Površina poligona pomaknutog za debljinu zidova: prema unutra (neto) ili van (bruto).
/// [half] je pola debljine zida za svaki brid (poly[i] → poly[i+1]).
double offsetArea(List<Offset> poly, List<double> half, {required bool inward}) {
  final n = poly.length;
  if (n < 3) return 0;
  final a = signedArea(poly);
  final sgn = a >= 0 ? 1.0 : -1.0;
  var sumLh = 0.0, corr = 0.0;
  for (var i = 0; i < n; i++) {
    final p0 = poly[i], p1 = poly[(i + 1) % n], p2 = poly[(i + 2) % n];
    sumLh += (p1 - p0).distance * half[i];
    final c = cross(p1 - p0, p2 - p1) * sgn;
    final h = half[i] * half[(i + 1) % n];
    if (c > 1e-9) {
      corr += h;
    } else if (c < -1e-9) {
      corr -= h;
    }
  }
  final r = inward ? a.abs() - sumLh + corr : a.abs() + sumLh + corr;
  return r < 0 ? 0 : r;
}

/// Pola debljine zida za svaki brid niza čvorova.
List<double> edgeHalfThickness(Plan plan, List<String> ids) {
  final byKey = <String, Wall>{};
  for (final w in plan.walls) {
    byKey['${w.a}|${w.b}'] = w;
    byKey['${w.b}|${w.a}'] = w;
  }
  return [
    for (var i = 0; i < ids.length; i++) (byKey['${ids[i]}|${ids[(i + 1) % ids.length]}']?.thickness ?? 0) / 2,
  ];
}

/// Neto (svijetla) površina prostorije – unutar lica zidova.
double roomNetArea(Plan plan, Room r) =>
    offsetArea(plan.roomPolygon(r), edgeHalfThickness(plan, r.nodeIds), inward: true);

/// Pronalazi zatvorene prostorije u planarnom grafu zidova.
///
/// Za svaki usmjereni brid (u→v) u čvoru v uzima se sljedeći susjed iza u
/// (sortirano po kutu). Tako se obilaze lica grafa; omeđena lica dobiju
/// negativnu površinu, a vanjski obris pozitivnu. Prostorije se vraćaju
/// preokrenute, s pozitivnom orijentacijom.
FaceResult detectFaces(Plan plan) {
  final adj = <String, List<String>>{};
  for (final w in plan.walls) {
    if (w.a == w.b) continue;
    if (!plan.nodes.containsKey(w.a) || !plan.nodes.containsKey(w.b)) continue;
    adj.putIfAbsent(w.a, () => []).add(w.b);
    adj.putIfAbsent(w.b, () => []).add(w.a);
  }
  double ang(String from, String to) {
    final d = plan.nodePos(to) - plan.nodePos(from);
    return math.atan2(d.dy, d.dx);
  }

  for (final e in adj.entries) {
    final list = e.value.toSet().toList()..sort((x, y) => ang(e.key, x).compareTo(ang(e.key, y)));
    adj[e.key] = list;
  }

  final visited = <String>{};
  final faces = <List<String>>[];
  final outlines = <List<Offset>>[];
  final outlineIds = <List<String>>[];

  for (final u0 in adj.keys) {
    for (final v0 in adj[u0]!) {
      if (visited.contains('$u0|$v0')) continue;
      final cycle = <String>[];
      var u = u0, v = v0;
      var guard = 0;
      while (!visited.contains('$u|$v') && guard++ < 10000) {
        visited.add('$u|$v');
        cycle.add(u);
        final nb = adj[v]!;
        final i = nb.indexOf(u);
        final next = nb[(i + 1) % nb.length];
        u = v;
        v = next;
      }
      final clean = _removeSpikes(cycle);
      if (clean.length < 3) continue;
      final poly = [for (final id in clean) plan.nodePos(id)];
      final a = signedArea(poly);
      if (a < -0.25) {
        // omeđeno lice: spremi s pozitivnom orijentacijom (unutrašnjost lijevo od smjera obilaska)
        faces.add(clean.reversed.toList());
      } else if (a > 0.25) {
        outlines.add(poly);
        outlineIds.add(clean);
      }
    }
  }
  return FaceResult(faces, outlines, outlineIds);
}

/// Uklanja "šiljke" (slobodni zid unutar prostorije: ...a, b, a...).
List<String> _removeSpikes(List<String> c) {
  final l = List<String>.from(c);
  var changed = true;
  while (changed && l.length >= 3) {
    changed = false;
    for (var i = 0; i < l.length; i++) {
      final prev = l[(i - 1 + l.length) % l.length];
      final next = l[(i + 1) % l.length];
      if (prev == next) {
        // ukloni l[i] i jedan od duplikata
        final j = (i + 1) % l.length;
        if (j > i) {
          l.removeAt(j);
          l.removeAt(i);
        } else {
          l.removeAt(i);
          l.removeAt(j);
        }
        changed = true;
        break;
      }
    }
  }
  // ukloni uzastopne duplikate
  final out = <String>[];
  for (final id in l) {
    if (out.isEmpty || out.last != id) out.add(id);
  }
  if (out.length > 1 && out.first == out.last) out.removeLast();
  return out;
}
