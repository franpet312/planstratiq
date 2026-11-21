import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/geometry.dart';
import '../models/plan.dart';
import '../state/plan_controller.dart';
import 'plan_painter.dart';

(double, double, double, double)? planBounds(Plan plan) {
  final pts = <Offset>[for (final n in plan.nodes.values) n.pos];
  for (final it in plan.items) {
    final r = math.max(it.w, it.d) / 2;
    pts.add(it.pos - Offset(r, r));
    pts.add(it.pos + Offset(r, r));
  }
  if (pts.isEmpty) return null;
  var minX = pts.first.dx, maxX = minX, minY = pts.first.dy, maxY = minY;
  for (final p in pts) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  return (minX, minY, maxX, maxY);
}

/// Tlocrt kao PNG za ispis ili dijeljenje, s natpisnim poljem projekta.
Future<Uint8List?> renderPlanPng(PlanController c, {double pxPerMeter = 70}) async {
  final b = planBounds(c.plan);
  if (b == null) return null;
  final (minX, minY, maxX, maxY) = b;
  const margin = 2.2;
  final w = ((maxX - minX + 2 * margin) * pxPerMeter).clamp(600, 4200).toDouble();
  final h = ((maxY - minY + 2 * margin) * pxPerMeter + 90).clamp(500, 4200).toDouble();
  final scale = math.min((w) / (maxX - minX + 2 * margin), (h - 90) / (maxY - minY + 2 * margin));
  final pan = Offset(w / 2, (h - 90) / 2) - Offset((minX + maxX) / 2, (minY + maxY) / 2) * scale;

  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
  PlanPainter(PlanPaintState(plan: c.plan, scale: scale, pan: pan, printMode: true)).paint(canvas, Size(w, h - 90));

  // natpisno polje
  final st = c.stats;
  final top = h - 78;
  canvas.drawLine(Offset(24, top), Offset(w - 24, top), Paint()
    ..color = Pal.ink
    ..strokeWidth = 1.2);
  void text(String s, Offset at, TextStyle style, {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, textAlign: align)..layout();
    tp.paint(canvas, align == TextAlign.right ? at - Offset(tp.width, 0) : at);
  }

  text(c.plan.name, Offset(24, top + 12), AppText.ui(size: 22, weight: FontWeight.w700));
  text('Neto površina ${fmtM2(st.netArea)}, bruto ${fmtM2(st.footprint)}, ${st.rooms.length} prostorija',
      Offset(24, top + 44), AppText.narrow(size: 14, color: Pal.inkSoft));
  final now = DateTime.now();
  text('Planstratiq', Offset(w - 24, top + 14), AppText.ui(size: 15, weight: FontWeight.w700, color: Pal.accent), align: TextAlign.right);
  text('${now.day}. ${now.month}. ${now.year}.  Mjere u metrima', Offset(w - 24, top + 44), AppText.narrow(size: 13, color: Pal.muted),
      align: TextAlign.right);

  final img = await rec.endRecording().toImage(w.round(), h.round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}
