/// Podne obloge i boje zidova. [texture] određuje proceduralnu teksturu u 3D-u.
class FloorMaterial {
  const FloorMaterial({
    required this.id,
    required this.name,
    required this.color,
    required this.texture,
    required this.pricePerM2,
  });

  final String id;
  final String name;
  final int color;

  /// wood | tile | largeTile | stone | concrete | carpet | plain
  final String texture;
  final double pricePerM2; // okvirno, materijal + ugradnja (€)
}

const floorMaterials = <FloorMaterial>[
  FloorMaterial(id: 'parket_hrast', name: 'Parket, hrast', color: 0xFFB98B5E, texture: 'wood', pricePerM2: 55),
  FloorMaterial(id: 'parket_orah', name: 'Parket, orah', color: 0xFF7A5236, texture: 'wood', pricePerM2: 70),
  FloorMaterial(id: 'laminat_svijetli', name: 'Laminat, svijetli', color: 0xFFD8C3A0, texture: 'wood', pricePerM2: 25),
  FloorMaterial(id: 'laminat_sivi', name: 'Laminat, sivi', color: 0xFFA9A39A, texture: 'wood', pricePerM2: 25),
  FloorMaterial(id: 'plocice_bijele', name: 'Pločice 30×30, bijele', color: 0xFFEDEBE6, texture: 'tile', pricePerM2: 35),
  FloorMaterial(id: 'plocice_sive', name: 'Pločice 60×60, sive', color: 0xFFA6A8A6, texture: 'largeTile', pricePerM2: 45),
  FloorMaterial(id: 'plocice_tamne', name: 'Pločice 60×60, antracit', color: 0xFF55585A, texture: 'largeTile', pricePerM2: 45),
  FloorMaterial(id: 'kamen', name: 'Prirodni kamen', color: 0xFFC9C1B2, texture: 'stone', pricePerM2: 90),
  FloorMaterial(id: 'beton', name: 'Brušeni beton', color: 0xFFB3B1AC, texture: 'concrete', pricePerM2: 60),
  FloorMaterial(id: 'tepison', name: 'Tepison', color: 0xFF8C8F99, texture: 'carpet', pricePerM2: 20),
];

FloorMaterial floorById(String? id) =>
    floorMaterials.firstWhere((m) => m.id == id, orElse: () => floorMaterials.first);

class WallPaint {
  const WallPaint(this.name, this.color);
  final String name;
  final int color;
}

const wallPaints = <WallPaint>[
  WallPaint('Bijela', 0xFFF6F5F1),
  WallPaint('Topla bijela', 0xFFF1EBDD),
  WallPaint('Pješčana', 0xFFE3D5BD),
  WallPaint('Kadulja', 0xFFC2CCB4),
  WallPaint('Magla', 0xFFCBD5D9),
  WallPaint('Golublja siva', 0xFFB9B6AE),
  WallPaint('Teracota', 0xFFC98A6B),
  WallPaint('Ponoćna', 0xFF3E4A5A),
];

/// Obloga zidova prostorije (pločice, drvo, cigla…). 'paint' = samo boja.
class WallFinish {
  const WallFinish({required this.id, required this.name, required this.color, required this.texture, required this.pricePerM2});
  final String id;
  final String name;
  final int color;

  /// Ime teksture u 3D engineu (null = glatka boja).
  final String? texture;
  final double pricePerM2;
}

const wallFinishes = <WallFinish>[
  WallFinish(id: 'paint', name: 'Boja', color: 0xFFF6F5F1, texture: null, pricePerM2: paintPricePerM2),
  WallFinish(id: 'tile_white', name: 'Pločice 20×20, bijele', color: 0xFFF6F6F4, texture: 'wallTile', pricePerM2: 38),
  WallFinish(id: 'tile_metro', name: 'Metro pločice', color: 0xFFF4F4F1, texture: 'metroTile', pricePerM2: 42),
  WallFinish(id: 'tile_grey', name: 'Pločice 30×60, sive', color: 0xFFB4B5B2, texture: 'wallTileL', pricePerM2: 40),
  WallFinish(id: 'tile_green', name: 'Pločice 20×20, zelene', color: 0xFF8FA595, texture: 'wallTile', pricePerM2: 45),
  WallFinish(id: 'wood', name: 'Drvena obloga', color: 0xFFC49A6C, texture: 'woodPanel', pricePerM2: 60),
  WallFinish(id: 'brick', name: 'Cigla', color: 0xFFFFFFFF, texture: 'brick', pricePerM2: 65),
  WallFinish(id: 'concrete', name: 'Dekorativni beton', color: 0xFFB9B7B1, texture: 'concrete', pricePerM2: 32),
  WallFinish(id: 'wallpaper', name: 'Tapeta', color: 0xFFE6DCCB, texture: 'wallpaper', pricePerM2: 18),
];

WallFinish finishById(String? id) => wallFinishes.firstWhere((f) => f.id == id, orElse: () => wallFinishes.first);

/// Okvirne jedinične cijene za troškovnik (€).
const paintPricePerM2 = 6.0; // boja + rad, dva sloja
const litersPerM2 = 0.25; // dva sloja
