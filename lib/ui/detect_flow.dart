import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../state/plan_controller.dart';
import '../state/plan_detect.dart';

/// Automatsko prepoznavanje zidova, vrata i prozora sa slike nacrta, s potvrdom mjerila.
Future<bool> runDetection(BuildContext context, PlanController c) async {
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        SizedBox(width: 16),
        Expanded(child: Text('Tražim zidove, vrata i prozore na nacrtu…')),
      ]),
    ),
  );
  DetectionDraft? draft;
  try {
    await Future<void>.delayed(const Duration(milliseconds: 60)); // neka se dijalog iscrta
    draft = await c.detectFromImage();
  } catch (_) {
    draft = null;
  }
  nav.pop();
  if (draft == null || draft.walls.length < 3) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Na ovoj slici nisam pronašao dovoljno zidova. Precrtaj ih ručno: postavi mjerilo pa crtaj zidove preko nacrta.')));
    return false;
  }
  final (wPx, hPx) = draft.extentPx;
  final est = draft.estimateMpp() ?? c.plan.image!.metersPerPixel;
  final ctrl = TextEditingController(text: (wPx * est).toStringAsFixed(2).replaceAll('.', ','));
  var replace = true;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('Prepoznati nacrt'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pronađeno: ${draft!.walls.length} zidova, ${draft.doors} vrata i ${draft.windows} prozora.',
                style: AppText.ui(size: 14, weight: FontWeight.w600)),
            const SizedBox(height: 14),
            Text('Za točno mjerilo upiši ukupnu vanjsku širinu zgrade (vodoravna kota na nacrtu). '
                'Predložena vrijednost procijenjena je prema širini vrata.',
                style: AppText.ui(size: 12.5, color: Pal.muted, height: 1.4)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Vanjska širina zgrade',
                suffixText: 'm',
                helperText: 'Dubina tada iznosi ≈ ${(hPx * est).toStringAsFixed(2).replaceAll('.', ',')} m',
              ),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
            if (c.plan.walls.isNotEmpty) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: replace,
                onChanged: (v) => setD(() => replace = v ?? true),
                title: const Text('Zamijeni postojeće zidove na ovoj etaži'),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Odustani')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ucrtaj zidove')),
        ],
      ),
    ),
  );
  if (ok != true) return false;
  final meters = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
  final mpp = meters != null && meters > 1 && wPx > 0 ? meters / wPx : est;
  c.applyDetection(draft, mpp, replace: replace);
  messenger.showSnackBar(const SnackBar(
      content: Text('Zidovi su ucrtani. Provjeri ih uz nacrt u pozadini; pogrešan zid ukloni tipkom Delete, a sve možeš poništiti s Ctrl+Z.')));
  return true;
}
