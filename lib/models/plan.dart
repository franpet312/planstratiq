import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Sve mjere u modelu su u METRIMA. Koordinatni sustav tlocrta:
/// x = desno, y = dolje (kao na papiru). U 3D-u se y tlocrta mapira na os z.

final _rnd = math.Random();
int _seq = 0;

String newId(String prefix) {
  _seq++;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_seq.toRadixString(36)}${_rnd.nextInt(1 << 16).toRadixString(36)}';
}

double _r3(double v) => (v * 1000).roundToDouble() / 1000;
double _d(dynamic v, double fallback) => v is num ? v.toDouble() : fallback;
int _i(dynamic v, int fallback) => v is num ? v.toInt() : fallback;
bool _b(dynamic v) => v == true;

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) => v is List
    ? v.map((e) => f(Map<String, dynamic>.from(e as Map))).toList()
    : <T>[];

/// Točka (čvor) u kojoj se spajaju zidovi. Zidovi dijele čvorove, pa kad
/// pomakneš jedan zid, spojeni zidovi se automatski prilagode.
class PlanNode {
  PlanNode(this.id, this.pos);
  final String id;
  Offset pos;

  Map<String, dynamic> toJson() => {'id': id, 'x': _r3(pos.dx), 'y': _r3(pos.dy)};
  factory PlanNode.fromJson(Map<String, dynamic> j) =>
      PlanNode(j['id'] as String, Offset(_d(j['x'], 0), _d(j['y'], 0)));
}

class Wall {
  Wall({
    required this.id,
    required this.a,
    required this.b,
    this.thickness = 0.2,
    this.height = 2.6,
    this.color = 0xFFF6F5F1,
  });

  final String id;
  String a;
  String b;
  double thickness;
  double height;
  int color;

  Wall copyWith({required String id, String? a, String? b}) => Wall(
      id: id, a: a ?? this.a, b: b ?? this.b, thickness: thickness, height: height, color: color);

  Map<String, dynamic> toJson() =>
      {'id': id, 'a': a, 'b': b, 'thickness': thickness, 'height': height, 'color': color};

  factory Wall.fromJson(Map<String, dynamic> j) => Wall(
        id: j['id'] as String,
        a: j['a'] as String,
        b: j['b'] as String,
        thickness: _d(j['thickness'], 0.2),
        height: _d(j['height'], 2.6),
        color: _i(j['color'], 0xFFF6F5F1),
      );
}

enum OpeningType { door, window, balcony, passage }

extension OpeningTypeX on OpeningType {
  String get label => switch (this) {
        OpeningType.door => 'Vrata',
        OpeningType.window => 'Prozor',
        OpeningType.balcony => 'Balkonska vrata',
        OpeningType.passage => 'Prolaz',
      };

  /// Može li se kroz otvor proći (za šetnju u 3D-u).
  bool get walkable => this != OpeningType.window;
}

/// Vrata, prozor ili prolaz na zidu. [t] je položaj središta duž zida (0..1).
class Opening {
  Opening({
    required this.id,
    required this.wallId,
    required this.type,
    required this.t,
    required this.width,
    required this.height,
    required this.sill,
    this.flip = false,
    this.swingOut = false,
    this.style = '',
    this.shade = '',
    this.shadeColor,
  });

  factory Opening.preset(String wallId, OpeningType type, double t) {
    final (w, h, s) = switch (type) {
      OpeningType.door => (0.9, 2.05, 0.0),
      OpeningType.window => (1.2, 1.4, 0.9),
      OpeningType.balcony => (1.8, 2.2, 0.0),
      OpeningType.passage => (1.2, 2.2, 0.0),
    };
    return Opening(id: newId('o'), wallId: wallId, type: type, t: t, width: w, height: h, sill: s);
  }

  final String id;
  String wallId;
  OpeningType type;
  double t;
  double width;
  double height;
  double sill;

  /// Šarke na drugoj strani.
  bool flip;

  /// Otvaraju se na drugu stranu zida.
  bool swingOut;

  /// Izvedba: vrata single|double|sliding|pocket|folding, prozor casement|fixed|sliding,
  /// balkonska vrata casement|sliding. Prazno = uobičajena izvedba.
  String style;

  /// Zaštita od sunca (prozori, balkonska vrata): '' | 'skure' | 'roleta'.
  String shade;
  int? shadeColor;

