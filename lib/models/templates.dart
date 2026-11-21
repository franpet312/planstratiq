import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../state/plan_controller.dart';
import 'catalog.dart';
import 'plan.dart';

class PlanTemplate {
  const PlanTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.build,
  });

  final String id;
  final String name;
  final String description;
  final void Function(PlanController c) build;
}

const templates = <PlanTemplate>[
  PlanTemplate(
    id: 'house',
    name: 'Obiteljska kuća',
    description: 'Prizemnica 12 × 10 m, tri spavaće sobe i vrt s bazenom',
    build: buildHouse,
  ),
  PlanTemplate(
    id: 'apartment',
    name: 'Stan s dvije sobe',
    description: 'Oko 70 m², dnevni boravak s kuhinjom i balkonom',
    build: buildApartment,
  ),
];

PlanTemplate? templateById(String id) {
  for (final t in templates) {
    if (t.id == id) return t;
  }
  return null;
}

void _put(PlanController c, String id, double x, double y, [double rotDeg = 0]) {
  final item = catalogById(id);
  if (item != null) c.placeItem(item, Offset(x, y), rotation: rotDeg * math.pi / 180);
}

void _opening(PlanController c, double x, double y, OpeningType t, {double? width, double? height, double? sill}) {
  final o = c.addOpeningNear(Offset(x, y), t, tol: 0.05);
  if (o == null) return;
  final w = c.plan.wallById(o.wallId)!;
  final len = c.plan.wallLength(w);
  if (width != null) o.width = width;
  if (height != null) o.height = height;
  if (sill != null) o.sill = sill;
  o.t = PlanController.clampOpeningT(len, o.width, o.t);
}

/// Vanjski zidovi (na rubu pravokutnika) dobivaju veću debljinu.
void _outerWalls(PlanController c, Rect r, double thickness) {
  bool on(Offset p, double v, bool x) => ((x ? p.dx : p.dy) - v).abs() < 1e-6;
  for (final w in c.plan.walls) {
    final a = c.plan.nodePos(w.a), b = c.plan.nodePos(w.b);
    final outer = (on(a, r.left, true) && on(b, r.left, true)) ||
        (on(a, r.right, true) && on(b, r.right, true)) ||
        (on(a, r.top, false) && on(b, r.top, false)) ||
        (on(a, r.bottom, false) && on(b, r.bottom, false));
    w.thickness = outer ? thickness : 0.12;
  }
}

