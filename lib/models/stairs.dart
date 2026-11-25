import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'plan.dart';

/// Vrste stubišta: ravno, L s podestom, zavojito (spiralno).
const stairShapes = {'stairs', 'stairs_l', 'stairs_spiral'};

/// Širina kraka L-stubišta (isto kao u 3D engineu).
double stairLFlight(double w, double d) {
  final m = math.min(w, d);
  return (m * 0.45).clamp(0.7, math.max(0.7, m - 0.3)).toDouble();
}

/// Obris otvora u stropu iznad stubišta, u lokalnim koordinatama objekta (x širina, y dubina).
List<Offset> stairOutlineLocal(PlacedItem it, {double inset = 0.02}) {
  final hw = it.w / 2 - inset, hd = it.d / 2 - inset;
  switch (it.shape) {
    case 'stairs_l':
      final fw = stairLFlight(it.w, it.d);
      // prvi krak desno (od naprijed prema natrag), drugi straga ulijevo
      return [
        Offset(hw - fw, hd),
        Offset(hw, hd),
        Offset(hw, -hd),
        Offset(-hw, -hd),
        Offset(-hw, -hd + fw),
        Offset(hw - fw, -hd + fw),
      ];
    case 'stairs_spiral':
      final r = math.min(it.w, it.d) / 2 - inset;
      return [for (var i = 0; i < 20; i++) Offset(r * math.cos(i * math.pi / 10), r * math.sin(i * math.pi / 10))];
    default:
      return [Offset(-hw, -hd), Offset(hw, -hd), Offset(hw, hd), Offset(-hw, hd)];
  }
}

/// Isti obris u koordinatama tlocrta.
List<Offset> stairOutline(PlacedItem it, {double inset = 0.02}) {
  final cs = math.cos(it.rotation), sn = math.sin(it.rotation);
  return [
    for (final p in stairOutlineLocal(it, inset: inset)) Offset(it.pos.dx + p.dx * cs - p.dy * sn, it.pos.dy + p.dx * sn + p.dy * cs)
  ];
}
