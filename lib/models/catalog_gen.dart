import 'catalog.dart';

/// Generirani katalog: vrste namještaja × stilovi × veličine × boje × izvedbe.
/// Svi ID-jevi su deterministički pa se spremljeni projekti uvijek mogu povezati
/// s proizvodom.

class Style {
  const Style(this.id, this.name, this.series, this.priceFactor, this.legs, this.legColor);
  final String id;
  final String name;

  /// Naziv kolekcije u tom stilu (npr. "Učka").
  final String series;
  final double priceFactor;

  /// Zadane noge za stil.
  final String legs;
  final int legColor;
}

const styles = <Style>[
  Style('skandi', 'Skandinavski', 'Učka', 1.0, 'wood', 0xFFD7B98E),
  Style('moderni', 'Moderni', 'Mosor', 1.15, 'chrome', 0xFFC9CBCC),
  Style('klasicni', 'Klasični', 'Velebit', 1.3, 'wood', 0xFF5A3E2B),
  Style('industrijski', 'Industrijski', 'Dinara', 1.1, 'metal', 0xFF2A2A2A),
  Style('rustikalni', 'Rustikalni', 'Biokovo', 1.2, 'wood', 0xFF8A6243),
  Style('minimal', 'Minimalistički', 'Kornat', 1.05, 'plinth', 0xFF3A3A3A),
  Style('boho', 'Boho', 'Mljet', 0.95, 'wood', 0xFFC49A6C),
  Style('retro', 'Retro', 'Vis', 1.0, 'wood', 0xFF9A6A43),
];

Style styleById(String? id) => styles.firstWhere((s) => s.id == id, orElse: () => styles.first);

class NamedColor {
  const NamedColor(this.name, this.color);
  final String name;
  final int color;
}

const _fabric = <NamedColor>[
  NamedColor('siva', 0xFF8E9296),
  NamedColor('svijetlosiva', 0xFFC4C6C6),
  NamedColor('antracit', 0xFF4A4E52),
  NamedColor('bež', 0xFFCDBBA0),
  NamedColor('krem', 0xFFE8DFCE),
  NamedColor('tamnoplava', 0xFF33455E),
  NamedColor('petrolej', 0xFF2F5F63),
  NamedColor('kadulja', 0xFF9AA98C),
  NamedColor('maslinasta', 0xFF6B6F45),
  NamedColor('terakota', 0xFFB4664B),
  NamedColor('konjak', 0xFF8C5A35),
  NamedColor('senf', 0xFFC99A35),
  NamedColor('bordo', 0xFF6E2E35),
  NamedColor('ružičasta', 0xFFD4A5A0),
];

const _wood = <NamedColor>[
  NamedColor('hrast', 0xFFC09A6B),
  NamedColor('svijetli hrast', 0xFFD9C09A),
  NamedColor('orah', 0xFF7A5236),
  NamedColor('bukva', 0xFFD2AE84),
  NamedColor('trešnja', 0xFF9A5A3C),
  NamedColor('bijela', 0xFFF1EFEA),
  NamedColor('crna', 0xFF2C2C2C),
  NamedColor('siva', 0xFF9C9C98),
  NamedColor('kadulja', 0xFFA9B59A),
  NamedColor('tamnoplava', 0xFF3A4A60),
];

const _fronts = <NamedColor>[
  NamedColor('bijela sjajna', 0xFFFAFAF8),
  NamedColor('bijela mat', 0xFFEDEBE6),
  NamedColor('kašmir', 0xFFD8CFC2),
  NamedColor('siva', 0xFFA4A6A4),
  NamedColor('antracit', 0xFF4B4F52),
  NamedColor('hrast', 0xFFC09A6B),
  NamedColor('orah', 0xFF7A5236),
  NamedColor('kadulja', 0xFF9AA98C),
  NamedColor('tamnoplava', 0xFF33455E),
  NamedColor('crna mat', 0xFF2A2A2A),
];

const _appliance = <NamedColor>[
  NamedColor('inox', 0xFFC5C8CA),
  NamedColor('bijela', 0xFFF4F4F2),
  NamedColor('crna', 0xFF2A2B2D),
];

const _sanitary = <NamedColor>[NamedColor('bijela', 0xFFFFFFFF), NamedColor('crna mat', 0xFF2E2E2E)];

const _outdoor = <NamedColor>[
  NamedColor('antracit', 0xFF4A4E52),
  NamedColor('bijela', 0xFFF0F0EC),
  NamedColor('tikovina', 0xFF9C7350),
  NamedColor('siva', 0xFF9A9C9A),
  NamedColor('zelena', 0xFF5E7A55),
];

const _shade = <NamedColor>[
  NamedColor('bež', 0xFFE3D6BC),
  NamedColor('bijela', 0xFFF2F0EA),
  NamedColor('siva', 0xFFA9ABAA),
  NamedColor('terakota', 0xFFC27A5E),
  NamedColor('zelena', 0xFF7D9A72),
];