  Map<String, dynamic> toJson() => {
        'id': id,
        'wallId': wallId,
        'type': type.name,
        't': _r3(t),
        'width': width,
        'height': height,
        'sill': sill,
        'flip': flip,
        'swingOut': swingOut,
        if (style.isNotEmpty) 'style': style,
        if (shade.isNotEmpty) 'shade': shade,
        if (shadeColor != null) 'shadeColor': shadeColor,
      };

  factory Opening.fromJson(Map<String, dynamic> j) => Opening(
        id: j['id'] as String,
        wallId: j['wallId'] as String,
        type: OpeningType.values.firstWhere((e) => e.name == j['type'], orElse: () => OpeningType.door),
        t: _d(j['t'], 0.5),
        width: _d(j['width'], 0.9),
        height: _d(j['height'], 2.05),
        sill: _d(j['sill'], 0),
        flip: _b(j['flip']),
        swingOut: _b(j['swingOut']),
        style: (j['style'] as String?) ?? '',
        shade: (j['shade'] as String?) ?? '',
        shadeColor: (j['shadeColor'] as num?)?.toInt(),
      );
}

/// Prostorija – automatski se prepoznaje iz zatvorenih zidova.
class Room {
  Room({
    required this.id,
    required this.name,
    required this.nodeIds,
    this.floor = 'parket_hrast',
    this.wallFinish = 'paint',
    this.wallColor,
    this.finishHeight = 0,
    this.floorHeating = false,
  });

  final String id;
  String name;
  List<String> nodeIds;
  String floor;

  /// Obloga zidova u prostoriji (id iz [wallFinishes]); 'paint' = samo boja.
  String wallFinish;

  /// Boja zidova u prostoriji (null = boja samog zida).
  int? wallColor;

  /// Visina obloge (m); 0 = cijeli zid. Iznad obloge je boja.
  double finishHeight;

  /// Podno grijanje u prostoriji.
  bool floorHeating;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nodeIds': nodeIds,
        'floor': floor,
        if (wallFinish != 'paint') 'wallFinish': wallFinish,
        if (wallColor != null) 'wallColor': wallColor,
        if (finishHeight > 0) 'finishHeight': finishHeight,
        if (floorHeating) 'floorHeating': true,
      };

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Prostorija',
        nodeIds: List<String>.from(j['nodeIds'] as List),
        floor: (j['floor'] as String?) ?? 'parket_hrast',
        wallFinish: (j['wallFinish'] as String?) ?? 'paint',
        wallColor: j['wallColor'] is int ? j['wallColor'] as int : null,
        finishHeight: (j['finishHeight'] as num?)?.toDouble() ?? 0,
        floorHeating: j['floorHeating'] == true,
      );
}

/// Komad namještaja ili vanjski objekt postavljen u projekt.
class PlacedItem {
  PlacedItem({
    required this.id,
    required this.catalogId,
    required this.name,
    required this.shape,
    required this.pos,
    this.rotation = 0,
    required this.w,
    required this.d,
    required this.h,
    required this.color,
    this.price,
    this.modelUrl,
    this.retailer,
    this.style,
    this.legs,
    this.productUrl,
  });

  final String id;
  final String catalogId;
  String name;
  final String shape;
  Offset pos;

  /// Rotacija u radijanima (u smjeru kazaljke na tlocrtu).
  double rotation;
  double w;
  double d;
  double h;
  int color;
  double? price;
  final String? modelUrl;
  final String? retailer;
  final String? style;
  final String? legs;
  final String? productUrl;

  Map<String, dynamic> toJson() => {
        'id': id,
        'catalogId': catalogId,
        'name': name,
        'shape': shape,
        'x': _r3(pos.dx),
        'y': _r3(pos.dy),
        'rotation': _r3(rotation),
        'w': w,
        'd': d,
        'h': h,
        'color': color,
        if (price != null) 'price': price,
        if (modelUrl != null) 'modelUrl': modelUrl,
        if (retailer != null) 'retailer': retailer,
        if (style != null) 'style': style,
        if (legs != null) 'legs': legs,
        if (productUrl != null) 'productUrl': productUrl,
      };

