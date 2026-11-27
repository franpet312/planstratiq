
import 'geometry.dart';
import 'plan.dart';
import 'topology.dart';

/// Grijanje i hlađenje: okvirna potrebna snaga po prostoriji i snaga postavljenih uređaja.
/// Specifično toplinsko opterećenje (W/m²) ovisi o izolaciji kuće; brojke su okvirne (za razgovor s
/// projektantom/instalaterom), ne zamjenjuju proračun.

const insulationLevels = <String, (String, double)>{
  'new': ('Nova gradnja / niskoenergetska', 45),
  'good': ('Dobro izolirana (fasada 10+ cm)', 65),
  'average': ('Prosječno (stara fasada)', 90),
  'poor': ('Slabo (bez izolacije)', 120),
};

/// Toplinska snaga uređaja u W (grijanje) i rashladna snaga (hlađenje).
(double, double) devicePower(PlacedItem it) => switch (it.shape) {
      // pločasti radijator tip 22 ~ 1500 W po m² prednje plohe (pri 70/55 °C)
      'radiator' => (it.w * it.h * 1500, 0),
      'towel_radiator' => (it.w * it.h * 800, 0),
      // inverter klima: ogrjevni učin nešto veći od rashladnog
      'ac_indoor' => it.w < 0.85 ? (3200, 2500) : (it.w < 1.0 ? (4000, 3500) : (5800, 5000)),
      'wood_stove' => (it.w < 0.55 ? 6000 : 8000, 0),
      'fireplace' => (5000, 0),
      _ => (0, 0),
    };

const floorHeatingWPerM2 = 70.0;
const floorHeatingPricePerM2 = 45.0;

class RoomClimate {
  RoomClimate(this.room, this.level, this.area, this.heatNeed, this.coolNeed, this.heat, this.cool);
  final Room room;
  final String level;
  final double area;
  final double heatNeed, coolNeed; // W
  final double heat, cool; // W
  bool get heatOk => heat >= heatNeed * 0.95;
  bool get coolOk => cool >= coolNeed * 0.9;
}

/// Klima po prostorijama za cijelu kuću.
List<RoomClimate> roomClimate(Plan plan) {
  final spec = insulationLevels[plan.insulation]?.$2 ?? 65;
  final out = <RoomClimate>[];
  final prev = plan.active;
  for (var li = 0; li < plan.levels.length; li++) {
    plan.active = li;
    for (final r in plan.rooms) {
      final poly = plan.roomPolygon(r);
      if (poly.length < 3) continue;
      final area = roomNetArea(plan, r);
      // kupaonica treba toplije (24 °C)
      final bath = RegExp('kupaon|wc|toalet', caseSensitive: false).hasMatch(r.name);
      final heatNeed = area * spec * (bath ? 1.3 : 1.0);
      final coolNeed = area * 85.0;
      var heat = r.floorHeating ? area * floorHeatingWPerM2 : 0.0, cool = 0.0;
      for (final it in plan.items) {
        if (!pointInPolygon(it.pos, poly)) continue;
        final (h, c) = devicePower(it);
        heat += h;
        cool += c;
      }
      out.add(RoomClimate(r, plan.levels.length > 1 ? plan.level.name : '', area, heatNeed, coolNeed, heat, cool));
    }
  }
  plan.active = prev;
  return out;
}

String fmtKw(double w) => '${(w / 1000).toStringAsFixed(1).replaceAll('.', ',')} kW';


// ------------------------------------------------------------------ godišnja potrošnja

/// Klimatska područja: (naziv, stupanj-dani grijanja K·d, projektna vanjska temperatura °C).
const climates = <String, (String, double, double)>{
  'continental': ('Kontinentalna Hrvatska', 2900, -15),
  'coastal': ('Primorska Hrvatska', 1500, -5),
};

/// Izvori topline: (naziv, cijena isporučene topline €/kWh, emisija kg CO₂/kWh topline).
/// Okvirne cijene energenata 2026. sa stupnjem djelovanja (dizalica topline SCOP 3,5).
const heatSources = <String, (String, double, double)>{
  'gas': ('Plinski kondenzacijski kotao', 0.072, 0.21),
  'heatpump': ('Dizalica topline zrak–voda', 0.045, 0.07),
  'electric': ('Električno (grijalice, podno)', 0.155, 0.24),
  'wood': ('Drva (peć ili kotao)', 0.065, 0.03),
  'pellet': ('Peleti', 0.07, 0.04),
  'oil': ('Lož-ulje', 0.125, 0.30),
};

/// Energetski razredi prema godišnjoj potrebnoj toplini za grijanje po m² (kWh/m²a).
const energyClasses = <(String, double, int)>[
  ('A+', 15, 0xFF1E8C3A),
  ('A', 25, 0xFF3FA535),
  ('B', 50, 0xFF9BC53D),
  ('C', 100, 0xFFE3D33B),
  ('D', 150, 0xFFF2A93B),
  ('E', 200, 0xFFE8742F),
  ('F', 250, 0xFFD9472B),
  ('G', double.infinity, 0xFFB3261E),
];

class EnergyEstimate {
  EnergyEstimate({
    required this.area,
    required this.heatKwh,
    required this.waterKwh,
    required this.coolKwh,
    required this.perM2,
    required this.cls,
    required this.clsColor,
    required this.costs,
    required this.coolCost,
    required this.co2,
  });
  final double area, heatKwh, waterKwh, coolKwh, perM2, coolCost, co2;
  final String cls;
  final int clsColor;

  /// Godišnji trošak grijanja i tople vode po izvoru topline (€).
  final Map<String, double> costs;
}

/// Okvirna godišnja potrošnja: grijanje iz projektnog opterećenja i stupanj-dana (umanjeno za
/// unutarnje i sunčane dobitke te noćno sniženje), topla voda 12,5 kWh/m², hlađenje 500 h punog rada.
EnergyEstimate? energyEstimate(Plan plan) {
  final list = roomClimate(plan);
  if (list.isEmpty) return null;
  final area = list.fold<double>(0, (a, r) => a + r.area);
  if (area < 1) return null;
  final need = list.fold<double>(0, (a, r) => a + r.heatNeed);
  final cool = list.fold<double>(0, (a, r) => a + r.coolNeed);
  final (_, hdd, tDesign) = climates[plan.climate] ?? climates['continental']!;
  final dT = 20 - tDesign;
  final heat = need / dT * hdd * 24 / 1000 * 0.6;
  final water = area * 12.5;
  final coolK = cool / 1000 * (plan.climate == 'coastal' ? 650 : 450) / 4.5; // struja za klimu (SEER 4,5)
  final perM2 = heat / area;
  final c = energyClasses.firstWhere((e) => perM2 <= e.$2);
  return EnergyEstimate(
    area: area,
    heatKwh: heat,
    waterKwh: water,
    coolKwh: coolK,
    perM2: perM2,
    cls: c.$1,
    clsColor: c.$3,
    costs: {for (final e in heatSources.entries) e.key: (heat + water) * e.value.$2},
    coolCost: coolK * 0.155,
    co2: (heat + water) * (heatSources[plan.heatSource]?.$3 ?? 0.2),
  );
}

String fmtKwh(double v) => '${_thousands(v.round())} kWh';

String _thousands(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}
