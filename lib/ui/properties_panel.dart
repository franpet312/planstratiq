import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/geometry.dart';
import '../models/plan.dart';
import '../state/plan_controller.dart';

const wallColors = [0xFFF3EFE9, 0xFFFFFFFF, 0xFFE6DCCB, 0xFFC9D6DF, 0xFFB7C9A8, 0xFF9E9E9A, 0xFFD9A38B];
const floorColors = [0xFFC8A98A, 0xFFD9C3A3, 0xFF9C7350, 0xFFD6D3CC, 0xFFB9C7CF, 0xFF8E8E8A, 0xFFEFEAE2];
const itemColors = [0xFFFFFFFF, 0xFFEDE7DF, 0xFFD9C7B0, 0xFFB08D6E, 0xFF8C6A4F, 0xFF5A4636, 0xFF7C8B99, 0xFF3D3D3D, 0xFF4F7F4A, 0xFFB5574B];

/// Brojčano polje koje primjenjuje vrijednost na Enter ili gubitak fokusa.
class NumField extends StatefulWidget {
  const NumField({
    super.key,
    required this.label,
    required this.value,
    required this.onSubmit,
    this.suffix = 'm',
    this.decimals = 2,
  });

  final String label;
  final double value;
  final ValueChanged<double> onSubmit;
  final String suffix;
  final int decimals;

  @override
  State<NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<NumField> {
  late final TextEditingController ctrl =
      TextEditingController(text: widget.value.toStringAsFixed(widget.decimals));
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus) _submit();
    });
  }

  @override
  void didUpdateWidget(NumField old) {
    super.didUpdateWidget(old);
    if (!focus.hasFocus) ctrl.text = widget.value.toStringAsFixed(widget.decimals);
  }

  @override
  void dispose() {
    ctrl.dispose();
    focus.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(ctrl.text.replaceAll(',', '.').trim());
    if (v != null && (v - widget.value).abs() > 1e-6) {
      widget.onSubmit(v);
    } else {
      ctrl.text = widget.value.toStringAsFixed(widget.decimals);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextField(
          controller: ctrl,
          focusNode: focus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(
            isDense: true,
            labelText: widget.label,
            suffixText: widget.suffix,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
      );
}

class _Swatches extends StatelessWidget {
  const _Swatches({required this.colors, required this.value, required this.onPick});
  final List<int> colors;
  final int value;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in colors)
          InkWell(
            onTap: () => onPick(c),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                  color: c == value ? Theme.of(context).colorScheme.primary : Colors.black26,
                  width: c == value ? 3.0 : 1.0,
                ),
              ),
            ),
          ),
      ]);
}

class PropertiesPanel extends StatelessWidget {
  const PropertiesPanel({super.key, required this.c});
  final PlanController c;

