import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/geometry.dart';
import '../models/materials.dart';
import '../state/plan_controller.dart';
import 'plan_export.dart';
import 'plan_painter.dart';

/// Izvoz projekta u PDF: naslovnica, tlocrt svake etaže u mjerilu, popis prostorija i troškovnik.
///
/// Stranice se crtaju Flutterovim platnom (192 dpi), a `web/psqpdf.js` ih slaže u PDF.
/// Mjerilo vrijedi pri ispisu bez prilagodbe veličine („stvarna veličina” / 100 %).

enum Paper { a4, a3 }

class PdfOptions {
  PdfOptions({
    this.paper = Paper.a4,
    this.scale = 0,
    this.cover = true,
    this.plans = true,
    this.rooms = true,
    this.costs = true,
  });
  Paper paper;

  /// Nazivnik mjerila (50, 100, 200…); 0 = automatski najveće mjerilo koje stane.
  int scale;
  bool cover, plans, rooms, costs;
}

@JS('psqPdf')
external _PsqPdf? get _psqPdf;

extension type _PsqPdf(JSObject _) implements JSObject {
  external JSPromise<JSUint8Array> build(JSArray<JSUint8Array> pages, String meta);
}

const _vpm = 96 / 25.4; // virtualni px po mm (kao zaslon 96 dpi)
const _k = 2.0; // rasterizacija 2× => 192 dpi
const _standardScales = [20, 50, 100, 200, 250, 500, 1000];

class _Page {
  _Page(this.wMm, this.hMm);
  final double wMm, hMm;
  late final ui.PictureRecorder rec = ui.PictureRecorder();
  late final Canvas canvas = () {
    final c = Canvas(rec);
    c.scale(_k * _vpm); // crtamo u milimetrima
    c.drawRect(Rect.fromLTWH(0, 0, wMm, hMm), Paint()..color = Colors.white);
    return c;
  }();

  Future<Uint8List> png() async {
    final img = await rec.endRecording().toImage((wMm * _vpm * _k).round(), (hMm * _vpm * _k).round());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data!.buffer.asUint8List();
  }
}

class _Pdf {
  _Pdf(this.c, this.o, this.view3d);
  final PlanController c;
  final PdfOptions o;
  final ui.Image? view3d;
  final pages = <_Page>[];
  final titles = <String>[];
  int total = 0;

  (double, double) get portrait => o.paper == Paper.a3 ? (297, 420) : (210, 297);
  (double, double) get landscape => (portrait.$2, portrait.$1);

