
import 'geometry.dart';
import 'plan.dart';

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