void buildHouse(PlanController c) {
  c.plan.wallHeight = 2.7;
  void room(double l, double t, double r, double b, String name, String floor) =>
      c.addRoomRect(Rect.fromLTRB(l, t, r, b), name: name, floor: floor);
  room(0, 0, 7, 5, 'Dnevni boravak', 'parket_hrast');
  room(7, 0, 12, 5, 'Kuhinja i blagovaonica', 'plocice_sive');
  room(0, 5, 12, 6.4, 'Hodnik', 'plocice_sive');
  room(0, 6.4, 3.6, 10, 'Dječja soba', 'laminat_svijetli');
  room(3.6, 6.4, 6, 10, 'Kupaonica', 'plocice_bijele');
  room(6, 6.4, 10, 10, 'Spavaća soba', 'parket_hrast');
  room(10, 6.4, 12, 10, 'Garderoba', 'laminat_svijetli');
  _outerWalls(c, const Rect.fromLTRB(0, 0, 12, 10), 0.3);

  _opening(c, 0, 5.7, OpeningType.door, width: 1.0); // ulaz
  _opening(c, 6.0, 5, OpeningType.door);
  _opening(c, 10.5, 5, OpeningType.door);
  _opening(c, 7, 2.5, OpeningType.passage, width: 1.6);
  _opening(c, 2.8, 6.4, OpeningType.door, width: 0.8);
  _opening(c, 4.8, 6.4, OpeningType.door, width: 0.8);
  _opening(c, 6.8, 6.4, OpeningType.door, width: 0.8);
  _opening(c, 10, 7.2, OpeningType.door, width: 0.8);
  _opening(c, 1.8, 0, OpeningType.window);
  _opening(c, 5.2, 0, OpeningType.window);
  _opening(c, 0, 2.5, OpeningType.balcony);
  _opening(c, 12, 2.5, OpeningType.window);
  _opening(c, 1.8, 10, OpeningType.window);
  _opening(c, 4.8, 10, OpeningType.window, width: 0.8, height: 0.8, sill: 1.4);
  _opening(c, 8, 10, OpeningType.window, width: 1.6);

  // Dnevni boravak
  _put(c, 'rug', 3.5, 2.6, 90);
  _put(c, 'sofa_corner', 3.5, 3.99, 180);
  _put(c, 'coffee_table', 3.5, 2.6);
  _put(c, 'tv_unit', 3.5, 0.375);
  _put(c, 'armchair', 6.49, 1.0, 90);
  _put(c, 'plant', 0.55, 0.55);
  _put(c, 'floor_lamp', 0.5, 4.5);
  // Kuhinja
  _put(c, 'kitchen_block_360', 9.4, 0.45);
  _put(c, 'fridge', 11.525, 1.25, 90);
  _put(c, 'dining_table', 9.4, 2.9);
  _put(c, 'chair', 8.95, 2.25);
  _put(c, 'chair', 9.85, 2.25);
  _put(c, 'chair', 8.95, 3.55, 180);
  _put(c, 'chair', 9.85, 3.55, 180);
  // Hodnik
  _put(c, 'shoe_cabinet', 1.4, 5.21);
  _put(c, 'plant', 11.6, 5.7);
  // Dječja
  _put(c, 'bed_90', 1.18, 9.2, 270);
  _put(c, 'desk', 3.19, 8.0, 90);
  _put(c, 'office_chair', 2.55, 8.0, 270);
  _put(c, 'toy_shelf', 1.0, 6.64);
  _put(c, 'rug_round', 1.9, 7.9);
  // Kupaonica
  _put(c, 'bathtub', 4.8, 9.475, 180);
  _put(c, 'toilet', 3.985, 7.8, 270);
  _put(c, 'vanity', 5.71, 7.4, 90);
  _put(c, 'washer', 5.64, 8.5, 90);
  // Spavaća
  _put(c, 'bed_180', 8.88, 8.3, 90);
  _put(c, 'nightstand', 9.69, 7.0, 90);
  _put(c, 'nightstand', 9.69, 9.6, 90);
  _put(c, 'wardrobe_200', 6.36, 8.6, 270);
  // Garderoba
  _put(c, 'wardrobe_100', 11.55, 7.25, 90);
  _put(c, 'wardrobe_100', 11.55, 8.35, 90);
  _put(c, 'dresser', 11.1, 9.6, 180);

  // Vrt
  _put(c, 'deck', 3.5, -1.65);
  _put(c, 'garden_table', 3.5, -1.8);
  _put(c, 'garden_chair', 2.9, -2.4);
  _put(c, 'garden_chair', 4.1, -2.4);
  _put(c, 'garden_chair', 2.9, -1.2, 180);
  _put(c, 'garden_chair', 4.1, -1.2, 180);
  _put(c, 'grill', 0.6, -2.4, 270);
  _put(c, 'pool', 6.5, -7);
  _put(c, 'lounger', 11.6, -6.6);
  _put(c, 'lounger', 12.5, -6.6);
  _put(c, 'umbrella', 12.0, -8.6);
  _put(c, 'tree', -3.5, -3.0);
  _put(c, 'tree', 15.0, -4.0);
  _put(c, 'tree_small', -2.5, 11.5);
  for (var y = 1.0; y <= 9; y += 2.0) {
    _put(c, 'cypress', 14.5, y);
  }
  for (var x = 0.0; x <= 12; x += 2.0) {
    _put(c, 'hedge', x, -11);
  }
  _put(c, 'path', -2.15, 5.7, 90);
  _put(c, 'flowerbed', -0.8, 2.5, 90);
  _put(c, 'driveway', -6.5, 8.5);
  _put(c, 'car', -6.5, 8.5);
  _put(c, 'shed', -6, -6);
}

