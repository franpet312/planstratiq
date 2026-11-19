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

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) => v is List
    ? v.map((e) => f(Map<String, dynamic>.from(e as Map))).toList()
    : <T>[];

/// Točka (čvor) u kojoj se spajaju zidovi. Zidovi dijele čvorove, pa kad
/// pomakneš jedan zid, spojeni zidovi se automatski prilagode.
class PlanNode {
  PlanNode(this.id, this.pos);
  final String id;
  Offset pos;

  Map<String, dynamic> toJson() =>
      {'id': id, 'x': _r3(pos.dx), 'y': _r3(pos.dy)};
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
    this.color = 0xFFF3EFE9,
  });

  final String id;
  String a;
  String b;
  double thickness;
  double height;
  int color;

  Map<String, dynamic> toJson() => {
        'id': id,
        'a': a,
        'b': b,
        'thickness': thickness,
        'height': height,
        'color': color,
      };

  factory Wall.fromJson(Map<String, dynamic> j) => Wall(
        id: j['id'] as String,
        a: j['a'] as String,
        b: j['b'] as String,
        thickness: _d(j['thickness'], 0.2),
        height: _d(j['height'], 2.6),
        color: _i(j['color'], 0xFFF3EFE9),
      );
}

enum OpeningType { door, window }

/// Vrata ili prozor na zidu. [t] je položaj središta duž zida (0..1).
class Opening {
  Opening({
    required this.id,
    required this.wallId,
    required this.type,
    required this.t,
    required this.width,
    required this.height,
    required this.sill,
  });

  factory Opening.preset(String wallId, OpeningType type, double t) =>
      type == OpeningType.door
          ? Opening(
              id: newId('o'),
              wallId: wallId,
              type: type,
              t: t,
              width: 0.9,
              height: 2.1,
              sill: 0)
          : Opening(
              id: newId('o'),
              wallId: wallId,
              type: type,
              t: t,
              width: 1.2,
              height: 1.2,
              sill: 0.9);

  final String id;
  final String wallId;
  OpeningType type;
  double t;
  double width;
  double height;
  double sill;

  Map<String, dynamic> toJson() => {
        'id': id,
        'wallId': wallId,
        'type': type.name,
        't': _r3(t),
        'width': width,
        'height': height,
        'sill': sill,
      };

  factory Opening.fromJson(Map<String, dynamic> j) => Opening(
        id: j['id'] as String,
        wallId: j['wallId'] as String,
        type: j['type'] == 'window' ? OpeningType.window : OpeningType.door,
        t: _d(j['t'], 0.5),
        width: _d(j['width'], 0.9),
        height: _d(j['height'], 2.1),
        sill: _d(j['sill'], 0),
      );
}

class Room {
  Room({
    required this.id,
    required this.name,
    required this.nodeIds,
    this.floorColor = 0xFFD8C3A5,
  });

  final String id;
  String name;
  final List<String> nodeIds;
  int floorColor;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nodeIds': nodeIds,
        'floorColor': floorColor,
      };

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Soba',
        nodeIds: List<String>.from(j['nodeIds'] as List),
        floorColor: _i(j['floorColor'], 0xFFD8C3A5),
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
    this.modelUrl,
    this.retailer,
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
  final String? modelUrl;
  final String? retailer;

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
        if (modelUrl != null) 'modelUrl': modelUrl,
        if (retailer != null) 'retailer': retailer,
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
        modelUrl: j['modelUrl'] as String?,
        retailer: j['retailer'] as String?,
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
    this.opacity = 0.6,
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
        opacity: _d(j['opacity'], 0.6),
      );
}

class Plan {
  Plan({
    this.name = 'Novi projekt',
    Map<String, PlanNode>? nodes,
    List<Wall>? walls,
    List<Opening>? openings,
    List<Room>? rooms,
    List<PlacedItem>? items,
    this.image,
  })  : nodes = nodes ?? {},
        walls = walls ?? [],
        openings = openings ?? [],
        rooms = rooms ?? [],
        items = items ?? [];

  String name;
  final Map<String, PlanNode> nodes;
  final List<Wall> walls;
  final List<Opening> openings;
  final List<Room> rooms;
  final List<PlacedItem> items;
  PlanImage? image;

  bool get isEmpty => walls.isEmpty && items.isEmpty && rooms.isEmpty;

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
        'version': 1,
        'name': name,
        'nodes': nodes.values.map((n) => n.toJson()).toList(),
        'walls': walls.map((w) => w.toJson()).toList(),
        'openings': openings.map((o) => o.toJson()).toList(),
        'rooms': rooms.map((r) => r.toJson()).toList(),
        'items': items.map((i) => i.toJson()).toList(),
        if (includeImage && image != null) 'image': image!.toJson(),
      };

  factory Plan.fromJson(Map<String, dynamic> j) {
    final nodes = _list(j['nodes'], PlanNode.fromJson);
    return Plan(
      name: (j['name'] as String?) ?? 'Projekt',
      nodes: {for (final n in nodes) n.id: n},
      walls: _list(j['walls'], Wall.fromJson),
      openings: _list(j['openings'], Opening.fromJson),
      rooms: _list(j['rooms'], Room.fromJson),
      items: _list(j['items'], PlacedItem.fromJson),
      image: j['image'] is Map
          ? PlanImage.fromJson(Map<String, dynamic>.from(j['image'] as Map))
          : null,
    );
  }

  /// Podaci koji idu u 3D engine (bez slike nacrta).
  Map<String, dynamic> toSceneJson() => {
        'nodes': {
          for (final n in nodes.values) n.id: {'x': n.pos.dx, 'y': n.pos.dy}
        },
        'walls': walls.map((w) => w.toJson()).toList(),
        'openings': openings.map((o) => o.toJson()).toList(),
        'rooms': rooms.map((r) => r.toJson()).toList(),
        'items': items.map((i) => i.toJson()).toList(),
      };
}