const _green = <NamedColor>[
  NamedColor('zelena', 0xFF4F7F4A),
  NamedColor('tamnozelena', 0xFF3A5E37),
  NamedColor('svijetlozelena', 0xFF6E9A55),
];

const _stone = <NamedColor>[
  NamedColor('svijetli kamen', 0xFFC9C1B2),
  NamedColor('sivi kamen', 0xFF9E9C97),
  NamedColor('pješčenjak', 0xFFD3BE97),
];

const _elec = <NamedColor>[NamedColor('bijela', 0xFFF4F4F2), NamedColor('antracit', 0xFF3F4347), NamedColor('crna', 0xFF1E1E1E)];
const _lightMetal = <NamedColor>[
  NamedColor('crna', 0xFF2B2B2B),
  NamedColor('zlatna', 0xFFC9A55A),
  NamedColor('krom', 0xFFD0D2D4),
  NamedColor('mesing', 0xFFB08D57),
  NamedColor('bijela', 0xFFF0EEE9),
];
const _lampShade = <NamedColor>[
  NamedColor('crna', 0xFF2B2B2B),
  NamedColor('bijela', 0xFFF0EEE9),
  NamedColor('zlatna', 0xFFC9A55A),
  NamedColor('kadulja', 0xFF9DAE95),
  NamedColor('terakota', 0xFFC27A5E),
];
const _metalFinish = <NamedColor>[NamedColor('krom', 0xFFD0D2D4), NamedColor('crna', 0xFF2E2E2E)];
const _pool = <NamedColor>[NamedColor('plava', 0xFF4FB3E0), NamedColor('tirkizna', 0xFF4FC6C0)];
const _car = <NamedColor>[
  NamedColor('siva', 0xFF8899AA),
  NamedColor('crna', 0xFF26292D),
  NamedColor('bijela', 0xFFF2F2F2),
  NamedColor('plava', 0xFF2F5A8A),
  NamedColor('crvena', 0xFFA8323A),
];

/// Izvedbe nogu koje se nude kao zasebne varijante.
const _legOptions = <(String, String)>[
  ('wood', 'drvene noge'),
  ('metal', 'metalne noge'),
  ('plinth', 'bez nogu'),
];

class Family {
  const Family({
    required this.id,
    required this.name,
    required this.category,
    required this.shape,
    required this.sizes,
    required this.price,
    required this.colors,
    this.zone = CatalogZone.interior,
    this.styled = true,
    this.legVariants = false,
  });

  final String id;
  final String name;
  final String category;
  final String shape;

  /// (širina, dubina, visina) u metrima.
  final List<(double, double, double)> sizes;

  /// Okvirna cijena prve veličine u srednjem razredu (€).
  final double price;
  final List<NamedColor> colors;
  final CatalogZone zone;
  final bool styled;
  final bool legVariants;
}

const _e = CatalogZone.exterior;