  factory PlacedItem.fromJson(Map<String, dynamic> j) => PlacedItem(
        id: j['id'] as String,
        catalogId: (j['catalogId'] as String?) ?? '',
        name: (j['name'] as String?) ?? 'Objekt',
        shape: (j['shape'] as String?) ?? 'box',
        pos: Offset(_d(j['x'], 0), _d(j['y'], 0)),
        rotation: _d(j['rotation'], 0),
        w: _d(j['w'], 1),
        d: _d(j['d'], 1),
        h: _d(j['h'], 1),
        color: _i(j['color'], 0xFFCCCCCC),
        price: j['price'] is num ? (j['price'] as num).toDouble() : null,
        modelUrl: j['modelUrl'] as String?,
        retailer: j['retailer'] as String?,
        style: j['style'] as String?,
        legs: j['legs'] as String?,
        productUrl: j['productUrl'] as String?,
      );
}

/// Učitani nacrt (slika) kao podloga za precrtavanje.
class PlanImage {
  PlanImage({
    required this.dataUrl,
    required this.origin,
    required this.metersPerPixel,
    required this.widthPx,
    required this.heightPx,
    this.opacity = 0.55,
  });

  final String dataUrl;
  Offset origin;
  double metersPerPixel;
  final int widthPx;
  final int heightPx;
  double opacity;

  Map<String, dynamic> toJson() => {
        'dataUrl': dataUrl,
        'x': origin.dx,
        'y': origin.dy,
        'metersPerPixel': metersPerPixel,
        'widthPx': widthPx,
        'heightPx': heightPx,
        'opacity': opacity,
      };

  factory PlanImage.fromJson(Map<String, dynamic> j) => PlanImage(
        dataUrl: j['dataUrl'] as String,
        origin: Offset(_d(j['x'], 0), _d(j['y'], 0)),
        metersPerPixel: _d(j['metersPerPixel'], 0.01),
        widthPx: _i(j['widthPx'], 1000),
        heightPx: _i(j['heightPx'], 1000),
        opacity: _d(j['opacity'], 0.55),
      );
}

/// Jedna etaža zgrade (podrum, prizemlje, kat…): vlastiti zidovi, otvori, prostorije i namještaj.
class Level {
  Level({
    required this.id,
    this.name = 'Prizemlje',
    this.elevation = 0,
    this.height = 2.6,
    this.attic = false,
    this.kneeWall = 1.2,
    Map<String, PlanNode>? nodes,
    List<Wall>? walls,
    List<Opening>? openings,
    List<Room>? rooms,
    List<PlacedItem>? items,
    List<Note>? notes,
    this.image,
  })  : nodes = nodes ?? {},
        walls = walls ?? [],
        openings = openings ?? [],
        rooms = rooms ?? [],
        items = items ?? [],
        notes = notes ?? [];

  final String id;
  String name;

  /// Visina gotovog poda iznad terena (m); podrum je ispod nule.
  double elevation;

  /// Zadana visina zidova (svijetla visina etaže).
  double height;

  /// Potkrovlje: krov počinje na vrhu koljenskog zida, strop je kosi (ispod krova).
  bool attic;

  /// Visina koljenskog (nadozida) u potkrovlju (m).
  double kneeWall;
  final Map<String, PlanNode> nodes;
  final List<Wall> walls;
  final List<Opening> openings;
  final List<Room> rooms;
  final List<PlacedItem> items;
  final List<Note> notes;
  PlanImage? image;

  bool get isEmpty => walls.isEmpty && items.isEmpty;

  Map<String, dynamic> toJson({bool includeImage = true}) => {
        'id': id,
        'name': name,
        'elevation': elevation,
        'wallHeight': height,
        if (attic) 'attic': true,
        if (attic) 'kneeWall': kneeWall,
        'nodes': nodes.values.map((n) => n.toJson()).toList(),
        'walls': walls.map((w) => w.toJson()).toList(),
        'openings': openings.map((o) => o.toJson()).toList(),
        'rooms': rooms.map((r) => r.toJson()).toList(),
        'items': items.map((i) => i.toJson()).toList(),
        if (notes.isNotEmpty) 'notes': notes.map((n) => n.toJson()).toList(),
        if (includeImage && image != null) 'image': image!.toJson(),
      };

  factory Level.fromJson(Map<String, dynamic> j, {String? fallbackId}) {
    final nodes = _list(j['nodes'], PlanNode.fromJson);
    return Level(
      id: (j['id'] as String?) ?? fallbackId ?? 'L0',
      name: (j['name'] as String?) ?? 'Prizemlje',
      elevation: _d(j['elevation'], 0),
      height: _d(j['wallHeight'], 2.6),
      attic: j['attic'] == true,
      kneeWall: _d(j['kneeWall'], 1.2),
      nodes: {for (final n in nodes) n.id: n},
      walls: _list(j['walls'], Wall.fromJson),
      openings: _list(j['openings'], Opening.fromJson),
      rooms: _list(j['rooms'], Room.fromJson),
      items: _list(j['items'], PlacedItem.fromJson),
      notes: _list(j['notes'], Note.fromJson),
      image: j['image'] is Map ? PlanImage.fromJson(Map<String, dynamic>.from(j['image'] as Map)) : null,
    );
  }
}

