/// Katalog namještaja i vanjskih objekata.
///
/// Trenutno su to generički objekti s realnim mjerama i proceduralnim 3D
/// oblikom ([shape]). Stvarni proizvodi trgovaca (IKEA, JYSK, Emmezeta…)
/// dolaze kroz partnerske/affiliate feedove: tada se popunjavaju [retailer],
/// [productUrl], [price] i [modelUrl] (GLB 3D model) – vidi README.
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
    this.retailer,
    this.productUrl,
    this.price,
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
  final String? retailer;
  final String? productUrl;
  final double? price;
  final String? modelUrl;

  String get dims =>
      '${(w * 100).round()} × ${(d * 100).round()} × ${(h * 100).round()} cm';
}

const _bed = 'Spavaća soba';
const _living = 'Dnevni boravak';
const _kitchen = 'Kuhinja i blagovaonica';
const _bath = 'Kupaonica';
const _office = 'Radni kutak';
const _garden = 'Vrt i dvorište';

const List<CatalogItem> catalog = [
  // Spavaća soba
  CatalogItem(id: 'bed_160', name: 'Bračni krevet 160×200', category: _bed, zone: CatalogZone.interior, shape: 'bed', w: 1.66, d: 2.10, h: 1.00, color: 0xFFB08D6E),
  CatalogItem(id: 'bed_90', name: 'Krevet 90×200', category: _bed, zone: CatalogZone.interior, shape: 'bed', w: 0.96, d: 2.06, h: 0.90, color: 0xFFD9C7B0),
  CatalogItem(id: 'wardrobe_150', name: 'Ormar 150', category: _bed, zone: CatalogZone.interior, shape: 'wardrobe', w: 1.50, d: 0.60, h: 2.20, color: 0xFFEDE7DF),
  CatalogItem(id: 'nightstand', name: 'Noćni ormarić', category: _bed, zone: CatalogZone.interior, shape: 'box', w: 0.45, d: 0.40, h: 0.50, color: 0xFFB08D6E),
  CatalogItem(id: 'dresser', name: 'Komoda', category: _bed, zone: CatalogZone.interior, shape: 'box', w: 1.20, d: 0.50, h: 0.80, color: 0xFFEDE7DF),
  // Dnevni boravak
  CatalogItem(id: 'sofa_3', name: 'Trosjed', category: _living, zone: CatalogZone.interior, shape: 'sofa', w: 2.20, d: 0.95, h: 0.85, color: 0xFF7C8B99),
  CatalogItem(id: 'armchair', name: 'Fotelja', category: _living, zone: CatalogZone.interior, shape: 'sofa', w: 0.90, d: 0.90, h: 0.85, color: 0xFF9A7B65),
  CatalogItem(id: 'coffee_table', name: 'Klub stolić', category: _living, zone: CatalogZone.interior, shape: 'table', w: 1.10, d: 0.60, h: 0.45, color: 0xFF8C6A4F),
  CatalogItem(id: 'tv_unit', name: 'TV komoda s TV-om', category: _living, zone: CatalogZone.interior, shape: 'tv', w: 1.80, d: 0.45, h: 1.25, color: 0xFF3D3D3D),
  CatalogItem(id: 'bookshelf', name: 'Polica za knjige', category: _living, zone: CatalogZone.interior, shape: 'shelf', w: 0.80, d: 0.35, h: 1.90, color: 0xFFF0EDE8),
  CatalogItem(id: 'rug', name: 'Tepih 200×300', category: _living, zone: CatalogZone.interior, shape: 'rug', w: 2.00, d: 3.00, h: 0.01, color: 0xFFC9B79C),
  CatalogItem(id: 'floor_lamp', name: 'Podna lampa', category: _living, zone: CatalogZone.interior, shape: 'lamp', w: 0.40, d: 0.40, h: 1.60, color: 0xFFEFE6D2),
  CatalogItem(id: 'plant', name: 'Sobna biljka', category: _living, zone: CatalogZone.interior, shape: 'plant', w: 0.50, d: 0.50, h: 1.20, color: 0xFF4F7F4A),
  // Kuhinja
  CatalogItem(id: 'kitchen_block', name: 'Kuhinjski blok 240', category: _kitchen, zone: CatalogZone.interior, shape: 'kitchen', w: 2.40, d: 0.60, h: 2.20, color: 0xFFFFFFFF),
  CatalogItem(id: 'kitchen_base', name: 'Donji element 60', category: _kitchen, zone: CatalogZone.interior, shape: 'kitchen', w: 0.60, d: 0.60, h: 0.90, color: 0xFFFFFFFF),
  CatalogItem(id: 'fridge', name: 'Hladnjak', category: _kitchen, zone: CatalogZone.interior, shape: 'box', w: 0.60, d: 0.65, h: 1.85, color: 0xFFDADDE0),
  CatalogItem(id: 'dining_table', name: 'Blagovaonski stol', category: _kitchen, zone: CatalogZone.interior, shape: 'table', w: 1.60, d: 0.90, h: 0.75, color: 0xFFA07A55),
  CatalogItem(id: 'chair', name: 'Stolica', category: _kitchen, zone: CatalogZone.interior, shape: 'chair', w: 0.45, d: 0.50, h: 0.90, color: 0xFF5A4636),
  // Kupaonica
  CatalogItem(id: 'bathtub', name: 'Kada', category: _bath, zone: CatalogZone.interior, shape: 'bath', w: 1.70, d: 0.75, h: 0.60, color: 0xFFFFFFFF),
  CatalogItem(id: 'shower', name: 'Tuš kabina', category: _bath, zone: CatalogZone.interior, shape: 'shower', w: 0.90, d: 0.90, h: 2.00, color: 0xFFFFFFFF),
  CatalogItem(id: 'toilet', name: 'WC školjka', category: _bath, zone: CatalogZone.interior, shape: 'toilet', w: 0.38, d: 0.65, h: 0.80, color: 0xFFFFFFFF),
  CatalogItem(id: 'vanity', name: 'Umivaonik s ormarićem', category: _bath, zone: CatalogZone.interior, shape: 'kitchen', w: 0.80, d: 0.46, h: 0.85, color: 0xFFFFFFFF),
  // Radni kutak
  CatalogItem(id: 'desk', name: 'Radni stol', category: _office, zone: CatalogZone.interior, shape: 'table', w: 1.40, d: 0.70, h: 0.75, color: 0xFFE8E2D8),
  CatalogItem(id: 'office_chair', name: 'Uredska stolica', category: _office, zone: CatalogZone.interior, shape: 'chair', w: 0.60, d: 0.60, h: 1.10, color: 0xFF2E2E2E),
  // Vrt i dvorište
  CatalogItem(id: 'tree', name: 'Stablo', category: _garden, zone: CatalogZone.exterior, shape: 'tree', w: 3.0, d: 3.0, h: 6.0, color: 0xFF3F7A3A),
  CatalogItem(id: 'tree_small', name: 'Ukrasno stablo', category: _garden, zone: CatalogZone.exterior, shape: 'tree', w: 1.5, d: 1.5, h: 3.0, color: 0xFF5C8F3E),
  CatalogItem(id: 'hedge', name: 'Živica 2 m', category: _garden, zone: CatalogZone.exterior, shape: 'hedge', w: 2.0, d: 0.6, h: 1.4, color: 0xFF3E6B35),
  CatalogItem(id: 'fence', name: 'Ograda 3 m', category: _garden, zone: CatalogZone.exterior, shape: 'fence', w: 3.0, d: 0.06, h: 1.2, color: 0xFFE9E4DA),
  CatalogItem(id: 'pool', name: 'Bazen 8×4', category: _garden, zone: CatalogZone.exterior, shape: 'pool', w: 8.0, d: 4.0, h: 0.3, color: 0xFF4FB3E0),
  CatalogItem(id: 'deck', name: 'Terasa (deck)', category: _garden, zone: CatalogZone.exterior, shape: 'deck', w: 4.0, d: 3.0, h: 0.12, color: 0xFF9C7350),
  CatalogItem(id: 'garden_table', name: 'Vrtni stol', category: _garden, zone: CatalogZone.exterior, shape: 'table', w: 1.40, d: 0.80, h: 0.74, color: 0xFF6E6E6E),
  CatalogItem(id: 'garden_chair', name: 'Vrtna stolica', category: _garden, zone: CatalogZone.exterior, shape: 'chair', w: 0.55, d: 0.60, h: 0.85, color: 0xFF6E6E6E),
  CatalogItem(id: 'lounger', name: 'Ležaljka', category: _garden, zone: CatalogZone.exterior, shape: 'lounger', w: 0.70, d: 1.90, h: 0.40, color: 0xFFF2F2F2),
  CatalogItem(id: 'umbrella', name: 'Suncobran', category: _garden, zone: CatalogZone.exterior, shape: 'umbrella', w: 2.5, d: 2.5, h: 2.4, color: 0xFFE9E2D0),
  CatalogItem(id: 'path', name: 'Staza (ploče)', category: _garden, zone: CatalogZone.exterior, shape: 'rug', w: 1.0, d: 4.0, h: 0.02, color: 0xFFB9B4AA),
  CatalogItem(id: 'car', name: 'Automobil', category: _garden, zone: CatalogZone.exterior, shape: 'car', w: 1.8, d: 4.5, h: 1.5, color: 0xFF8899AA),
];

CatalogItem? catalogById(String id) {
  for (final c in catalog) {
    if (c.id == id) return c;
  }
  return null;
}
