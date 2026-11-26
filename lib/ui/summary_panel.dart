import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../app/theme.dart';
import '../models/geometry.dart';
import '../models/materials.dart';
import '../models/shopping.dart';
import '../state/plan_controller.dart';
import 'common.dart';
import 'catalog_panel.dart' show storeColor;
import 'pdf_dialog.dart';
import 'web_files.dart';

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
    final items = [for (final l in c.plan.levels) ...l.items];
    final furniture = items.fold<double>(0, (a, i) => a + (i.price ?? 0));
    final total = st.floorCost + st.paintCost + st.finishCost + furniture;

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
      ..._issuesSection(),
      const SectionTitle('Prostorije'),
      if (st.rooms.isEmpty)
        Text('Zatvori zidove u prostoriju pa će se ovdje pojaviti njena površina.', style: AppText.ui(size: 12.5, color: Pal.muted))
      else
        for (final r in st.rooms)
          InkWell(
            onTap: () {
              c.switchLevel(r.levelIndex);
              c.select(Selection(SelKind.room, r.room.id));
            },
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(r.material.color), borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.level.isEmpty ? r.room.name : '${r.room.name}  ·  ${r.level}', style: AppText.ui(size: 13, weight: FontWeight.w500)),
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
      for (final e in st.finishAreas.entries)
        StatRow('${finishById(e.key).name}, ${fmtM2(e.value)}', fmtEur(e.value * finishById(e.key).pricePerM2)),
      StatRow('Namještaj i oprema, ${items.where((i) => i.price != null).length} kom.', fmtEur(furniture)),
      const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider()),
      StatRow('Ukupno okvirno', fmtEur(total), strong: true),
      const SizedBox(height: 6),
      Text(
        'Za bojanje treba oko ${st.paintLiters.ceil()} L boje (dva sloja). Cijene su okvirne, uključuju materijal i ugradnju '
        'za podove i boju, a ne uključuju gradnju, instalacije ni stolariju.',
        style: AppText.ui(size: 11.5, color: Pal.muted, height: 1.4),
      ),
      ..._electric(),
      ..._shopping(context),
      const SectionTitle('Gradnja'),
      StatRow('Ukupna duljina zidova', '${fmtM(st.wallLength)} m'),
      StatRow('Vrata (uklj. balkonska)', '${st.doors}'),
      StatRow('Prozori', '${st.windows}'),
      const SizedBox(height: 18),
      FilledButton.icon(
          onPressed: () => showPdfDialog(context, c),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('Izvoz u PDF (tlocrti, površine, troškovnik)')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: onExportPlan, icon: const Icon(Icons.image_outlined, size: 18), label: const Text('Spremi tlocrt kao sliku')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: onExportCsv, icon: const Icon(Icons.table_view_outlined, size: 18), label: const Text('Izvezi troškovnik (CSV)')),
    ]);
  }
  List<Widget> _electric() {
    const names = {
      'socket': 'Utičnice',
      'socket_double': 'Dvostruke utičnice',
      'socket_high': 'Utičnice iznad radne ploče',
      'switch': 'Prekidači',
      'tv_socket': 'TV / antenske utičnice',
      'lan_socket': 'Mrežne utičnice (LAN)',
      'light_point': 'Rasvjetna mjesta',
    };
    final counts = <String, int>{};
    var cost = 0.0;
    var lights = 0;
    for (final l in c.plan.levels) {
      for (final it in l.items) {
        if (names.containsKey(it.shape)) {
          counts[it.shape] = (counts[it.shape] ?? 0) + 1;
          cost += it.price ?? 0;
        } else if (const {'chandelier', 'chandelier_ring', 'pendant', 'pendant_row', 'ceiling_light', 'wall_lamp'}.contains(it.shape)) {
          lights++;
        }
      }
    }
    if (counts.isEmpty) return const [];
    return [
      const SectionTitle('Električne instalacije'),
      for (final k in names.keys)
        if (counts[k] != null) StatRow(names[k]!, '${counts[k]} kom.'),
      if (lights > 0) StatRow('Stropna i zidna rasvjeta (iz kataloga)', '$lights kom.'),
      const SizedBox(height: 4),
      StatRow('Okvirno (točke s ugradnjom)', fmtEur(cost), strong: true),
    ];
  }

  List<Widget> _shopping(BuildContext context) {
    final list = shoppingList(c.plan);
    if (list.isEmpty) return const [];
    final all = list.values.expand((l) => l).fold<double>(0, (a, l) => a + l.total);
    return [
      const SectionTitle('Popis za kupnju po trgovinama'),
      for (final e in list.entries)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 6),
            dense: true,
            leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: storeColor(e.key == genericStore ? null : e.key), shape: BoxShape.circle)),
            title: Text(e.key, style: AppText.ui(size: 13, weight: FontWeight.w600)),
            subtitle: Text('${e.value.fold<int>(0, (a, l) => a + l.qty)} kom.', style: AppText.ui(size: 11.5, color: Pal.muted)),
            trailing: Text(fmtEur(e.value.fold<double>(0, (a, l) => a + l.total)), style: AppText.narrow(size: 13.5, weight: FontWeight.w700)),
            children: [
              for (final l in e.value)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(width: 26, child: Text('${l.qty}×', style: AppText.narrow(size: 12.5, weight: FontWeight.w600))),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.ui(size: 12.5)),
                        Text('${(l.w * 100).round()}×${(l.d * 100).round()}×${(l.h * 100).round()} cm', style: AppText.ui(size: 11, color: Pal.muted)),
                      ]),
                    ),
                    Text(l.price == null ? '—' : fmtEur(l.total), style: AppText.narrow(size: 12.5)),
                    if (l.url != null)
                      IconButton(
                        tooltip: 'Otvori proizvod',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        onPressed: () => web.window.open(l.url!, '_blank'),
                      ),
                  ]),
                ),
            ],
          ),
        ),
      StatRow('Sve trgovine', fmtEur(all), strong: true),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        onPressed: () => downloadText(shoppingCsv(c.plan), '${c.plan.name} - popis za kupnju.csv', mime: 'text/csv;charset=utf-8'),
        icon: const Icon(Icons.shopping_cart_outlined, size: 18),
        label: const Text('Preuzmi popis za kupnju (CSV)'),
      ),
    ];
  }

  List<Widget> _issuesSection() {
    final issues = c.issues;
    return [
      SectionTitle(issues.isEmpty ? 'Provjera prolaza' : 'Provjera prolaza (${issues.length})'),
      if (issues.isEmpty)
        Text('Na ovoj etaži sva vrata, ladice i ormari imaju mjesta za otvaranje, a prolazi su dovoljno široki.',
            style: AppText.ui(size: 12.5, color: Pal.muted, height: 1.35))
      else
        for (final i in issues)
          InkWell(
            onTap: i.itemId == null ? null : () => c.select(Selection(SelKind.item, i.itemId!)),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber_rounded, size: 17, color: i.serious ? const Color(0xFFC0392B) : const Color(0xFFD08A1E)),
                const SizedBox(width: 8),
                Expanded(child: Text(i.message, style: AppText.ui(size: 12.5, height: 1.35))),
              ]),
            ),
          ),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: c.showIssues,
        onChanged: c.setShowIssues,
        title: Text('Prikaži upozorenja na tlocrtu', style: AppText.ui(size: 12.5)),
      ),
    ];
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
    b.writeln('${q(r.level.isEmpty ? r.room.name : '${r.room.name} (${r.level})')};${n(r.area)};${n(r.perimeter)};${q(r.material.name)};${n(r.floorCost)}');
  }
  b.writeln('${q('Ukupno')};${n(st.netArea)};;;${n(st.floorCost)}');
  b.writeln();
  b.writeln('${q('Bojanje zidova (m²)')};${n(st.paintArea)};${q('Boja (L)')};${n(st.paintLiters)};${n(st.paintCost)}');
  for (final e in st.finishAreas.entries) {
    final f = finishById(e.key);
    b.writeln('${q('Zidna obloga: ${f.name} (m²)')};${n(e.value)};;;${n(e.value * f.pricePerM2)}');
  }
  b.writeln();
  b.writeln('${q('Namještaj')};${q('Širina (cm)')};${q('Dubina (cm)')};${q('Visina (cm)')};${q('Okvirna cijena (€)')}');
  var furniture = 0.0;
  for (final i in [for (final l in c.plan.levels) ...l.items]) {
    furniture += i.price ?? 0;
    b.writeln('${q(i.name)};${(i.w * 100).round()};${(i.d * 100).round()};${(i.h * 100).round()};${i.price == null ? '' : n(i.price!)}');
  }
  b.writeln('${q('Ukupno namještaj')};;;;${n(furniture)}');
  b.writeln();
  b.writeln('${q('Sveukupno okvirno (€)')};;;;${n(st.floorCost + st.paintCost + st.finishCost + furniture)}');
  return b.toString();
}
