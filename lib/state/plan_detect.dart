import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Offset;

import '../models/geometry.dart';
import '../models/plan.dart';
import 'plan_controller.dart';

@JS('psqDetect')
external _PsqDetect? get _psqDetect;

extension type _PsqDetect(JSObject _) implements JSObject {
  external JSPromise<JSString> detect(String dataUrl, String opts);
  external JSPromise<JSString> prepare(String dataUrl);
}

/// Priprema nacrta: PDF → slika prve stranice, sken se izravna. Vraća (bajtovi, mime, kut nagiba, bio PDF).
Future<(Uint8List, String, double, bool)> prepareImage(Uint8List bytes, String mime, String name) async {
  final isPdf = mime == 'application/pdf' || name.toLowerCase().endsWith('.pdf');
  final api = _psqDetect;
  if (api == null) {
    if (isPdf) throw StateError('PDF nije podržan');
    return (bytes, mime, 0.0, false);
  }
  final type = isPdf ? 'application/pdf' : (mime.isEmpty ? 'image/png' : mime);
  final res = (await api.prepare('data:$type;base64,${base64Encode(bytes)}').toDart).toDart;
  final j = jsonDecode(res) as Map<String, dynamic>;
  final url = j['dataUrl'] as String;
  final outMime = url.substring(5, url.indexOf(';'));
  final out = base64Decode(url.substring(url.indexOf(',') + 1));
  return (Uint8List.fromList(out), outMime, (j['angle'] as num).toDouble(), j['pdf'] == true);
}

/// Rezultat prepoznavanja u pikselima slike nacrta, prije pretvorbe u metre.
class DetectionDraft {
  DetectionDraft(this.walls, this.openings, this.thicknessPx);
  final List<({double ax, double ay, double bx, double by, double t})> walls;
  final List<({String type, double x, double y, double width})> openings;
  final double thicknessPx;

  int get doors => openings.where((o) => o.type == 'door').length;
  int get windows => openings.where((o) => o.type == 'window').length;

  /// Vanjska širina i dubina prepoznate zgrade u pikselima (od vanjskog lica do vanjskog lica).
  (double, double) get extentPx {
    var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
    for (final w in walls) {
      minX = math.min(minX, math.min(w.ax, w.bx) - w.t / 2);
      maxX = math.max(maxX, math.max(w.ax, w.bx) + w.t / 2);
      minY = math.min(minY, math.min(w.ay, w.by) - w.t / 2);
      maxY = math.max(maxY, math.max(w.ay, w.by) + w.t / 2);
    }
    return walls.isEmpty ? (0, 0) : (maxX - minX, maxY - minY);
  }

  /// Procjena mjerila: medijan širine vrata ≈ 90 cm; bez vrata vanjski zid ≈ 30 cm.
  double? estimateMpp() {
    final doors = openings.where((o) => o.type == 'door').map((o) => o.width).toList()..sort();
    if (doors.length >= 2) return 0.9 / doors[doors.length ~/ 2];
    if (walls.isEmpty) return null;
    final ts = walls.map((w) => w.t).toList()..sort();
    return 0.3 / ts.last;
  }
}

extension PlanDetection on PlanController {
  /// Pokreni prepoznavanje na slici nacrta aktivne etaže.
  Future<DetectionDraft?> detectFromImage() async {
    final im = plan.image;
    final api = _psqDetect;
    if (im == null || api == null) return null;
    final res = (await api.detect(im.dataUrl, '{}').toDart).toDart;
    final j = jsonDecode(res) as Map<String, dynamic>;
    double d(dynamic v) => (v as num).toDouble();
    return DetectionDraft(
      [
        for (final w in (j['walls'] as List).cast<Map>())
          (ax: d(w['ax']), ay: d(w['ay']), bx: d(w['bx']), by: d(w['by']), t: d(w['t']))
      ],
      [
        for (final o in (j['openings'] as List).cast<Map>())
          (type: o['type'] as String, x: d(o['x']), y: d(o['y']), width: d(o['width']))
      ],
      d(j['thicknessPx']),
    );
  }

  /// Ucrtaj prepoznate zidove i otvore uz mjerilo [mpp] (metara po pikselu slike).
  void applyDetection(DetectionDraft draft, double mpp, {bool replace = true}) {
    final im = plan.image;
    if (im == null) return;
    mutate(() {
      im.metersPerPixel = mpp;
      Offset world(double x, double y) =>
          Offset(roundTo(im.origin.dx + x * mpp, 0.01), roundTo(im.origin.dy + y * mpp, 0.01));
      if (replace) {
        plan.walls.clear();
        plan.openings.clear();
        plan.nodes.clear();
        plan.rooms.clear();
      }
      for (final w in draft.walls) {
        final a = world(w.ax, w.ay), b = world(w.bx, w.by);
        if ((b - a).distance < 0.2) continue;
        final t = roundTo((w.t * mpp).clamp(0.08, 0.5), 0.01);
        addWall(a, b, thickness: t);
      }
      for (final o in draft.openings) {
        final type = o.type == 'window' ? OpeningType.window : OpeningType.door;
        final op = addOpeningNear(world(o.x, o.y), type, tol: 0.35);
        if (op == null) continue;
        final w = plan.wallById(op.wallId);
        if (w == null) continue;
        final len = plan.wallLength(w);
        final width = roundTo((o.width * mpp).clamp(0.5, math.max(0.5, len - 0.12)), 0.05);
        op.width = width;
        op.t = PlanController.clampOpeningT(len, width, op.t);
      }
      selection = Selection.none;
      tool = Tool.select;
    });
  }
}