void buildApartment(PlanController c) {
  c.plan.wallHeight = 2.6;
  void room(double l, double t, double r, double b, String name, String floor) =>
      c.addRoomRect(Rect.fromLTRB(l, t, r, b), name: name, floor: floor);
  room(0, 0, 6, 4.2, 'Dnevni boravak s kuhinjom', 'parket_hrast');
  room(6, 0, 10, 4.2, 'Spavaća soba', 'parket_hrast');
  room(3, 4.2, 7.4, 7, 'Predsoblje', 'plocice_sive');
  room(0, 4.2, 3, 7, 'Dječja soba', 'laminat_svijetli');
  room(7.4, 4.2, 10, 7, 'Kupaonica', 'plocice_bijele');
  _outerWalls(c, const Rect.fromLTRB(0, 0, 10, 7), 0.25);

  _opening(c, 5.2, 7, OpeningType.door, width: 1.0); // ulaz
  _opening(c, 5.4, 4.2, OpeningType.door, width: 0.8);
  _opening(c, 6.7, 4.2, OpeningType.door, width: 0.8);
  _opening(c, 3, 5.6, OpeningType.door, width: 0.8);
  _opening(c, 7.4, 5.6, OpeningType.door, width: 0.8);
  _opening(c, 5.2, 0, OpeningType.window);
  _opening(c, 0, 2.4, OpeningType.balcony);
  _opening(c, 8, 0, OpeningType.window, width: 1.4);
  _opening(c, 0, 5.6, OpeningType.window);
  _opening(c, 10, 5.6, OpeningType.window, width: 0.7, height: 0.8, sill: 1.4);

  _put(c, 'kitchen_block', 1.4, 0.425);
  _put(c, 'dining_round', 1.6, 2.4);
  _put(c, 'chair', 1.6, 1.6);
  _put(c, 'chair', 1.6, 3.2, 180);
  _put(c, 'rug', 3.6, 2.8, 90);
  _put(c, 'sofa_3', 3.6, 3.665, 180);
  _put(c, 'coffee_table', 3.6, 2.75);
  _put(c, 'tv_unit', 3.6, 0.35);
  _put(c, 'plant', 5.6, 0.6);

  _put(c, 'bed_160', 8.0, 1.175);
  _put(c, 'nightstand', 6.75, 0.33);
  _put(c, 'nightstand', 9.25, 0.33);
  _put(c, 'wardrobe_200', 9.575, 3.0, 90);

  _put(c, 'bed_90', 1.155, 6.35, 270);
  _put(c, 'desk', 2.1, 4.61);
  _put(c, 'office_chair', 2.1, 5.2, 180);

  _put(c, 'bathtub', 8.65, 6.5, 180);
  _put(c, 'vanity', 8.0, 4.49);
  _put(c, 'washer', 8.9, 4.56);
  _put(c, 'toilet', 9.55, 5.45, 90);

  _put(c, 'shoe_cabinet', 4.0, 6.725, 180);
  _put(c, 'hall_wardrobe', 6.6, 6.675, 180);
  _put(c, 'plant', 3.4, 4.65);
}

/// Izgradi plan iz predloška (s prepoznatim prostorijama) bez spremanja.
Plan buildTemplatePlan(PlanTemplate t, {String? name}) {
  final c = PlanController(projectId: 'template');
  c.plan.name = name ?? t.name;
  c.replaceWith(t.build);
  final plan = c.plan;
  c.dispose();
  return plan;
}