/// Debljina međukatne konstrukcije (m) – razmak od stropa jedne do poda sljedeće etaže.
const double slabThickness = 0.25;

/// Cijeli projekt: jedna ili više etaža. Polja nodes/walls/… odnose se na AKTIVNU etažu,
/// pa uređivač, crtanje i statistika rade s etažom koja je trenutno odabrana.
class Plan {
  Plan({
    this.name = 'Novi projekt',
    Map<String, PlanNode>? nodes,
    List<Wall>? walls,
    List<Opening>? openings,
    List<Room>? rooms,
    List<PlacedItem>? items,
    PlanImage? image,
    double wallHeight = 2.6,
    this.roof = false,
    List<Level>? levels,
    int active = 0,
  }) : levels = levels ??
            [
              Level(
                id: 'L0',
                nodes: nodes,
                walls: walls,
                openings: openings,
                rooms: rooms,
                items: items,
                image: image,
                height: wallHeight,
              )
            ] {
    this.active = active.clamp(0, this.levels.length - 1);
  }

  String name;

  /// Etaže poredane odozdo prema gore.
  final List<Level> levels;
  int active = 0;

  Level get level => levels[active];
  Map<String, PlanNode> get nodes => level.nodes;
  List<Wall> get walls => level.walls;
  List<Opening> get openings => level.openings;
  List<Room> get rooms => level.rooms;
  List<PlacedItem> get items => level.items;
  List<Note> get notes => level.notes;
  Note? noteById(String id) => notes.where((n) => n.id == id).firstOrNull;
  PlanImage? get image => level.image;
  set image(PlanImage? v) => level.image = v;

  /// Zadana visina novih zidova aktivne etaže.
  double get wallHeight => level.height;
  set wallHeight(double v) => level.height = v;

  /// Prikaži krov u 3D-u (na najvišoj etaži).
  bool roof;

  /// Oblik krova: 'gable' dvostrešni, 'hip' četverostrešni, 'shed' jednostrešni, 'flat' ravni.
  String roofType = 'gable';

  /// Nagib krovnih ploha u stupnjevima.
  double roofPitch = 30;

  /// Prepust krova preko zida (m).
  double roofOverhang = 0.5;

  /// Boja pokrova (ARGB).
  int roofColor = 0xFFA5533A;

  /// Zakreni sljeme za 90° (dvostrešni krov) ili smjer pada (jednostrešni).
  bool roofTurn = false;

  /// Parcela i okolina kuće.
  Site site = Site();

  /// Crta presjeka A–A na tlocrtu (zajednička svim etažama), ili null.
  SectionLine? section;

  /// Toplinska izolacija kuće (za okvirnu potrebnu snagu grijanja): new | good | average | poor.
  String insulation = 'good';

  /// Fasada: osnovna obloga (žbuka u boji, drvo, opeka…), donja zona prizemlja (cokl ili kamen)
  /// i obloga zabata/potkrovlja.
  String facadeKind = 'plaster';
  int facadeColor = 0xFFECE7DF;
  String baseKind = 'none';
  double baseHeight = 0.5;
  String gableKind = 'same';

  /// Klimatsko područje (za godišnju potrošnju): continental | coastal.
  String climate = 'continental';

  /// Grijanje: gas | heatpump | electric | wood | pellet | oil.
  String heatSource = 'gas';

  /// Etaža ispod aktivne (za prozirni prikaz na tlocrtu), ako postoji.
  Level? get levelBelow => active > 0 ? levels[active - 1] : null;

  /// Prizemlje: etaža s visinom najbližom nuli.
  int get groundIndex {
    var best = 0;
    for (var i = 1; i < levels.length; i++) {
      if (levels[i].elevation.abs() < levels[best].elevation.abs()) best = i;
    }
    return best;
  }

