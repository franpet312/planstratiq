import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../editor/section_painter.dart';
import '../state/plan_controller.dart';

/// Prozor s presjekom A–A (crta presjeka na tlocrtu).
Future<void> showSectionDialog(BuildContext context, PlanController c) => showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 760),
          child: AnimatedBuilder(
            animation: c,
            builder: (ctx, _) {
              final sec = c.plan.section;
              if (sec == null) return const SizedBox(height: 80, child: Center(child: Text('Presjek je obrisan.')));
              final g = buildSection(c.plan, sec, c.roofShape, terrainAt: c.terrainAt);
              return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                          'Presječeni zidovi su crni, ploče sive, krov crven; namještaj kroz koji crta prolazi je svijetao. '
                          'Kote lijevo su visine poda iznad terena, desno svijetle visine etaža.',
                          style: AppText.ui(size: 12.5, color: Pal.muted, height: 1.35)),
                    ),
                    TextButton.icon(
                        onPressed: () => c.mutate(() => sec.flip = !sec.flip),
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        label: const Text('Gledaj s druge strane')),
                    TextButton.icon(
                        onPressed: () {
                          c.mutate(() => c.plan.section = null);
                          Navigator.of(ctx).pop();
                        },
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Obriši presjek')),
                    IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close), tooltip: 'Zatvori'),
                  ]),
                ),
                Flexible(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Pal.lineSoft), borderRadius: BorderRadius.circular(8)),
                      clipBehavior: Clip.antiAlias,
                      child: CustomPaint(painter: SectionPainter(g)),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