  @override
  Widget build(BuildContext context) {
    final s = c.selection;
    final plan = c.plan;
    final theme = Theme.of(context);
    Widget title(String t, IconData icon) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(t, style: theme.textTheme.titleMedium)),
            IconButton(
              tooltip: 'Obriši (Del)',
              icon: const Icon(Icons.delete_outline),
              onPressed: c.deleteSelection,
            ),
          ]),
        );
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Text(t, style: theme.textTheme.labelMedium),
        );
    Key k(String f) => ValueKey('${s.id}-$f');

    final List<Widget> children;
    switch (s.kind) {
      case SelKind.wall:
        final w = plan.wallById(s.id)!;
        children = [
          title('Zid', Icons.horizontal_rule),
          NumField(key: k('len'), label: 'Duljina', value: plan.wallLength(w),
              onSubmit: (v) => c.setWallLength(w.id, v)),
          NumField(key: k('th'), label: 'Debljina', value: w.thickness * 100, suffix: 'cm', decimals: 0,
              onSubmit: (v) => c.updateWall(w.id, thickness: v / 100)),
          NumField(key: k('h'), label: 'Visina', value: w.height,
              onSubmit: (v) => c.updateWall(w.id, height: v)),
          label('Boja zida'),
          _Swatches(colors: wallColors, value: w.color, onPick: (v) => c.updateWall(w.id, color: v)),
          const SizedBox(height: 10),
          TextButton.icon(
            icon: const Icon(Icons.copy_all, size: 18),
            label: const Text('Primijeni visinu i boju na sve zidove'),
            onPressed: () => c.applyToAllWalls(height: w.height, color: w.color),
          ),
          Text('Savjet: povuci zid mišem da ga pomakneš; spojeni zidovi prate.',
              style: theme.textTheme.bodySmall),
        ];
      case SelKind.node:
        final n = plan.nodes[s.id]!;
        children = [
          title('Točka spoja', Icons.radio_button_checked),
          NumField(key: k('x'), label: 'X', value: n.pos.dx,
              onSubmit: (v) => c.mutate(() => c.setNodePos(n.id, Offset(v, n.pos.dy)))),
          NumField(key: k('y'), label: 'Y', value: n.pos.dy,
              onSubmit: (v) => c.mutate(() => c.setNodePos(n.id, Offset(n.pos.dx, v)))),
        ];
      case SelKind.opening:
        final o = plan.openingById(s.id)!;
        final ow = plan.wallById(o.wallId)!;
        final len = plan.wallLength(ow);
        children = [
          title(o.type == OpeningType.door ? 'Vrata' : 'Prozor',
              o.type == OpeningType.door ? Icons.door_front_door : Icons.window),
          SegmentedButton<OpeningType>(
            segments: const [
              ButtonSegment(value: OpeningType.door, label: Text('Vrata')),
              ButtonSegment(value: OpeningType.window, label: Text('Prozor')),
            ],
            selected: {o.type},
            onSelectionChanged: (v) => c.updateOpening(o.id, type: v.first),
          ),
          const SizedBox(height: 6),
          NumField(key: k('w'), label: 'Širina', value: o.width, onSubmit: (v) => c.updateOpening(o.id, width: v)),
          NumField(key: k('h'), label: 'Visina', value: o.height, onSubmit: (v) => c.updateOpening(o.id, height: v)),
          if (o.type == OpeningType.window)
            NumField(key: k('sill'), label: 'Parapet (od poda)', value: o.sill,
                onSubmit: (v) => c.updateOpening(o.id, sill: v)),
          NumField(key: k('off'), label: 'Udaljenost od početka zida', value: o.t * len - o.width / 2,
              onSubmit: (v) => c.updateOpening(o.id, offsetFromStart: v + o.width / 2)),
        ];
      case SelKind.item:
        final it = plan.itemById(s.id)!;
        final deg = (it.rotation * 180 / math.pi) % 360;
        children = [
          title(it.name, Icons.chair),
          if (it.retailer != null) Text(it.retailer!, style: theme.textTheme.bodySmall),
          Row(children: [
            Expanded(child: NumField(key: k('w'), label: 'Širina', value: it.w * 100, suffix: 'cm', decimals: 0,
                onSubmit: (v) => c.updateItem(it.id, w: v / 100))),
            const SizedBox(width: 6),
            Expanded(child: NumField(key: k('d'), label: 'Dubina', value: it.d * 100, suffix: 'cm', decimals: 0,
                onSubmit: (v) => c.updateItem(it.id, d: v / 100))),
          ]),
          NumField(key: k('h'), label: 'Visina', value: it.h * 100, suffix: 'cm', decimals: 0,
              onSubmit: (v) => c.updateItem(it.id, h: v / 100)),
          Row(children: [
            Expanded(
              child: NumField(key: k('rot'), label: 'Rotacija', value: deg, suffix: '°', decimals: 0,
                  onSubmit: (v) => c.updateItem(it.id, rotation: v * math.pi / 180)),
            ),
            IconButton(
                tooltip: '−90° (Shift+R)',
                icon: const Icon(Icons.rotate_left),
                onPressed: () => c.rotateItem(it.id, -math.pi / 2)),
            IconButton(
                tooltip: '+90° (R)',
                icon: const Icon(Icons.rotate_right),
                onPressed: () => c.rotateItem(it.id, math.pi / 2)),
          ]),
          label('Boja'),
          _Swatches(colors: itemColors, value: it.color, onPick: (v) => c.updateItem(it.id, color: v)),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.control_point_duplicate, size: 18),
            label: const Text('Dupliciraj (Ctrl+D)'),
            onPressed: () => c.duplicateItem(it.id),
          ),
        ];
      case SelKind.room:
        final r = plan.roomById(s.id)!;
        final poly = plan.roomPolygon(r);
        children = [
          title('Prostorija', Icons.crop_square),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: TextFormField(
              key: k('name'),
              initialValue: r.name,
              decoration: const InputDecoration(isDense: true, labelText: 'Naziv', border: OutlineInputBorder()),
              onFieldSubmitted: (v) => c.updateRoom(r.id, name: v),
            ),
          ),
          Text('Površina: ${polygonArea(poly).toStringAsFixed(2)} m²', style: theme.textTheme.bodyMedium),
          label('Pod'),
          _Swatches(colors: floorColors, value: r.floorColor, onPick: (v) => c.updateRoom(r.id, floorColor: v)),
          const SizedBox(height: 8),
          Text('Povuci prostoriju da je pomakneš zajedno sa zidovima.', style: theme.textTheme.bodySmall),
        ];
      case SelKind.none:
        final total = plan.rooms.fold<double>(0, (a, r) => a + polygonArea(plan.roomPolygon(r)));
        children = [
          Text('Projekt', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('${plan.rooms.length} prostorija · ${total.toStringAsFixed(1)} m² · '
              '${plan.walls.length} zidova · ${plan.items.length} objekata',
              style: theme.textTheme.bodySmall),
          if (plan.image != null) ...[
            label('Nacrt – prozirnost'),
            Slider(value: plan.image!.opacity, min: 0.05, max: 1, onChanged: c.setImageOpacity),
            Row(children: [
              TextButton.icon(
                icon: const Icon(Icons.straighten, size: 18),
                label: const Text('Kalibriraj'),
                onPressed: () => c.setTool(Tool.calibrate),
              ),
              TextButton.icon(
                icon: const Icon(Icons.hide_image_outlined, size: 18),
                label: const Text('Ukloni'),
                onPressed: c.removeImage,
              ),
            ]),
          ],
        ];
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
