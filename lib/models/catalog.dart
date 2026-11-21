/// Katalog namještaja i vanjskih objekata.
///
/// Generički objekti s realnim mjerama, proceduralnim 3D oblikom ([shape]) i
/// okvirnom cijenom. Proizvodi trgovaca (IKEA, JYSK, Emmezeta…) dolaze kroz
/// partnerske feedove: tada se popunjavaju [retailer], [productUrl] i
/// [modelUrl] (GLB 3D model).
enum CatalogZone { interior, exterior }

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.name,
    required this.category,
    required this.zone,
    required this.shape,
    required this.w,
    required this.d,
    required this.h,
    required this.color,
    this.price,
    this.retailer,
    this.productUrl,
    this.modelUrl,
  });

  final String id;
  final String name;
  final String category;
  final CatalogZone zone;
  final String shape;
  final double w; // širina (m)
  final double d; // dubina (m)
  final double h; // visina (m)
  final int color;

  /// Okvirna cijena u eurima (srednji cjenovni razred).
  final double? price;
  final String? retailer;
  final String? productUrl;
  final String? modelUrl;

  String get dims => '${(w * 100).round()} × ${(d * 100).round()} × ${(h * 100).round()} cm';

  Map<String, dynamic> toSceneJson() => {
        'id': 'thumb-$id',
        'shape': shape,
        'x': 0,
        'y': 0,
        'rotation': 0,
        'w': w,
        'd': d,
        'h': h,
        'color': color,
        if (modelUrl != null) 'modelUrl': modelUrl,
      };
}

const catLiving = 'Dnevni boravak';
const catBed = 'Spavaća soba';
const catKitchen = 'Kuhinja i blagovaonica';
const catBath = 'Kupaonica';
const catWork = 'Radni kutak i dječja';
const catHall = 'Predsoblje i ostalo';
const catGarden = 'Vrt i terasa';
const catYard = 'Dvorište';

const _i = CatalogZone.interior;
const _e = CatalogZone.exterior;