const families = <Family>[
  // ---------------------------------------------------------------- dnevni boravak
  Family(id: 'dvosjed', name: 'Dvosjed', category: catLiving, shape: 'sofa', sizes: [(1.5, 0.88, 0.84), (1.7, 0.9, 0.85), (1.85, 0.92, 0.85)], price: 450, colors: _fabric, legVariants: true),
  Family(id: 'trosjed', name: 'Trosjed', category: catLiving, shape: 'sofa', sizes: [(2.0, 0.95, 0.85), (2.2, 0.95, 0.85), (2.4, 0.98, 0.88)], price: 650, colors: _fabric, legVariants: true),
  Family(id: 'cetverosjed', name: 'Četverosjed', category: catLiving, shape: 'sofa', sizes: [(2.6, 1.0, 0.88), (2.9, 1.0, 0.88)], price: 900, colors: _fabric, legVariants: true),
  Family(id: 'kutna', name: 'Kutna garnitura', category: catLiving, shape: 'sofa_corner', sizes: [(2.4, 1.6, 0.85), (2.8, 1.9, 0.85), (3.2, 2.1, 0.86)], price: 1100, colors: _fabric, legVariants: true),
  Family(id: 'kutna_lezaj', name: 'Kutna garnitura s ležajem', category: catLiving, shape: 'sofa_corner', sizes: [(2.6, 1.7, 0.88), (3.0, 2.0, 0.88)], price: 1300, colors: _fabric, legVariants: true),
  Family(id: 'chaise', name: 'Sofa s ležaljkom', category: catLiving, shape: 'sofa_corner', sizes: [(2.2, 1.5, 0.85), (2.5, 1.6, 0.85), (2.8, 1.65, 0.86)], price: 950, colors: _fabric, legVariants: true),
  Family(id: 'konzola', name: 'Konzolni stolić', category: catLiving, shape: 'table', sizes: [(1.0, 0.35, 0.8), (1.2, 0.35, 0.8)], price: 140, colors: _wood, legVariants: true),
  Family(id: 'lezaj', name: 'Ležaj na razvlačenje', category: catLiving, shape: 'sofa', sizes: [(2.0, 1.0, 0.9), (2.2, 1.05, 0.9)], price: 700, colors: _fabric),
  Family(id: 'fotelja', name: 'Fotelja', category: catLiving, shape: 'sofa', sizes: [(0.78, 0.84, 0.84), (0.9, 0.9, 0.92)], price: 280, colors: _fabric, legVariants: true),
  Family(id: 'pouf', name: 'Tabure', category: catLiving, shape: 'pouf', sizes: [(0.45, 0.45, 0.42), (0.6, 0.6, 0.42), (0.9, 0.6, 0.42)], price: 60, colors: _fabric),
  Family(id: 'klub', name: 'Klub stolić', category: catLiving, shape: 'table', sizes: [(0.9, 0.5, 0.45), (1.1, 0.6, 0.45), (1.2, 0.7, 0.42)], price: 120, colors: _wood, legVariants: true),
  Family(id: 'klub_okrugli', name: 'Okrugli klub stolić', category: catLiving, shape: 'table_round', sizes: [(0.6, 0.6, 0.45), (0.8, 0.8, 0.42), (1.0, 1.0, 0.4)], price: 110, colors: _wood),
  Family(id: 'pomocni', name: 'Pomoćni stolić', category: catLiving, shape: 'table_round', sizes: [(0.4, 0.4, 0.55), (0.5, 0.5, 0.6)], price: 60, colors: _wood),
  Family(id: 'tv_komoda', name: 'TV komoda', category: catLiving, shape: 'tv_stand', sizes: [(1.4, 0.4, 0.5), (1.6, 0.42, 0.5), (1.8, 0.45, 0.5), (2.2, 0.45, 0.48)], price: 220, colors: _wood, legVariants: true),
  Family(id: 'tv_set', name: 'TV komoda s televizorom', category: catLiving, shape: 'tv', sizes: [(1.6, 0.42, 1.15), (1.8, 0.45, 1.25), (2.2, 0.45, 1.35)], price: 750, colors: _wood),
  Family(id: 'polica', name: 'Polica za knjige', category: catLiving, shape: 'shelf', sizes: [(0.6, 0.3, 1.8), (0.8, 0.35, 1.9), (1.2, 0.35, 2.0)], price: 90, colors: _wood),
  Family(id: 'polica_niska', name: 'Niska polica', category: catLiving, shape: 'shelf', sizes: [(0.8, 0.35, 0.9), (1.2, 0.35, 0.9), (1.6, 0.35, 0.8)], price: 70, colors: _wood),
  Family(id: 'vitrina', name: 'Vitrina', category: catLiving, shape: 'vitrine', sizes: [(0.8, 0.4, 1.9), (1.0, 0.42, 2.0)], price: 300, colors: _wood),
  Family(id: 'komoda_niska', name: 'Niska komoda', category: catLiving, shape: 'dresser', sizes: [(1.2, 0.45, 0.75), (1.6, 0.45, 0.75), (2.0, 0.45, 0.8)], price: 250, colors: _wood, legVariants: true),
  Family(id: 'tepih', name: 'Tepih', category: catLiving, shape: 'rug', sizes: [(1.6, 2.3, 0.01), (2.0, 3.0, 0.01), (2.4, 3.4, 0.01)], price: 120, colors: _fabric),
  Family(id: 'tepih_okrugli', name: 'Okrugli tepih', category: catLiving, shape: 'rug_round', sizes: [(1.2, 1.2, 0.01), (1.6, 1.6, 0.01), (2.0, 2.0, 0.01)], price: 90, colors: _fabric),
  Family(id: 'lampa', name: 'Podna lampa', category: catLight, shape: 'lamp', sizes: [(0.35, 0.35, 1.5), (0.45, 0.45, 1.7)], price: 60, colors: _shade),
  Family(id: 'lampa_luk', name: 'Podna lampa, lučna', category: catLight, shape: 'lamp_arc', sizes: [(0.4, 1.6, 1.9), (0.4, 2.0, 2.1)], price: 140, colors: _lightMetal, styled: false),
  Family(id: 'luster', name: 'Luster, klasični s kristalima', category: catLight, shape: 'chandelier', sizes: [(0.6, 0.6, 0.6), (0.8, 0.8, 0.75), (1.0, 1.0, 0.9)], price: 220, colors: _lightMetal, styled: false),
  Family(id: 'luster_prsten', name: 'Luster, LED prsten', category: catLight, shape: 'chandelier_ring', sizes: [(0.6, 0.6, 0.6), (0.8, 0.8, 0.6), (1.2, 1.2, 0.7)], price: 160, colors: _lightMetal, styled: false),
  Family(id: 'visilica', name: 'Viseća lampa', category: catLight, shape: 'pendant', sizes: [(0.3, 0.3, 0.8), (0.45, 0.45, 0.9), (0.6, 0.6, 0.9)], price: 70, colors: _lampShade, styled: false),
  Family(id: 'visilica_niz', name: 'Viseće lampe u nizu (3)', category: catLight, shape: 'pendant_row', sizes: [(1.2, 0.3, 0.9), (1.6, 0.3, 0.9)], price: 150, colors: _lampShade, styled: false),
  Family(id: 'plafonjera', name: 'Plafonjera', category: catLight, shape: 'ceiling_light', sizes: [(0.35, 0.35, 0.1), (0.5, 0.5, 0.12)], price: 45, colors: _lightMetal, styled: false),
  Family(id: 'zidna_lampa', name: 'Zidna lampa', category: catLight, shape: 'wall_lamp', sizes: [(0.2, 0.18, 0.3)], price: 40, colors: _lightMetal, styled: false),
  Family(id: 'el_uticnica', name: 'Utičnica', category: catElectric, shape: 'socket', sizes: [(0.08, 0.05, 0.08)], price: 35, colors: _elec, styled: false),
  Family(id: 'el_uticnica2', name: 'Dvostruka utičnica', category: catElectric, shape: 'socket_double', sizes: [(0.15, 0.05, 0.08)], price: 50, colors: _elec, styled: false),
  Family(id: 'el_uticnica_v', name: 'Utičnica iznad radne ploče', category: catElectric, shape: 'socket_high', sizes: [(0.15, 0.05, 0.08)], price: 50, colors: _elec, styled: false),
  Family(id: 'el_prekidac', name: 'Prekidač', category: catElectric, shape: 'switch', sizes: [(0.08, 0.05, 0.08)], price: 30, colors: _elec, styled: false),
  Family(id: 'el_tv', name: 'TV / antenska utičnica', category: catElectric, shape: 'tv_socket', sizes: [(0.08, 0.05, 0.08)], price: 40, colors: _elec, styled: false),
  Family(id: 'el_lan', name: 'Mrežna utičnica (LAN)', category: catElectric, shape: 'lan_socket', sizes: [(0.08, 0.05, 0.08)], price: 45, colors: _elec, styled: false),
  Family(id: 'el_svjetlo', name: 'Rasvjetno mjesto (strop)', category: catElectric, shape: 'light_point', sizes: [(0.12, 0.12, 0.04)], price: 40, colors: _elec, styled: false),
  Family(id: 'stolna_lampa', name: 'Stolna lampa', category: catLight, shape: 'table_lamp', sizes: [(0.3, 0.3, 0.5), (0.4, 0.4, 0.62)], price: 35, colors: _shade, styled: false),
  Family(id: 'kamin', name: 'Kamin', category: catLiving, shape: 'fireplace', sizes: [(1.0, 0.45, 1.0), (1.2, 0.5, 1.1), (1.6, 0.5, 1.1)], price: 1500, colors: _stone, styled: false),
  Family(id: 'biljka', name: 'Sobna biljka', category: catLiving, shape: 'plant', sizes: [(0.4, 0.4, 0.8), (0.5, 0.5, 1.2), (0.7, 0.7, 1.7)], price: 40, colors: _green, styled: false),

  // ---------------------------------------------------------------- spavaća
  Family(id: 'bracni', name: 'Bračni krevet', category: catBed, shape: 'bed', sizes: [(1.46, 2.08, 1.0), (1.66, 2.1, 1.0), (1.86, 2.12, 1.05), (2.06, 2.12, 1.05)], price: 450, colors: _fabric, legVariants: true),
  Family(id: 'krevet', name: 'Krevet', category: catBed, shape: 'bed', sizes: [(0.96, 2.06, 0.9), (1.26, 2.06, 0.9)], price: 220, colors: _wood, legVariants: true),
  Family(id: 'nocni', name: 'Noćni ormarić', category: catBed, shape: 'dresser', sizes: [(0.4, 0.35, 0.45), (0.45, 0.4, 0.5), (0.5, 0.4, 0.55)], price: 60, colors: _wood, legVariants: true),
  Family(id: 'komoda', name: 'Komoda s ladicama', category: catBed, shape: 'dresser', sizes: [(0.8, 0.45, 0.8), (1.0, 0.48, 0.85), (1.2, 0.5, 0.9)], price: 180, colors: _wood, legVariants: true),
  Family(id: 'komoda_visoka', name: 'Visoka komoda', category: catBed, shape: 'dresser', sizes: [(0.8, 0.45, 1.2), (1.0, 0.48, 1.3)], price: 230, colors: _wood, legVariants: true),
  Family(id: 'ormar2', name: 'Ormar s dva krila', category: catBed, shape: 'wardrobe', sizes: [(1.0, 0.58, 2.0), (1.0, 0.6, 2.2)], price: 220, colors: _wood),
  Family(id: 'ormar3', name: 'Ormar s tri krila', category: catBed, shape: 'wardrobe', sizes: [(1.5, 0.6, 2.2), (1.5, 0.6, 2.36)], price: 350, colors: _wood),
  Family(id: 'ormar4', name: 'Ormar s četiri krila', category: catBed, shape: 'wardrobe', sizes: [(2.0, 0.6, 2.2), (2.0, 0.6, 2.36)], price: 480, colors: _wood),
  Family(id: 'ormar_klizni', name: 'Ormar s kliznim vratima', category: catBed, shape: 'wardrobe', sizes: [(1.8, 0.65, 2.2), (2.2, 0.65, 2.3), (2.5, 0.65, 2.36)], price: 600, colors: _wood),
  Family(id: 'toaletni', name: 'Toaletni stolić', category: catBed, shape: 'table', sizes: [(1.0, 0.45, 0.75), (1.2, 0.45, 0.76)], price: 150, colors: _wood, legVariants: true),
  Family(id: 'klupa_krevet', name: 'Klupa za kraj kreveta', category: catBed, shape: 'bench', sizes: [(1.2, 0.4, 0.45), (1.4, 0.4, 0.45)], price: 120, colors: _fabric),

  // ---------------------------------------------------------------- kuhinja
  Family(id: 'kuhinja', name: 'Kuhinjski blok', category: catKitchen, shape: 'kitchen', sizes: [(1.8, 0.6, 2.2), (2.4, 0.6, 2.2), (3.0, 0.6, 2.2), (3.6, 0.6, 2.2), (4.2, 0.6, 2.2)], price: 1700, colors: _fronts),
  Family(id: 'donji', name: 'Donji kuhinjski element', category: catKitchen, shape: 'kitchen', sizes: [(0.3, 0.6, 0.9), (0.4, 0.6, 0.9), (0.6, 0.6, 0.9), (0.8, 0.6, 0.9), (1.0, 0.6, 0.9), (1.2, 0.6, 0.9)], price: 150, colors: _fronts),
  Family(id: 'visoki', name: 'Visoki kuhinjski element', category: catKitchen, shape: 'tall', sizes: [(0.6, 0.6, 2.2)], price: 400, colors: _fronts),
  Family(id: 'otok', name: 'Kuhinjski otok', category: catKitchen, shape: 'island', sizes: [(1.2, 0.9, 0.92), (1.8, 0.9, 0.92), (2.4, 1.0, 0.92)], price: 1000, colors: _fronts),
  Family(id: 'stol', name: 'Blagovaonski stol', category: catKitchen, shape: 'table', sizes: [(1.2, 0.8, 0.75), (1.4, 0.85, 0.75), (1.6, 0.9, 0.75), (1.8, 0.9, 0.75), (2.0, 1.0, 0.76), (2.4, 1.0, 0.76)], price: 300, colors: _wood, legVariants: true),
  Family(id: 'stol_okrugli', name: 'Okrugli blagovaonski stol', category: catKitchen, shape: 'table_round', sizes: [(0.9, 0.9, 0.75), (1.1, 1.1, 0.75), (1.3, 1.3, 0.75)], price: 250, colors: _wood),
  Family(id: 'stolica', name: 'Stolica', category: catKitchen, shape: 'chair', sizes: [(0.44, 0.5, 0.88), (0.46, 0.52, 0.9)], price: 70, colors: _wood, legVariants: true),
  Family(id: 'stolica_tap', name: 'Tapecirana stolica', category: catKitchen, shape: 'chair', sizes: [(0.48, 0.55, 0.88), (0.52, 0.58, 0.82)], price: 90, colors: _fabric, legVariants: true),
  Family(id: 'barski_stol', name: 'Barski stol', category: catKitchen, shape: 'table', sizes: [(1.2, 0.6, 1.05), (1.6, 0.7, 1.05)], price: 260, colors: _wood, legVariants: true),
  Family(id: 'barska', name: 'Barska stolica', category: catKitchen, shape: 'stool', sizes: [(0.38, 0.38, 0.65), (0.4, 0.4, 0.75)], price: 80, colors: _wood),
  Family(id: 'klupa', name: 'Klupa za blagovaonu', category: catKitchen, shape: 'bench', sizes: [(1.2, 0.38, 0.46), (1.6, 0.38, 0.46)], price: 140, colors: _wood),
  Family(id: 'hladnjak', name: 'Hladnjak', category: catKitchen, shape: 'fridge', sizes: [(0.55, 0.6, 1.45), (0.6, 0.65, 1.85), (0.6, 0.65, 2.0)], price: 450, colors: _appliance, styled: false),
  Family(id: 'hladnjak_sbs', name: 'Hladnjak side-by-side', category: catKitchen, shape: 'fridge', sizes: [(0.9, 0.7, 1.78)], price: 1300, colors: _appliance, styled: false),
  Family(id: 'stednjak', name: 'Štednjak', category: catKitchen, shape: 'stove', sizes: [(0.5, 0.6, 0.85), (0.6, 0.6, 0.85), (0.9, 0.6, 0.9)], price: 350, colors: _appliance, styled: false),
  Family(id: 'perilica_posuda', name: 'Perilica posuđa', category: catKitchen, shape: 'dishwasher', sizes: [(0.45, 0.6, 0.85), (0.6, 0.6, 0.85)], price: 400, colors: _appliance, styled: false),

  // ---------------------------------------------------------------- kupaonica
  Family(id: 'kada', name: 'Kada', category: catBath, shape: 'bath', sizes: [(1.5, 0.7, 0.58), (1.6, 0.7, 0.6), (1.7, 0.75, 0.6), (1.8, 0.8, 0.6)], price: 350, colors: _sanitary, styled: false),
  Family(id: 'tus', name: 'Tuš kabina', category: catBath, shape: 'shower', sizes: [(0.8, 0.8, 2.0), (0.9, 0.9, 2.0), (1.0, 1.0, 2.0), (1.2, 0.9, 2.0)], price: 400, colors: _metalFinish, styled: false),
  Family(id: 'wc', name: 'WC školjka', category: catBath, shape: 'toilet', sizes: [(0.36, 0.52, 0.8), (0.38, 0.65, 0.8)], price: 180, colors: _sanitary, styled: false),
  Family(id: 'umivaonik', name: 'Umivaonik s ormarićem', category: catBath, shape: 'vanity', sizes: [(0.6, 0.46, 0.85), (0.8, 0.46, 0.85), (1.0, 0.46, 0.85), (1.2, 0.46, 0.85)], price: 250, colors: _fronts),
  Family(id: 'kup_ormaric', name: 'Visoki kupaonski ormarić', category: catBath, shape: 'tall', sizes: [(0.35, 0.3, 1.6), (0.4, 0.35, 1.8)], price: 150, colors: _fronts),
  Family(id: 'perilica', name: 'Perilica rublja', category: catBath, shape: 'washer', sizes: [(0.6, 0.6, 0.85)], price: 400, colors: _appliance, styled: false),
  Family(id: 'susilica', name: 'Sušilica rublja', category: catBath, shape: 'washer', sizes: [(0.6, 0.62, 0.85)], price: 500, colors: _appliance, styled: false),

  // ---------------------------------------------------------------- rad i djeca
  Family(id: 'radni_stol', name: 'Radni stol', category: catWork, shape: 'table', sizes: [(1.0, 0.6, 0.75), (1.2, 0.6, 0.75), (1.4, 0.7, 0.75), (1.6, 0.8, 0.75)], price: 150, colors: _wood, legVariants: true),
  Family(id: 'uredska', name: 'Uredska stolica', category: catWork, shape: 'chair', sizes: [(0.6, 0.6, 1.05), (0.65, 0.65, 1.2)], price: 120, colors: _fabric),
  Family(id: 'kat', name: 'Krevet na kat', category: catWork, shape: 'bunk', sizes: [(0.98, 2.08, 1.6), (0.98, 2.08, 1.7)], price: 350, colors: _wood),
  Family(id: 'krevetic', name: 'Dječji krevetić', category: catWork, shape: 'crib', sizes: [(0.66, 1.26, 0.9), (0.76, 1.46, 0.9)], price: 150, colors: _wood),
  Family(id: 'igracke', name: 'Polica za igračke', category: catWork, shape: 'shelf', sizes: [(0.8, 0.35, 0.8), (1.2, 0.35, 0.9)], price: 70, colors: _wood),

  // ---------------------------------------------------------------- predsoblje
  Family(id: 'cipelarnik', name: 'Ormarić za cipele', category: catHall, shape: 'dresser', sizes: [(0.6, 0.3, 1.0), (0.8, 0.3, 1.0), (1.0, 0.3, 1.1)], price: 100, colors: _wood),
  Family(id: 'garderober', name: 'Garderober', category: catHall, shape: 'wardrobe', sizes: [(0.8, 0.4, 1.9), (1.2, 0.4, 2.0)], price: 220, colors: _wood),
  Family(id: 'klupa_hodnik', name: 'Klupa za predsoblje', category: catHall, shape: 'bench', sizes: [(0.8, 0.35, 0.48), (1.0, 0.38, 0.48)], price: 90, colors: _wood),
  Family(id: 'stube', name: 'Stubište, ravno', category: catHall, shape: 'stairs', sizes: [(0.9, 3.2, 2.6), (1.0, 3.6, 2.8), (1.2, 4.0, 3.0)], price: 3000, colors: _wood, styled: false),
  Family(id: 'stube_l', name: 'Stubište, L s podestom', category: catHall, shape: 'stairs_l', sizes: [(2.2, 2.6, 2.6), (2.4, 2.9, 2.8), (2.6, 3.1, 3.0)], price: 4200, colors: _wood, styled: false),
  Family(id: 'stube_spiral', name: 'Stubište, zavojito', category: catHall, shape: 'stairs_spiral', sizes: [(1.6, 1.6, 2.6), (1.8, 1.8, 2.8), (2.0, 2.0, 3.0)], price: 3800, colors: _wood, styled: false),

  // ---------------------------------------------------------------- vrt i terasa
  Family(id: 'vrtni_stol', name: 'Vrtni stol', category: catGarden, shape: 'table', sizes: [(0.8, 0.8, 0.74), (1.4, 0.8, 0.74), (2.0, 0.9, 0.74)], price: 200, colors: _outdoor, zone: _e, styled: false),
  Family(id: 'vrtna_stolica', name: 'Vrtna stolica', category: catGarden, shape: 'chair', sizes: [(0.55, 0.6, 0.85)], price: 50, colors: _outdoor, zone: _e, styled: false),
  Family(id: 'vrtna_sofa', name: 'Vrtna sofa', category: catGarden, shape: 'sofa', sizes: [(1.4, 0.8, 0.75), (2.0, 0.85, 0.75)], price: 450, colors: _outdoor, zone: _e, styled: false),
  Family(id: 'lezaljka', name: 'Ležaljka', category: catGarden, shape: 'lounger', sizes: [(0.7, 1.9, 0.4)], price: 120, colors: _outdoor, zone: _e, styled: false),
  Family(id: 'suncobran', name: 'Suncobran', category: catGarden, shape: 'umbrella', sizes: [(2.0, 2.0, 2.3), (2.5, 2.5, 2.4), (3.0, 3.0, 2.5)], price: 100, colors: _shade, zone: _e, styled: false),
  Family(id: 'rostilj', name: 'Roštilj', category: catGarden, shape: 'grill', sizes: [(0.8, 0.5, 1.05), (1.2, 0.6, 1.1), (1.5, 0.65, 1.15)], price: 300, colors: _appliance, zone: _e, styled: false),
  Family(id: 'bazen', name: 'Bazen', category: catGarden, shape: 'pool', sizes: [(5, 3, 0.3), (6, 3, 0.3), (8, 4, 0.3), (10, 5, 0.3)], price: 12000, colors: _pool, zone: _e, styled: false),
  Family(id: 'terasa', name: 'Terasa od dasaka', category: catGarden, shape: 'deck', sizes: [(3, 2, 0.12), (4, 3, 0.12), (5, 4, 0.12), (6, 4, 0.12)], price: 1000, colors: _wood, zone: _e, styled: false),
  Family(id: 'balkon', name: 'Balkon, staklena ograda', category: catGarden, shape: 'balcony', sizes: [(2.0, 1.2, 1.0), (3.0, 1.5, 1.0), (4.0, 1.8, 1.0), (5.0, 2.0, 1.0)], price: 2400, colors: _stone, zone: _e, styled: false),
  Family(id: 'balkon_metal', name: 'Balkon, metalna ograda', category: catGarden, shape: 'balcony_rail', sizes: [(2.0, 1.2, 1.0), (3.0, 1.5, 1.0), (4.0, 1.8, 1.0), (5.0, 2.0, 1.0)], price: 1800, colors: _stone, zone: _e, styled: false),
  Family(id: 'balkon_zid', name: 'Balkon, zidana ograda', category: catGarden, shape: 'balcony_wall', sizes: [(2.0, 1.2, 1.0), (3.0, 1.5, 1.0), (4.0, 1.8, 1.0), (5.0, 2.0, 1.0)], price: 2000, colors: _stone, zone: _e, styled: false),
  Family(id: 'gredica', name: 'Gredica s cvijećem', category: catGarden, shape: 'flowerbed', sizes: [(1.2, 0.6, 0.4), (2.0, 0.8, 0.4), (3.0, 1.0, 0.4)], price: 120, colors: _stone, zone: _e, styled: false),

  // ---------------------------------------------------------------- dvorište
  Family(id: 'stablo', name: 'Stablo', category: catYard, shape: 'tree', sizes: [(1.5, 1.5, 3.0), (2.0, 2.0, 4.0), (3.0, 3.0, 6.0), (4.0, 4.0, 8.0)], price: 120, colors: _green, zone: _e, styled: false),
  Family(id: 'cempres', name: 'Čempres', category: catYard, shape: 'cypress', sizes: [(0.7, 0.7, 3.0), (0.9, 0.9, 5.0)], price: 80, colors: _green, zone: _e, styled: false),
  Family(id: 'zivica', name: 'Živica', category: catYard, shape: 'hedge', sizes: [(1.0, 0.5, 1.0), (2.0, 0.6, 1.4), (3.0, 0.7, 1.8)], price: 60, colors: _green, zone: _e, styled: false),
  Family(id: 'ograda', name: 'Ograda', category: catYard, shape: 'fence', sizes: [(2.0, 0.06, 1.0), (3.0, 0.06, 1.2), (3.0, 0.06, 1.8)], price: 120, colors: _outdoor, zone: _e, styled: false),
  Family(id: 'staza', name: 'Staza od ploča', category: catYard, shape: 'path', sizes: [(1.0, 3.0, 0.02), (1.0, 5.0, 0.02), (1.2, 6.0, 0.02)], price: 150, colors: _stone, zone: _e, styled: false),
  Family(id: 'prilaz', name: 'Prilaz za auto', category: catYard, shape: 'path', sizes: [(3.0, 6.0, 0.02), (3.5, 8.0, 0.02)], price: 1500, colors: _stone, zone: _e, styled: false),
  Family(id: 'nadstresnica', name: 'Nadstrešnica za auto', category: catYard, shape: 'carport', sizes: [(3.0, 5.5, 2.4), (6.0, 5.5, 2.4)], price: 2500, colors: _outdoor, zone: _e, styled: false),
  Family(id: 'kucica', name: 'Vrtna kućica', category: catYard, shape: 'shed', sizes: [(2.0, 2.0, 2.2), (2.5, 2.0, 2.3), (3.0, 2.5, 2.4)], price: 900, colors: _wood, zone: _e, styled: false),
  Family(id: 'trampolin', name: 'Trampolin', category: catYard, shape: 'trampoline', sizes: [(2.4, 2.4, 0.8), (3.0, 3.0, 0.9), (3.7, 3.7, 0.95)], price: 250, colors: _outdoor, zone: _e, styled: false),
  Family(id: 'ljuljacka', name: 'Ljuljačka', category: catYard, shape: 'swing', sizes: [(2.2, 1.6, 2.1)], price: 220, colors: _wood, zone: _e, styled: false),
  Family(id: 'auto', name: 'Automobil', category: catYard, shape: 'car', sizes: [(1.8, 4.2, 1.45), (1.85, 4.6, 1.5), (1.9, 4.9, 1.7)], price: 0, colors: _car, zone: _e, styled: false),
];