  /// Ponovno izračunaj visine etaža (prizemlje ostaje na svojoj visini).
  void restackLevels() {
    final g = groundIndex;
    for (var i = g + 1; i < levels.length; i++) {
      levels[i].elevation = levels[i - 1].elevation + levels[i - 1].height + slabThickness;
    }
    for (var i = g - 1; i >= 0; i--) {
      levels[i].elevation = levels[i + 1].elevation - levels[i].height - slabThickness;
    }
  }

  bool get isEmpty => levels.every((l) => l.isEmpty);

  Wall? wallById(String id) {
    for (final w in walls) {
      if (w.id == id) return w;
    }
    return null;
  }

  Opening? openingById(String id) {
    for (final o in openings) {
      if (o.id == id) return o;
    }
    return null;
  }

  Room? roomById(String id) {
    for (final r in rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  PlacedItem? itemById(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  Offset nodePos(String id) => nodes[id]?.pos ?? Offset.zero;

  double wallLength(Wall w) => (nodePos(w.b) - nodePos(w.a)).distance;

  List<Offset> roomPolygon(Room r) => [
        for (final id in r.nodeIds)
          if (nodes.containsKey(id)) nodes[id]!.pos
      ];

  Map<String, dynamic> toJson({bool includeImage = true}) => {
        'format': 'planstratiq',
        'version': 3,
        'name': name,
        'roof': roof,
        'roofStyle': {'type': roofType, 'pitch': roofPitch, 'overhang': roofOverhang, 'color': roofColor, 'turn': roofTurn},
        'site': site.toJson(),
        if (section != null) 'section': section!.toJson(),
        'insulation': insulation,
        'climate': climate,
        'facade': {'kind': facadeKind, 'color': facadeColor, 'base': baseKind, 'baseH': baseHeight, 'gable': gableKind},
        'heatSource': heatSource,
        'active': active,
        'levels': [for (final l in levels) l.toJson(includeImage: includeImage)],
      };

  factory Plan.fromJson(Map<String, dynamic> j) {
    final raw = j['levels'];
    final levels = raw is List && raw.isNotEmpty
        ? [
            for (var i = 0; i < raw.length; i++)
              if (raw[i] is Map) Level.fromJson(Map<String, dynamic>.from(raw[i] as Map), fallbackId: 'L$i')
          ]
        : [Level.fromJson(j, fallbackId: 'L0')..name = 'Prizemlje']; // stari format (jedna etaža)
    final plan = Plan(
      name: (j['name'] as String?) ?? 'Projekt',
      roof: _b(j['roof']),
      levels: levels.isEmpty ? null : levels,
      active: j['active'] is int ? j['active'] as int : 0,
    );
    final rs = j['roofStyle'];
    if (rs is Map) {
      const types = {'gable', 'hip', 'shed', 'flat'};
      if (types.contains(rs['type'])) plan.roofType = rs['type'] as String;
      if (rs['pitch'] is num) plan.roofPitch = (rs['pitch'] as num).toDouble().clamp(5, 60);
      if (rs['overhang'] is num) plan.roofOverhang = (rs['overhang'] as num).toDouble().clamp(0, 1.5);
      if (rs['color'] is int) plan.roofColor = rs['color'] as int;
      plan.roofTurn = _b(rs['turn']);
    }
    if (j['insulation'] is String) plan.insulation = j['insulation'] as String;
    if (j['climate'] is String) plan.climate = j['climate'] as String;
    if (j['facade'] is Map) {
      final f = j['facade'] as Map;
      plan.facadeKind = (f['kind'] as String?) ?? 'plaster';
      plan.facadeColor = (f['color'] as num?)?.toInt() ?? 0xFFECE7DF;
      plan.baseKind = (f['base'] as String?) ?? 'none';
      plan.baseHeight = _d(f['baseH'], 0.5);
      plan.gableKind = (f['gable'] as String?) ?? 'same';
    }
    if (j['heatSource'] is String) plan.heatSource = j['heatSource'] as String;
    if (j['site'] is Map) plan.site = Site.fromJson(Map<String, dynamic>.from(j['site'] as Map));
    if (j['section'] is Map) plan.section = SectionLine.fromJson(Map<String, dynamic>.from(j['section'] as Map));
    return plan;
  }

  Plan clone() => Plan.fromJson(toJson());
}


/// Parcela (pravokutnik oko kuće), ograda, ulica i okolni krajolik.
class Site {
  Site({
    this.width = 0,
    this.depth = 0,
    this.offsetX = 0,
    this.offsetY = 0,
    this.fence = 'wood',
    this.fenceHeight = 1.2,
    this.street = 'S',
    this.surroundings = 'suburb',
    this.driveway = true,
    this.slope = 0,
    this.slopeDir = 'street',
  });

  /// Širina (istok–zapad) i dubina (sjever–jug) parcele u m; 0 = automatski oko kuće.
  double width, depth;

  /// Pomak parcele u odnosu na sredinu kuće (m).
  double offsetX, offsetY;

  /// none | wood | metal | panel | hedge | wall
  String fence;
  double fenceHeight;

  /// Strana parcele na ulici: N, S, E, W (sjever je gore na tlocrtu).
  String street;

  /// none | suburb (susjedstvo) | countryside (selo, polja) | city (grad)
  String surroundings;

  /// Prilaz od ulaza u parcelu do kuće.
  bool driveway;

  /// Nagib terena u % (0 = ravno) i smjer pada: street | back | left | right (gledano s ulice).
  double slope;
  String slopeDir;

  Map<String, dynamic> toJson() => {
        'width': width,
        'depth': depth,
        'offsetX': offsetX,
        'offsetY': offsetY,
        'fence': fence,
        'fenceHeight': fenceHeight,
        'street': street,
        'surroundings': surroundings,
        'driveway': driveway,
        if (slope > 0) 'slope': slope,
        if (slope > 0) 'slopeDir': slopeDir,
      };

  factory Site.fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return Site(
      width: d('width', 0),
      depth: d('depth', 0),
      offsetX: d('offsetX', 0),
      offsetY: d('offsetY', 0),
      fence: (j['fence'] as String?) ?? 'wood',
      fenceHeight: d('fenceHeight', 1.2),
      street: (j['street'] as String?) ?? 'S',
      surroundings: (j['surroundings'] as String?) ?? 'suburb',
      driveway: j['driveway'] != false,
      slope: d('slope', 0),
      slopeDir: (j['slopeDir'] as String?) ?? 'street',
    );
  }
}


/// Vrste fasadne obloge.
const facadeKinds = <String, String>{
  'plaster': 'Žbuka (u boji)',
  'stone': 'Kamen',
  'brick': 'Fasadna opeka',
  'wood': 'Drvena obloga',
  'concrete': 'Vidljivi beton',
};

/// Izvedbe otvora po vrsti (id, naziv).
List<(String, String)> openingStyles(OpeningType t) => switch (t) {
      OpeningType.door => const [('', 'Krilna'), ('double', 'Dvokrilna'), ('sliding', 'Klizna'), ('pocket', 'Klizna u zid'), ('folding', 'Harmonika')],
      OpeningType.window => const [('', 'Krilni'), ('sliding', 'Klizni'), ('fixed', 'Fiksni')],
      OpeningType.balcony => const [('', 'Krilna'), ('sliding', 'Klizna stijena')],
      OpeningType.passage => const [],
    };


/// Crta presjeka: od [a] do [b]; pogled je prema lijevoj strani smjera a→b (ili desnoj ako je [flip]).
class SectionLine {
  SectionLine(this.a, this.b, {this.flip = false});
  Offset a, b;
  bool flip;

  /// Smjer pogleda (jedinični vektor u tlocrtu).
  Offset get view {
    final d = b - a;
    final l = d.distance;
    if (l < 1e-9) return const Offset(0, 1);
    final n = Offset(d.dy / l, -d.dx / l);
    return flip ? -n : n;
  }

  Map<String, dynamic> toJson() => {'ax': a.dx, 'ay': a.dy, 'bx': b.dx, 'by': b.dy, 'flip': flip};
  factory SectionLine.fromJson(Map<String, dynamic> j) =>
      SectionLine(Offset(_d(j['ax'], 0), _d(j['ay'], 0)), Offset(_d(j['bx'], 1), _d(j['by'], 0)), flip: j['flip'] == true);
}

/// Bilješka na tlocrtu (npr. „polica po mjeri”, „pitati majstora za odvod”).
class Note {
  Note({required this.id, required this.pos, required this.text, this.color = 0xFFFFE58A});
  final String id;
  Offset pos;
  String text;
  int color;

  Map<String, dynamic> toJson() => {'id': id, 'x': pos.dx, 'y': pos.dy, 'text': text, 'color': color};

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: (j['id'] as String?) ?? newId('n'),
        pos: Offset(_d(j['x'], 0), _d(j['y'], 0)),
        text: (j['text'] as String?) ?? '',
        color: _i(j['color'], 0xFFFFE58A),
      );
}
