import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/geometry.dart';
import '../models/materials.dart';
import '../state/plan_controller.dart';
import 'common.dart';

/// Pregled projekta: površine po prostorijama i okvirni troškovnik.
class SummaryPanel extends StatelessWidget {
  const SummaryPanel({super.key, required this.c, required this.onExportCsv, required this.onExportPlan});
  final PlanController c;
  final VoidCallback onExportCsv;
  final VoidCallback onExportPlan;

  @override
  Widget build(BuildContext context) {
    final st = c.stats;
    final floorsByMat = <String, double>{};
    for (final r in st.rooms) {
      floorsByMat[r.material.id] = (floorsByMat[r.material.id] ?? 0) + r.area;
    }
    final items = c.plan.items;
    final furniture = items.fold<double>(0, (a, i) => a + (i.price ?? 0));
    final total = st.floorCost + st.paintCost + furniture;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
      // glavna brojka
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Pal.paper, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.lineSoft)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Neto površina', style: AppText.ui(size: 12, color: Pal.muted)),
              Text(fmtM2(st.netArea), style: AppText.narrow(size: 28, weight: FontWeight.w700, height: 1.1)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Bruto tlocrt', style: AppText.ui(size: 12, color: Pal.muted)),
            Text(fmtM2(st.footprint), style: AppText.narrow(size: 16, weight: FontWeight.w600)),
          ]),
        ]),
      ),
      const SectionTitle('Prostorije'),
      if (st.rooms.isEmpty)
        Text('Zatvori zidove u prostoriju pa će se ovdje pojaviti njena površina.', style: AppText.ui(size: 12.5, color: Pal.muted))
      else
        for (final r in st.rooms)
          InkWell(
            onTap: () => c.select(Selection(SelKind.room, r.room.id)),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(r.material.color), borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.room.name, style: AppText.ui(size: 13, weight: FontWeight.w500)),
                    Text(r.material.name, style: AppText.ui(size: 11.5, color: Pal.muted)),
                  ]),
                ),
                Text(fmtM2(r.area), style: AppText.narrow(size: 13.5, weight: FontWeight.w600)),
              ]),
            ),
          ),
      const SectionTitle('Okvirni troškovnik'),
      for (final e in floorsByMat.entries)
        StatRow('${floorById(e.key).name}, ${fmtM2(e.value)}', fmtEur(e.value * floorById(e.key).pricePerM2)),
      StatRow('Bojanje zidova, ${fmtM2(st.paintArea)}', fmtEur(st.paintCost)),
      StatRow('Namještaj i oprema, ${items.where((i) => i.price != null).length} kom.', fmtEur(furniture)),
      const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider()),
      StatRow('Ukupno okvirno', fmtEur(total), strong: true),
      const SizedBox(height: 6),
      Text(
        'Za bojanje treba oko ${st.paintLiters.ceil()} L boje (dva sloja). Cijene su okvirne, uključuju materijal i ugradnju '
        'za podove i boju, a ne uključuju gradnju, instalacije ni stolariju.',
        style: AppText.ui(size: 11.5, color: Pal.muted, height: 1.4),
      ),
      const SectionTitle('Gradnja'),
      StatRow('Ukupna duljina zidova', '${fmtM(st.wallLength)} m'),
      StatRow('Vrata (uklj. balkonska)', '${st.doors}'),
      StatRow('Prozori', '${st.windows}'),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: onExportPlan, icon: const Icon(Icons.image_outlined, size: 18), label: const Text('Spremi tlocrt kao sliku')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: onExportCsv, icon: const Icon(Icons.table_view_outlined, size: 18), label: const Text('Izvezi troškovnik (CSV)')),
    ]);
  }
}

/// Troškovnik u CSV obliku (otvara se u Excelu i Google Sheetsu).
String buildCsv(PlanController c) {
  final st = c.stats;
  final b = StringBuffer('﻿'); // BOM da Excel ispravno prikaže dijakritike
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  String n(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
  b.writeln('${q('Projekt')};${q(c.plan.name)}');
  b.writeln();
  b.writeln('${q('Prostorija')};${q('Površina (m²)')};${q('Opseg (m)')};${q('Pod')};${q('Cijena poda (€)')}');
  for (final r in st.rooms) {
    b.writeln('${q(r.room.name)};${n(r.area)};${n(r.perimeter)};${q(r.material.name)};${n(r.floorCost)}');
  }
  b.writeln('${q('Ukupno')};${n(st.netArea)};;;${n(st.floorCost)}');
  b.writeln();
  b.writeln('${q('Bojanje zidova (m²)')};${n(st.paintArea)};${q('Boja (L)')};${n(st.paintLiters)};${n(st.paintCost)}');
  b.writeln();
  b.writeln('${q('Namještaj')};${q('Širina (cm)')};${q('Dubina (cm)')};${q('Visina (cm)')};${q('Okvirna cijena (€)')}');
  var furniture = 0.0;
  for (final i in c.plan.items) {
    furniture += i.price ?? 0;
    b.writeln('${q(i.name)};${(i.w * 100).round()};${(i.d * 100).round()};${(i.h * 100).round()};${i.price == null ? '' : n(i.price!)}');
  }
  b.writeln('${q('Ukupno namještaj')};;;;${n(furniture)}');
  b.writeln();
  b.writeln('${q('Sveukupno okvirno (€)')};;;;${n(st.floorCost + st.paintCost + furniture)}');
  return b.toString();
}