/// Model = vrsta u jednom stilu (npr. "Trosjed Učka"); ima više varijanti.
class CatalogModel {
  CatalogModel(this.id, this.family, this.style, this.variants);
  final String id;
  final Family family;
  final Style? style;
  final List<CatalogItem> variants;

  String get name => style == null ? family.name : '${family.name} ${style!.series}';
  /// Zadana varijanta za prikaz (druga veličina ako postoji, prva boja).
  CatalogItem get main => variants[(family.sizes.length > 1 ? 1 : 0) * (variants.length ~/ family.sizes.length)];
  String get category => family.category;
  CatalogZone get zone => family.zone;
  double get minPrice => variants.map((v) => v.price ?? 0).reduce((a, b) => a < b ? a : b);
}

double _round9(double v) {
  if (v <= 0) return 0;
  if (v < 100) return (v / 5).round() * 5 - 1;
  return (v / 10).round() * 10 - 1;
}

String _sizeLabel(Family f, (double, double, double) s) {
  final w = (s.$1 * 100).round(), d = (s.$2 * 100).round();
  return switch (f.shape) {
    'bed' || 'bunk' || 'crib' => '${w - 6} × ${d - 8}',
    'rug' || 'path' || 'deck' || 'pool' || 'balcony' || 'balcony_rail' || 'balcony_wall' || 'kitchen' when f.id != 'donji' => '$w × $d',
    'table_round' || 'rug_round' || 'tree' || 'trampoline' || 'umbrella' => 'Ø $w',
    _ => '$w cm',
  };
}