  // ---------------------------------------------------------------- tekst
  double text(Canvas cv, String s, Offset at,
      {double size = 3.2, FontWeight w = FontWeight.w400, Color color = Pal.ink, double? maxW, TextAlign align = TextAlign.left, bool narrow = false}) {
    // veličina u mm; TextPainter radi u „px”, pa platno privremeno skaliramo
    const f = 4.0; // 1 mm = 4 jedinice teksta (oštar tekst pri rasterizaciji)
    final style = narrow ? AppText.narrow(size: size * f, weight: w, color: color) : AppText.ui(size: size * f, weight: w, color: color);
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxW == null ? null : 2,
      ellipsis: maxW == null ? null : '…',
    )..layout(maxWidth: maxW == null ? double.infinity : maxW * f);
    cv.save();
    cv.translate(at.dx, at.dy);
    cv.scale(1 / f);
    final dx = align == TextAlign.right ? -tp.width : (align == TextAlign.center ? -tp.width / 2 : 0.0);
    tp.paint(cv, Offset(dx, 0));
    cv.restore();
    return tp.height / f;
  }

  Paint stroke(double mm, [Color color = Pal.ink]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = mm
    ..color = color;

  // okvir lista i natpisno polje (dolje, cijela širina)
  Rect frame(_Page p, String sheet, {String? scaleLabel}) {
    final cv = p.canvas;
    const m = 10.0, mLeft = 15.0, tb = 18.0;
    final outer = Rect.fromLTRB(mLeft, m, p.wMm - m, p.hMm - m);
    cv.drawRect(outer, stroke(0.35));
    final top = outer.bottom - tb;
    cv.drawLine(Offset(outer.left, top), Offset(outer.right, top), stroke(0.25));
    final cols = [outer.left, outer.right - 150, outer.right - 95, outer.right - 50, outer.right];
    for (var i = 1; i < cols.length - 1; i++) {
      cv.drawLine(Offset(cols[i], top), Offset(cols[i], outer.bottom), stroke(0.18));
    }
    void cell(int i, String label, String value, {bool big = false}) {
      text(cv, label, Offset(cols[i] + 2.5, top + 2.2), size: 2.0, color: Pal.muted, narrow: true);
      text(cv, value, Offset(cols[i] + 2.5, top + 6.4), size: big ? 4.4 : 3.2, w: big ? FontWeight.w700 : FontWeight.w600,
          maxW: cols[i + 1] - cols[i] - 5);
    }

    cell(0, 'PROJEKT', c.plan.name, big: true);
    cell(1, 'LIST', sheet);
    cell(2, 'MJERILO', scaleLabel ?? '—');
    final now = DateTime.now();
    cell(3, 'DATUM · LIST', '${now.day}. ${now.month}. ${now.year}.   ${pages.length}/${total == 0 ? pages.length : total}');
    text(cv, 'Planstratiq', Offset(outer.left + 2.5, top + 13.2), size: 2.2, w: FontWeight.w700, color: Pal.accent);
    return Rect.fromLTRB(outer.left + 6, outer.top + 6, outer.right - 6, top - 6);
  }

  _Page newPage((double, double) size, String title) {
    final p = _Page(size.$1, size.$2);
    pages.add(p);
    titles.add(title);
    return p;
  }

  // ---------------------------------------------------------------- tlocrt
  void planPage(int li) {
    final plan = c.plan;
    final prev = plan.active;
    plan.active = li;
    try {
      final b = planBounds(plan);
      if (b == null) return;
      final (minX, minY, maxX, maxY) = b;
      const extra = 1.6; // mjesto za kote izvan zgrade
      final bw = maxX - minX + 2 * extra, bh = maxY - minY + 2 * extra;
      // orijentacija i mjerilo
      int? bestDen;
      (double, double)? bestSize;
      for (final size in [landscape, portrait]) {
        final aw = size.$1 - 15 - 10 - 12, ah = size.$2 - 20 - 18 - 12 - 8;
        final den = o.scale != 0 ? o.scale : _standardScales.firstWhere((d) => bw * 1000 / d <= aw && bh * 1000 / d <= ah, orElse: () => 1000);
        final fits = bw * 1000 / den <= aw && bh * 1000 / den <= ah;
        if (bestDen == null || (fits && den < bestDen)) {
          bestDen = den;
          bestSize = size;
        }
      }
      final den = bestDen!;
      final lvl = plan.levels.length > 1 ? plan.level.name : 'Tlocrt';
      final p = newPage(bestSize!, 'Tlocrt – ${plan.level.name}');
      final area = frame(p, plan.levels.length > 1 ? 'Tlocrt – $lvl' : 'Tlocrt', scaleLabel: '1:$den');
      final cv = p.canvas;

      // PlanPainter crta u „px”; 1 px = 1/_vpm mm (kao na zaslonu 96 dpi)
      final pxPerM = 1000 / den * _vpm;
      final areaPx = Rect.fromLTRB(area.left * _vpm, area.top * _vpm, area.right * _vpm, (area.bottom - 9) * _vpm);
      final pan = areaPx.center - Offset((minX + maxX) / 2, (minY + maxY) / 2) * pxPerM;
      cv.save();
      cv.clipRect(Rect.fromLTRB(area.left, area.top, area.right, area.bottom - 8));
      cv.scale(1 / _vpm);
      PlanPainter(PlanPaintState(plan: plan, scale: pxPerM, pan: pan, printMode: true)).paint(cv, areaPx.size + areaPx.topLeft);
      cv.restore();

      // grafičko mjerilo
      final stepM = den <= 50 ? 1.0 : (den <= 200 ? 2.0 : 5.0);
      final segMm = stepM * 1000 / den;
      final y = area.bottom - 4;
      var x = area.left;
      for (var i = 0; i < 4; i++) {
        final r = Rect.fromLTWH(x, y - 1.2, segMm, 1.2);
        if (i.isEven) cv.drawRect(r, Paint()..color = Pal.ink);
        cv.drawRect(r, stroke(0.15));
        text(cv, fmtM(stepM * i, 0), Offset(x, y + 0.6), size: 2.0, align: TextAlign.center, narrow: true);
        x += segMm;
      }
      text(cv, '${fmtM(stepM * 4, 0)} m', Offset(x, y + 0.6), size: 2.0, align: TextAlign.center, narrow: true);
      text(cv, 'Mjerilo 1:$den vrijedi pri ispisu u stvarnoj veličini (100 %).', Offset(area.right, y - 1.6),
          size: 2.0, color: Pal.muted, align: TextAlign.right, narrow: true);
    } finally {
      plan.active = prev;
    }
  }

  // ---------------------------------------------------------------- naslovnica
  void coverPage() {
    final p = newPage(portrait, 'Naslovnica');
    final cv = p.canvas;
    final area = frame(p, 'Naslovnica');
    final st = c.stats;
    var y = area.top + 6;
    text(cv, 'PROJEKT KUĆE', Offset(area.left + 4, y), size: 3, w: FontWeight.w600, color: Pal.accent, narrow: true);
    y += 6;
    y += text(cv, c.plan.name, Offset(area.left + 4, y), size: 11, w: FontWeight.w700, maxW: area.width - 8) + 4;

    // slika: 3D pogled ako postoji, inače tlocrt prizemlja
    final imgRect = Rect.fromLTWH(area.left + 4, y, area.width - 8, area.height * 0.46);
    cv.drawRect(imgRect, Paint()..color = const Color(0xFFF3F5F4));
    if (view3d != null) {
      final src = Rect.fromLTWH(0, 0, view3d!.width.toDouble(), view3d!.height.toDouble());
      final fit = applyBoxFit(BoxFit.cover, src.size, imgRect.size);
      final s = Alignment.center.inscribe(fit.source, src);
      cv.drawImageRect(view3d!, s, imgRect, Paint()..filterQuality = FilterQuality.high);
    } else {
      final plan = c.plan;
      final prev = plan.active;
      plan.active = plan.groundIndex;
      final b = planBounds(plan);
      if (b != null) {
        final (minX, minY, maxX, maxY) = b;
        final s = math.min((imgRect.width - 20) / (maxX - minX + 2), (imgRect.height - 20) / (maxY - minY + 2)) * _vpm;
        final rPx = Rect.fromLTRB(imgRect.left * _vpm, imgRect.top * _vpm, imgRect.right * _vpm, imgRect.bottom * _vpm);
        final pan = rPx.center - Offset((minX + maxX) / 2, (minY + maxY) / 2) * s;
        cv.save();
        cv.clipRect(imgRect);
        cv.scale(1 / _vpm);
        PlanPainter(PlanPaintState(plan: plan, scale: s, pan: pan, preview: true)).paint(cv, rPx.size + rPx.topLeft);
        cv.restore();
      }
      plan.active = prev;
    }
    y = imgRect.bottom + 8;

    // ključni podaci
    final furniture = c.plan.levels.fold<double>(0, (a, l) => a + l.items.fold<double>(0, (b, i) => b + (i.price ?? 0)));
    final facts = [
      ('Neto površina', fmtM2(st.netArea)),
      ('Bruto tlocrt', fmtM2(st.footprint)),
      ('Prostorija', '${st.rooms.length}'),
      ('Etaža', '${c.plan.levels.length}'),
      ('Vrata / prozori', '${st.doors} / ${st.windows}'),
      ('Okvirno opremanje', fmtEur(st.floorCost + st.paintCost + furniture)),
    ];
    final colW = (area.width - 8) / 3;
    for (var i = 0; i < facts.length; i++) {
      final x = area.left + 4 + (i % 3) * colW;
      final yy = y + (i ~/ 3) * 17;
      cv.drawLine(Offset(x, yy), Offset(x + colW - 6, yy), stroke(0.2, Pal.line));
      text(cv, facts[i].$1, Offset(x, yy + 2), size: 2.6, color: Pal.muted);
      text(cv, facts[i].$2, Offset(x, yy + 6.5), size: 5.2, w: FontWeight.w700);
    }
    y += 2 * 17 + 6;

    // sadržaj
    text(cv, 'Sadržaj', Offset(area.left + 4, y), size: 3.2, w: FontWeight.w700);
    y += 6;
    final toc = <String>[
      if (o.plans) for (final l in c.plan.levels) 'Tlocrt – ${l.name}',
      if (o.rooms) 'Popis prostorija',
      if (o.costs) 'Okvirni troškovnik',
    ];
    for (final t in toc) {
      if (y > area.bottom - 8) break;
      text(cv, '•  $t', Offset(area.left + 6, y), size: 3);
      y += 5;
    }
    text(cv, 'Izrađeno u aplikaciji Planstratiq. Mjere su informativne; prije gradnje ih mora provjeriti ovlašteni projektant.',
        Offset(area.left + 4, area.bottom - 6), size: 2.2, color: Pal.muted, maxW: area.width - 8);
  }

  // ---------------------------------------------------------------- tablice
  /// Crta tablicu na jednu ili više stranica.
  void table(String title, List<(String, double, TextAlign)> cols, List<List<String>> rows, {List<String>? footer, String? note}) {
    _Page? p;
    late Rect area;
    late double y;
    late List<double> xs;
    void header() {
      p = newPage(portrait, title);
      area = frame(p!, title);
      final cv = p!.canvas;
      y = area.top + 2;
      y += text(cv, title, Offset(area.left, y), size: 6, w: FontWeight.w700) + 2;
      if (note != null) y += text(cv, note, Offset(area.left, y), size: 2.4, color: Pal.muted, maxW: area.width) + 3;
      final total = cols.fold<double>(0, (a, c) => a + c.$2);
      xs = [area.left];
      for (final col in cols) {
        xs.add(xs.last + col.$2 / total * area.width);
      }
      for (var i = 0; i < cols.length; i++) {
        final al = cols[i].$3;
        final x = al == TextAlign.right ? xs[i + 1] - 1.5 : xs[i] + 1.5;
        text(cv, cols[i].$1, Offset(x, y + 1), size: 2.4, w: FontWeight.w600, color: Pal.muted, align: al, narrow: true);
      }
      y += 5.5;
      cv.drawLine(Offset(area.left, y), Offset(area.right, y), stroke(0.3));
    }

    void row(List<String> r, {bool bold = false}) {
      const rh = 6.2;
      if (p == null || y + rh > area.bottom - 2) header();
      final cv = p!.canvas;
      for (var i = 0; i < cols.length && i < r.length; i++) {
        final al = cols[i].$3;
        final x = al == TextAlign.right ? xs[i + 1] - 1.5 : xs[i] + 1.5;
        text(cv, r[i], Offset(x, y + 1.6), size: 2.9, w: bold ? FontWeight.w700 : FontWeight.w400, align: al,
            maxW: al == TextAlign.left ? xs[i + 1] - xs[i] - 3 : null);
      }
      y += rh;
      cv.drawLine(Offset(area.left, y), Offset(area.right, y), stroke(bold ? 0.3 : 0.1, bold ? Pal.ink : Pal.line));
    }

    for (final r in rows) {
      row(r);
    }
    if (footer != null) row(footer, bold: true);
    if (rows.isEmpty && footer == null) header();
  }

  void roomsPages() {
    final st = c.stats;
    final multi = c.plan.levels.length > 1;
    final rows = [
      for (final r in st.rooms)
        [if (multi) r.level, r.room.name, r.material.name, fmtM(r.perimeter), fmtM2(r.area)]
    ];
    table(
      'Popis prostorija',
      [if (multi) ('ETAŽA', 2.2, TextAlign.left), ('PROSTORIJA', 3.2, TextAlign.left), ('POD', 3, TextAlign.left), ('OPSEG (m)', 1.6, TextAlign.right), ('NETO POVRŠINA', 2, TextAlign.right)],
      rows,
      footer: [if (multi) '', 'Ukupno', '', '', fmtM2(st.netArea)],
      note: 'Neto površina mjeri se po unutarnjim licima zidova. Bruto tlocrtna površina zgrade: ${fmtM2(st.footprint)}.',
    );
  }

  void costPages() {
    final st = c.stats;
    // podovi po materijalu
    final byMat = <FloorMaterial, double>{};
    for (final r in st.rooms) {
      byMat[r.material] = (byMat[r.material] ?? 0) + r.area;
    }
    final rows = <List<String>>[
      for (final e in byMat.entries)
        ['Pod: ${e.key.name}', '${fmtM(e.value)} m²', fmtEur(e.key.pricePerM2), fmtEur(e.value * e.key.pricePerM2)],
      ['Bojanje zidova (${fmtM(st.paintLiters, 1)} L boje)', '${fmtM(st.paintArea)} m²', fmtEur(paintPricePerM2), fmtEur(st.paintCost)],
    ];
    var furniture = 0.0;
    final multi = c.plan.levels.length > 1;
    for (final l in c.plan.levels) {
      for (final i in l.items) {
        furniture += i.price ?? 0;
        final who = [if (i.retailer != null) i.retailer!, if (multi) l.name].join(', ');
        rows.add([
          who.isEmpty ? i.name : '${i.name} ($who)',
          '${(i.w * 100).round()}×${(i.d * 100).round()}×${(i.h * 100).round()} cm',
          '',
          i.price == null ? '—' : fmtEur(i.price!),
        ]);
      }
    }
    table(
      'Okvirni troškovnik',
      [('STAVKA', 5.4, TextAlign.left), ('KOLIČINA / MJERE', 2.2, TextAlign.right), ('JED. CIJENA', 1.5, TextAlign.right), ('IZNOS', 1.6, TextAlign.right)],
      rows,
      footer: ['Ukupno okvirno', '', '', fmtEur(st.floorCost + st.paintCost + furniture)],
      note: 'Cijene su okvirne (podovi i boja po prosječnim cijenama, namještaj po cijeni iz kataloga) i ne uključuju radove ni PDV ako nije navedeno.',
    );
  }

  void layout() {
    if (o.cover) coverPage();
    if (o.plans) {
      for (var i = 0; i < c.plan.levels.length; i++) {
        planPage(i);
      }
    }
    if (o.rooms) roomsPages();
    if (o.costs) costPages();
    if (pages.isEmpty) coverPage();
  }

  void discard() {
    for (final p in pages) {
      p.canvas; // osiguraj da je snimanje započelo
      p.rec.endRecording().dispose();
    }
  }

  Future<Uint8List> render() async {
    final pngs = <JSUint8Array>[];
    final sizes = <List<double>>[];
    for (final p in pages) {
      pngs.add((await p.png()).toJS);
      sizes.add([p.wMm / 25.4 * 72, p.hMm / 25.4 * 72]);
    }
    final api = _psqPdf;
    if (api == null) throw StateError('PDF modul nije učitan');
    final out = await api.build(pngs.toJS, jsonEncode({'title': c.plan.name, 'sizes': sizes, 'quality': 0.9})).toDart;
    return out.toDart;
  }
}

/// Izradi PDF projekta. [view3dPng] je snimka 3D prikaza za naslovnicu (ako je dostupna).
Future<Uint8List> buildProjectPdf(PlanController c, PdfOptions o, {Uint8List? view3dPng}) async {
  ui.Image? img;
  if (view3dPng != null) {
    try {
      final codec = await ui.instantiateImageCodec(view3dPng);
      img = (await codec.getNextFrame()).image;
    } catch (_) {}
  }
  // prvi prolaz samo prebroji listove (tablice se same lome na više stranica)
  final probe = _Pdf(c, o, img)..layout();
  final n = probe.pages.length;
  probe.discard();
  final pdf = _Pdf(c, o, img)
    ..total = n
    ..layout();
  return pdf.render();
}
