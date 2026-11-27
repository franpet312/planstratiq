import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../editor/pdf_export.dart';
import '../state/plan_controller.dart';
import '../viewer/engine_bridge.dart';
import 'web_files.dart';

final _last = PdfOptions();

/// Dijalog „Izvoz u PDF”: papir, mjerilo i sadržaj, zatim izrada i preuzimanje.
Future<void> showPdfDialog(BuildContext context, PlanController c) async {
  final o = _last;
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      Future<void> run() async {
        set(() {
          busy = true;
          error = null;
        });
        try {
          final shot = Engine3D.instance.screenshotPng();
          final bytes = await buildProjectPdf(c, o, view3dPng: shot);
          downloadBytes(bytes, '${c.plan.name}.pdf', mime: 'application/pdf');
          if (ctx.mounted) Navigator.pop(ctx);
        } catch (e) {
          set(() {
            busy = false;
            error = 'PDF se nije mogao izraditi. Osvježi stranicu i pokušaj ponovno.';
          });
        }
      }

      Widget check(String label, String sub, bool v, void Function(bool) on) => CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: v,
            onChanged: busy ? null : (x) => set(() => on(x ?? false)),
            title: Text(label, style: AppText.ui(size: 13, weight: FontWeight.w500)),
            subtitle: Text(sub, style: AppText.ui(size: 12, color: Pal.muted)),
          );

      return AlertDialog(
        title: const Text('Izvoz u PDF'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Papir', style: AppText.ui(size: 12, weight: FontWeight.w600, color: Pal.muted)),
            const SizedBox(height: 6),
            SegmentedButton<Paper>(
              segments: const [
                ButtonSegment(value: Paper.a4, label: Text('A4')),
                ButtonSegment(value: Paper.a3, label: Text('A3')),
              ],
              selected: {o.paper},
              onSelectionChanged: busy ? null : (s) => set(() => o.paper = s.first),
            ),
            const SizedBox(height: 14),
            Text('Mjerilo tlocrta', style: AppText.ui(size: 12, weight: FontWeight.w600, color: Pal.muted)),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Auto')),
                ButtonSegment(value: 50, label: Text('1:50')),
                ButtonSegment(value: 100, label: Text('1:100')),
                ButtonSegment(value: 200, label: Text('1:200')),
              ],
              selected: {o.scale},
              onSelectionChanged: busy ? null : (s) => set(() => o.scale = s.first),
            ),
            const SizedBox(height: 4),
            Text('Auto bira najveće mjerilo koje stane na papir. Ispisuj u stvarnoj veličini (100 %).',
                style: AppText.ui(size: 12, color: Pal.muted, height: 1.35)),
            const SizedBox(height: 10),
            check('Naslovnica', '3D prikaz, ključne površine i sadržaj', o.cover, (v) => o.cover = v),
            check('Tlocrti', c.plan.levels.length > 1 ? 'Svaka etaža na svom listu, s kotama' : 'S kotama i grafičkim mjerilom', o.plans,
                (v) => o.plans = v),
            if (c.plan.section != null)
              check('Presjek A–A', 'Vertikalni presjek po crti s tlocrta, s kotama visina', o.section, (v) => o.section = v),
            check('Popis prostorija', 'Neto površine, opsezi i podovi', o.rooms, (v) => o.rooms = v),
            check('Okvirni troškovnik', 'Podovi, bojanje i namještaj', o.costs, (v) => o.costs = v),
            check('Popis za kupnju', 'Namještaj po trgovinama, s količinama', o.shopping, (v) => o.shopping = v),
            if (busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text('Izrađujem PDF…', style: AppText.ui(size: 12, color: Pal.muted)),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: AppText.ui(size: 12, color: Pal.danger)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Odustani')),
          FilledButton.icon(
            onPressed: busy || !(o.cover || o.plans || o.section || o.rooms || o.costs || o.shopping) ? null : run,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Izradi PDF'),
          ),
        ],
      );
    }),
  );
}