List<CatalogModel> _buildModels() {
  final models = <CatalogModel>[];
  for (final f in families) {
    final styleList = f.styled ? styles.cast<Style?>() : const <Style?>[null];
    for (final st in styleList) {
      final variants = <CatalogItem>[];
      final legs = f.legVariants ? _legOptions : <(String, String)>[(st?.legs ?? 'wood', '')];
      for (var si = 0; si < f.sizes.length; si++) {
        final s = f.sizes[si];
        final sizeFactor = (s.$1 * s.$2) / (f.sizes.first.$1 * f.sizes.first.$2);
        for (var ci = 0; ci < f.colors.length; ci++) {
          final col = f.colors[ci];
          for (var li = 0; li < legs.length; li++) {
            final (legId, legName) = legs[li];
            final id = 'g:${f.id}:${st?.id ?? '-'}:$si:$ci:$li';
            final price = _round9(f.price * (0.75 + 0.25 * sizeFactor) * (st?.priceFactor ?? 1) * (legId == 'metal' ? 1.05 : 1));
            final parts = [_sizeLabel(f, s), col.name, if (legName.isNotEmpty) legName];
            variants.add(CatalogItem(
              id: id,
              name: '${st == null ? f.name : '${f.name} ${st.series}'} ${_sizeLabel(f, s)}',
              category: f.category,
              zone: f.zone,
              shape: f.shape,
              w: s.$1,
              d: s.$2,
              h: s.$3,
              color: col.color,
              price: price > 0 ? price : null,
              style: st?.id,
              legs: legId,
              modelId: '${f.id}:${st?.id ?? '-'}',
              variant: parts.join(', '),
            ));
          }
        }
      }
      models.add(CatalogModel('${f.id}:${st?.id ?? '-'}', f, st, variants));
    }
  }
  return models;
}

/// Svi modeli (generirani jednom, pri prvom pristupu).
final List<CatalogModel> catalogModels = _buildModels();

/// Sve varijante.
final List<CatalogItem> catalog = [for (final m in catalogModels) ...m.variants];

final Map<String, CatalogItem> _byId = {
  for (final c in legacyCatalog) c.id: c,
  for (final c in catalog) c.id: c,
};

/// Uvezeni proizvodi trgovina (postavlja ih ImportedCatalog).
final Map<String, CatalogItem> importedById = {};

/// Stvarni proizvodi trgovina (IKEA, JYSK, Emmezeta) – postavlja ih RetailCatalog.
final Map<String, CatalogItem> retailById = {};

CatalogItem? catalogById(String id) => _byId[id] ?? retailById[id] ?? importedById[id];

int get variantCount => catalog.length;