const List<CatalogItem> catalog = [
  // Dnevni boravak
  CatalogItem(id: 'sofa_3', name: 'Trosjed', category: catLiving, zone: _i, shape: 'sofa', w: 2.20, d: 0.95, h: 0.85, color: 0xFF7C8B99, price: 650),
  CatalogItem(id: 'sofa_corner', name: 'Kutna garnitura', category: catLiving, zone: _i, shape: 'sofa_corner', w: 2.80, d: 1.90, h: 0.85, color: 0xFF8E8A84, price: 1100),
  CatalogItem(id: 'armchair', name: 'Fotelja', category: catLiving, zone: _i, shape: 'sofa', w: 0.90, d: 0.90, h: 0.85, color: 0xFF9A7B65, price: 280),
  CatalogItem(id: 'coffee_table', name: 'Klub stolić', category: catLiving, zone: _i, shape: 'table', w: 1.10, d: 0.60, h: 0.45, color: 0xFF8C6A4F, price: 120),
  CatalogItem(id: 'tv_unit', name: 'TV komoda s televizorom', category: catLiving, zone: _i, shape: 'tv', w: 1.80, d: 0.45, h: 1.25, color: 0xFF3D3D3D, price: 750),
  CatalogItem(id: 'bookshelf', name: 'Polica za knjige', category: catLiving, zone: _i, shape: 'shelf', w: 0.80, d: 0.35, h: 1.90, color: 0xFFF0EDE8, price: 90),
  CatalogItem(id: 'sideboard', name: 'Niska komoda', category: catLiving, zone: _i, shape: 'dresser', w: 1.60, d: 0.45, h: 0.75, color: 0xFFE7DFD3, price: 250),
  CatalogItem(id: 'rug', name: 'Tepih 200 × 300', category: catLiving, zone: _i, shape: 'rug', w: 2.00, d: 3.00, h: 0.01, color: 0xFFC9B79C, price: 180),
  CatalogItem(id: 'rug_round', name: 'Okrugli tepih', category: catLiving, zone: _i, shape: 'rug_round', w: 1.60, d: 1.60, h: 0.01, color: 0xFF9FA8A3, price: 110),
  CatalogItem(id: 'floor_lamp', name: 'Podna lampa', category: catLiving, zone: _i, shape: 'lamp', w: 0.40, d: 0.40, h: 1.60, color: 0xFFEFE6D2, price: 60),
  CatalogItem(id: 'plant', name: 'Sobna biljka', category: catLiving, zone: _i, shape: 'plant', w: 0.50, d: 0.50, h: 1.20, color: 0xFF4F7F4A, price: 40),
  CatalogItem(id: 'fireplace', name: 'Kamin', category: catLiving, zone: _i, shape: 'fireplace', w: 1.20, d: 0.50, h: 1.10, color: 0xFFE3DED6, price: 1500),

  // Spavaća soba
  CatalogItem(id: 'bed_180', name: 'Bračni krevet 180 × 200', category: catBed, zone: _i, shape: 'bed', w: 1.86, d: 2.12, h: 1.00, color: 0xFF9B9590, price: 550),
  CatalogItem(id: 'bed_160', name: 'Bračni krevet 160 × 200', category: catBed, zone: _i, shape: 'bed', w: 1.66, d: 2.10, h: 1.00, color: 0xFFB08D6E, price: 450),
  CatalogItem(id: 'bed_90', name: 'Krevet 90 × 200', category: catBed, zone: _i, shape: 'bed', w: 0.96, d: 2.06, h: 0.90, color: 0xFFD9C7B0, price: 220),
  CatalogItem(id: 'wardrobe_200', name: 'Ormar 200', category: catBed, zone: _i, shape: 'wardrobe', w: 2.00, d: 0.60, h: 2.36, color: 0xFFEDE7DF, price: 480),
  CatalogItem(id: 'wardrobe_100', name: 'Ormar 100', category: catBed, zone: _i, shape: 'wardrobe', w: 1.00, d: 0.60, h: 2.20, color: 0xFFEDE7DF, price: 220),
  CatalogItem(id: 'nightstand', name: 'Noćni ormarić', category: catBed, zone: _i, shape: 'dresser', w: 0.45, d: 0.40, h: 0.50, color: 0xFFB08D6E, price: 60),
  CatalogItem(id: 'dresser', name: 'Komoda s ladicama', category: catBed, zone: _i, shape: 'dresser', w: 1.20, d: 0.50, h: 0.80, color: 0xFFEDE7DF, price: 180),

  // Kuhinja
  CatalogItem(id: 'kitchen_block', name: 'Kuhinjski blok 240', category: catKitchen, zone: _i, shape: 'kitchen', w: 2.40, d: 0.60, h: 2.20, color: 0xFFFFFFFF, price: 2200),
  CatalogItem(id: 'kitchen_block_360', name: 'Kuhinjski blok 360', category: catKitchen, zone: _i, shape: 'kitchen', w: 3.60, d: 0.60, h: 2.20, color: 0xFF5F6B63, price: 3400),
  CatalogItem(id: 'kitchen_base', name: 'Donji element 60', category: catKitchen, zone: _i, shape: 'kitchen', w: 0.60, d: 0.60, h: 0.90, color: 0xFFFFFFFF, price: 250),
  CatalogItem(id: 'island', name: 'Kuhinjski otok', category: catKitchen, zone: _i, shape: 'island', w: 1.80, d: 0.90, h: 0.92, color: 0xFFFFFFFF, price: 1200),
  CatalogItem(id: 'stove', name: 'Štednjak', category: catKitchen, zone: _i, shape: 'stove', w: 0.60, d: 0.60, h: 0.90, color: 0xFFDADDE0, price: 450),
  CatalogItem(id: 'fridge', name: 'Hladnjak', category: catKitchen, zone: _i, shape: 'fridge', w: 0.60, d: 0.65, h: 1.85, color: 0xFFDADDE0, price: 600),
  CatalogItem(id: 'dining_table', name: 'Blagovaonski stol', category: catKitchen, zone: _i, shape: 'table', w: 1.60, d: 0.90, h: 0.75, color: 0xFFA07A55, price: 350),
  CatalogItem(id: 'dining_round', name: 'Okrugli stol', category: catKitchen, zone: _i, shape: 'table_round', w: 1.10, d: 1.10, h: 0.75, color: 0xFFD7C4A8, price: 280),
  CatalogItem(id: 'chair', name: 'Stolica', category: catKitchen, zone: _i, shape: 'chair', w: 0.45, d: 0.50, h: 0.90, color: 0xFF5A4636, price: 70),
  CatalogItem(id: 'bar_stool', name: 'Barska stolica', category: catKitchen, zone: _i, shape: 'stool', w: 0.40, d: 0.40, h: 0.75, color: 0xFF3D3D3D, price: 80),

  // Kupaonica
  CatalogItem(id: 'bathtub', name: 'Kada', category: catBath, zone: _i, shape: 'bath', w: 1.70, d: 0.75, h: 0.60, color: 0xFFFFFFFF, price: 450),
  CatalogItem(id: 'shower', name: 'Tuš kabina 90', category: catBath, zone: _i, shape: 'shower', w: 0.90, d: 0.90, h: 2.00, color: 0xFFFFFFFF, price: 500),
  CatalogItem(id: 'toilet', name: 'WC školjka', category: catBath, zone: _i, shape: 'toilet', w: 0.38, d: 0.65, h: 0.80, color: 0xFFFFFFFF, price: 220),
  CatalogItem(id: 'vanity', name: 'Umivaonik s ormarićem', category: catBath, zone: _i, shape: 'vanity', w: 0.80, d: 0.46, h: 0.85, color: 0xFFFFFFFF, price: 350),
  CatalogItem(id: 'washer', name: 'Perilica rublja', category: catBath, zone: _i, shape: 'washer', w: 0.60, d: 0.60, h: 0.85, color: 0xFFF2F2F2, price: 450),

  // Radni kutak i dječja
  CatalogItem(id: 'desk', name: 'Radni stol', category: catWork, zone: _i, shape: 'table', w: 1.40, d: 0.70, h: 0.75, color: 0xFFE8E2D8, price: 180),
  CatalogItem(id: 'office_chair', name: 'Uredska stolica', category: catWork, zone: _i, shape: 'chair', w: 0.60, d: 0.60, h: 1.10, color: 0xFF2E2E2E, price: 150),
  CatalogItem(id: 'bunk_bed', name: 'Krevet na kat', category: catWork, zone: _i, shape: 'bunk', w: 0.98, d: 2.08, h: 1.60, color: 0xFFE9E1D3, price: 400),
  CatalogItem(id: 'toy_shelf', name: 'Niska polica za igračke', category: catWork, zone: _i, shape: 'shelf', w: 1.20, d: 0.35, h: 0.90, color: 0xFFF3E6C8, price: 80),

  // Predsoblje i ostalo
  CatalogItem(id: 'shoe_cabinet', name: 'Ormarić za cipele', category: catHall, zone: _i, shape: 'dresser', w: 0.80, d: 0.30, h: 1.00, color: 0xFFEDE7DF, price: 120),
  CatalogItem(id: 'hall_wardrobe', name: 'Garderober za predsoblje', category: catHall, zone: _i, shape: 'wardrobe', w: 1.20, d: 0.40, h: 2.00, color: 0xFFD9C7B0, price: 260),
  CatalogItem(id: 'stairs', name: 'Stubište, ravno', category: catHall, zone: _i, shape: 'stairs', w: 1.00, d: 3.60, h: 2.80, color: 0xFFB98B5E, price: 3500),

  // Vrt i terasa
  CatalogItem(id: 'deck', name: 'Terasa od dasaka', category: catGarden, zone: _e, shape: 'deck', w: 4.0, d: 3.0, h: 0.12, color: 0xFF9C7350, price: 1800),
  CatalogItem(id: 'garden_table', name: 'Vrtni stol', category: catGarden, zone: _e, shape: 'table', w: 1.40, d: 0.80, h: 0.74, color: 0xFF6E6E6E, price: 250),
  CatalogItem(id: 'garden_chair', name: 'Vrtna stolica', category: catGarden, zone: _e, shape: 'chair', w: 0.55, d: 0.60, h: 0.85, color: 0xFF6E6E6E, price: 60),
  CatalogItem(id: 'lounger', name: 'Ležaljka', category: catGarden, zone: _e, shape: 'lounger', w: 0.70, d: 1.90, h: 0.40, color: 0xFFF2F2F2, price: 120),
  CatalogItem(id: 'umbrella', name: 'Suncobran', category: catGarden, zone: _e, shape: 'umbrella', w: 2.5, d: 2.5, h: 2.4, color: 0xFFE9E2D0, price: 150),
  CatalogItem(id: 'grill', name: 'Roštilj', category: catGarden, zone: _e, shape: 'grill', w: 1.20, d: 0.60, h: 1.10, color: 0xFF2F3437, price: 400),
  CatalogItem(id: 'pool', name: 'Bazen 8 × 4', category: catGarden, zone: _e, shape: 'pool', w: 8.0, d: 4.0, h: 0.3, color: 0xFF4FB3E0, price: 15000),
  CatalogItem(id: 'flowerbed', name: 'Gredica s cvijećem', category: catGarden, zone: _e, shape: 'flowerbed', w: 2.0, d: 0.8, h: 0.4, color: 0xFF7A5A3A, price: 150),

  // Dvorište
  CatalogItem(id: 'tree', name: 'Stablo', category: catYard, zone: _e, shape: 'tree', w: 3.0, d: 3.0, h: 6.0, color: 0xFF3F7A3A, price: 150),
  CatalogItem(id: 'tree_small', name: 'Ukrasno stablo', category: catYard, zone: _e, shape: 'tree', w: 1.5, d: 1.5, h: 3.0, color: 0xFF5C8F3E, price: 60),
  CatalogItem(id: 'cypress', name: 'Čempres', category: catYard, zone: _e, shape: 'cypress', w: 0.9, d: 0.9, h: 5.0, color: 0xFF2F5A34, price: 90),
  CatalogItem(id: 'hedge', name: 'Živica 2 m', category: catYard, zone: _e, shape: 'hedge', w: 2.0, d: 0.6, h: 1.4, color: 0xFF3E6B35, price: 80),
  CatalogItem(id: 'fence', name: 'Ograda 3 m', category: catYard, zone: _e, shape: 'fence', w: 3.0, d: 0.06, h: 1.2, color: 0xFFE9E4DA, price: 150),
  CatalogItem(id: 'path', name: 'Staza od ploča', category: catYard, zone: _e, shape: 'path', w: 1.0, d: 4.0, h: 0.02, color: 0xFFB9B4AA, price: 200),
  CatalogItem(id: 'driveway', name: 'Prilaz za auto', category: catYard, zone: _e, shape: 'path', w: 3.0, d: 6.0, h: 0.02, color: 0xFF8E8C88, price: 1500),
  CatalogItem(id: 'carport', name: 'Nadstrešnica za auto', category: catYard, zone: _e, shape: 'carport', w: 3.0, d: 5.5, h: 2.4, color: 0xFF6E5A48, price: 2500),
  CatalogItem(id: 'shed', name: 'Vrtna kućica', category: catYard, zone: _e, shape: 'shed', w: 2.5, d: 2.0, h: 2.3, color: 0xFF8C6A4F, price: 1200),
  CatalogItem(id: 'trampoline', name: 'Trampolin', category: catYard, zone: _e, shape: 'trampoline', w: 3.0, d: 3.0, h: 0.9, color: 0xFF2F3437, price: 300),
  CatalogItem(id: 'swing', name: 'Ljuljačka', category: catYard, zone: _e, shape: 'swing', w: 2.2, d: 1.6, h: 2.1, color: 0xFF8C6A4F, price: 250),
  CatalogItem(id: 'car', name: 'Automobil', category: catYard, zone: _e, shape: 'car', w: 1.8, d: 4.5, h: 1.5, color: 0xFF8899AA),
];

CatalogItem? catalogById(String id) {
  for (final c in catalog) {
    if (c.id == id) return c;
  }
  return null;
}

/// Oblici koji leže na podu (ne zauzimaju prostor, imaju niži prioritet odabira).
const floorShapes = {'rug', 'rug_round', 'deck', 'pool', 'path'};
