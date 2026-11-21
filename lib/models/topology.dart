import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'geometry.dart';
import 'plan.dart';

class FaceResult {
  FaceResult(this.faces, this.outlines);

  /// Unutarnje zatvorene površine (prostorije) kao liste ID-jeva čvorova.
  final List<List<String>> faces;

  /// Vanjski obrisi (po jedan za svaku povezanu skupinu zidova).
  final List<List<Offset>> outlines;

  double get footprint => outlines.fold(0.0, (a, p) => a + polygonArea(p));
}

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
      }
    }
  }
  return FaceResult(faces, outlines);
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
