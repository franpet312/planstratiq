import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../app/theme.dart';
import '../models/catalog_gen.dart';
import '../models/geometry.dart';
import '../models/materials.dart';
import '../models/plan.dart';
import '../models/topology.dart';
import '../state/plan_controller.dart';
import 'catalog_panel.dart';
import 'common.dart';
import 'detect_flow.dart';

const itemColors = [
  0xFFFFFFFF, 0xFFEDE7DF, 0xFFD9C7B0, 0xFFB08D6E, 0xFF8C6A4F, 0xFF5A4636,
  0xFF7C8B99, 0xFF5F6B63, 0xFF3D3D3D, 0xFF4F7F4A, 0xFFB5574B, 0xFF2F5A8A,
];

/// Svojstva odabranog elementa (ili sažetak projekta kad ništa nije odabrano).
class PropertiesPanel extends StatelessWidget {
  const PropertiesPanel({super.key, required this.c, this.onCalibrate});
  final PlanController c;
  final VoidCallback? onCalibrate;

  @override
  Widget build(BuildContext context) {
    final s = c.selection;
    final children = switch (s.kind) {
      SelKind.wall => _wall(c.plan.wallById(s.id)),
      SelKind.node => _node(c.plan.nodes[s.id]),
      SelKind.opening => _opening(c.plan.openingById(s.id)),
      SelKind.item => _item(c.plan.itemById(s.id)),
      SelKind.room => _room(c.plan.roomById(s.id)),
      SelKind.none => _none(context),
    };
    return ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 20), children: children);
  }

  Key _k(String f) => ValueKey('${c.selection.id}-$f');

  Widget _header(String title, IconData icon, {String? subtitle, bool deletable = true}) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: Pal.accentSoft, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 19, color: Pal.accentDeep),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppText.ui(size: 15, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle != null) Text(subtitle, style: AppText.ui(size: 12, color: Pal.muted)),
            ]),
          ),
          if (deletable)
            IconBtn(icon: Icons.delete_outline, tooltip: 'Obriši (Delete)', onTap: c.deleteSelection),
        ]),
      );

  Widget _row(List<Widget> fields) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: fields[i]),
          ]
        ]),
      );

  // ---------------------------------------------------------------- zid
  List<Widget> _wall(Wall? w) {
    if (w == null) return [];
    final sides = c.wallSides(w);
    final len = c.plan.wallLength(w);
    return [
      _header('Zid', Icons.view_agenda_outlined,
          subtitle: sides <= 1 ? 'Vanjski zid' : 'Unutarnji zid, između dvije prostorije'),
      const SizedBox(height: 10),
      _row([
        NumField(key: _k('len'), label: 'Duljina', value: len, onSubmit: (v) => c.setWallLength(w.id, v)),
        NumField(key: _k('th'), label: 'Debljina', value: w.thickness * 100, suffix: 'cm', decimals: 0,
            onSubmit: (v) => c.updateWall(w.id, thickness: v / 100)),
      ]),
      _row([
        NumField(key: _k('h'), label: 'Visina', value: w.height, onSubmit: (v) => c.updateWall(w.id, height: v)),
        const SizedBox(),
      ]),
      Text('Povuci zid na tlocrtu da ga pomakneš; spojeni zidovi i prostorije prate promjenu.',
          style: AppText.ui(size: 12, color: Pal.muted, height: 1.35)),
      const SectionTitle('Boja zida iznutra'),
      Swatches(
        colors: [for (final p in wallPaints) p.color],
        names: [for (final p in wallPaints) p.name],
        value: w.color,
        onPick: (v) => c.updateWall(w.id, color: v),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton(onPressed: () => c.applyToAllWalls(color: w.color), child: const Text('Ova boja na sve zidove')),
        OutlinedButton(onPressed: () => c.applyToAllWalls(height: w.height), child: const Text('Ova visina na sve zidove')),
      ]),
      const SectionTitle('Dodaj na ovaj zid'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in OpeningType.values)
          OutlinedButton.icon(
            onPressed: () => c.mutate(() => c.addOpening(w.id, t, 0.5)),
            icon: Icon(_openingIcon(t), size: 18),
            label: Text(t.label),
          ),
      ]),
    ];
  }

  List<Widget> _node(PlanNode? n) {
    if (n == null) return [];
    return [
      _header('Kut zidova', Icons.radio_button_checked, subtitle: 'Povuci da promijeniš oblik prostorije'),
      const SizedBox(height: 10),
      _row([
        NumField(key: _k('x'), label: 'X', value: n.pos.dx, onSubmit: (v) => c.mutate(() => c.setNodePos(n.id, Offset(v, n.pos.dy)))),
        NumField(key: _k('y'), label: 'Y', value: n.pos.dy, onSubmit: (v) => c.mutate(() => c.setNodePos(n.id, Offset(n.pos.dx, v)))),
      ]),
    ];
  }

  // ---------------------------------------------------------------- otvor
  IconData _openingIcon(OpeningType t) => switch (t) {
        OpeningType.door => Icons.door_front_door_outlined,
        OpeningType.window => Icons.window_outlined,
        OpeningType.balcony => Icons.balcony_outlined,
        OpeningType.passage => Icons.space_bar,
      };

  List<Widget> _opening(Opening? o) {
    if (o == null) return [];
    final w = c.plan.wallById(o.wallId);
    if (w == null) return [];
    final len = c.plan.wallLength(w);
    return [
      _header(o.type.label, _openingIcon(o.type), subtitle: 'Povuci duž zida da ga pomakneš'),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final t in OpeningType.values)
          ChoiceChip(
            label: Text(t.label),
            selected: o.type == t,
            onSelected: (_) => c.updateOpening(o.id, type: t),
            labelStyle: AppText.ui(size: 12, weight: FontWeight.w500, color: o.type == t ? Pal.accentDeep : Pal.inkSoft),
            selectedColor: Pal.accentSoft,
            side: BorderSide(color: o.type == t ? Pal.accent : Pal.line),
            showCheckmark: false,
          ),
      ]),
      const SizedBox(height: 12),
      _row([
        NumField(key: _k('w'), label: 'Širina', value: o.width * 100, suffix: 'cm', decimals: 0,
            onSubmit: (v) => c.updateOpening(o.id, width: v / 100)),
        NumField(key: _k('h'), label: 'Visina', value: o.height * 100, suffix: 'cm', decimals: 0,
            onSubmit: (v) => c.updateOpening(o.id, height: v / 100)),
      ]),
      _row([
        NumField(key: _k('off'), label: 'Od početka zida', value: o.t * len - o.width / 2,
            onSubmit: (v) => c.updateOpening(o.id, offsetFromStart: v + o.width / 2)),
        if (o.type == OpeningType.window)
          NumField(key: _k('sill'), label: 'Parapet', value: o.sill * 100, suffix: 'cm', decimals: 0,
              onSubmit: (v) => c.updateOpening(o.id, sill: v / 100))
        else
          const SizedBox(),
      ]),
      if (o.type == OpeningType.door) ...[
        const SectionTitle('Otvaranje'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: () => c.updateOpening(o.id, flip: !o.flip),
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Šarke na drugu stranu'),
          ),
          OutlinedButton.icon(
            onPressed: () => c.updateOpening(o.id, swingOut: !o.swingOut),
            icon: const Icon(Icons.swap_vert, size: 18),
            label: const Text('Otvaranje u drugu prostoriju'),
          ),
        ]),
      ],
    ];
  }

  // ---------------------------------------------------------------- objekt
  List<Widget> _item(PlacedItem? it) {
    if (it == null) return [];
    final cat = catalogById(it.catalogId);
    final deg = ((it.rotation * 180 / math.pi) % 360 + 360) % 360;
    return [
      _header(it.name, shapeIcons[it.shape] ?? Icons.chair_outlined,
          subtitle: [if (cat != null) cat.category, if (it.price != null) '≈ ${fmtEur(it.price!)}'].join(', ')),
      const SizedBox(height: 10),
      _row([
        NumField(key: _k('w'), label: 'Širina', value: it.w * 100, suffix: 'cm', decimals: 0, onSubmit: (v) => c.updateItem(it.id, w: v / 100)),
        NumField(key: _k('d'), label: 'Dubina', value: it.d * 100, suffix: 'cm', decimals: 0, onSubmit: (v) => c.updateItem(it.id, d: v / 100)),
        NumField(key: _k('h'), label: 'Visina', value: it.h * 100, suffix: 'cm', decimals: 0, onSubmit: (v) => c.updateItem(it.id, h: v / 100)),
      ]),
      Row(children: [
        Expanded(
          child: NumField(key: _k('rot'), label: 'Rotacija', value: deg, suffix: '°', decimals: 0,
              onSubmit: (v) => c.updateItem(it.id, rotation: v * math.pi / 180)),
        ),
        const SizedBox(width: 6),
        IconBtn(icon: Icons.rotate_left, tooltip: 'Okreni −90° (Shift+R)', onTap: () => c.rotateItem(it.id, -math.pi / 2)),
        IconBtn(icon: Icons.rotate_right, tooltip: 'Okreni +90° (R)', onTap: () => c.rotateItem(it.id, math.pi / 2)),
      ]),
      const SizedBox(height: 6),
      Text('Na tlocrtu povuci kružić iznad objekta za slobodnu rotaciju, strelicama ga pomakni za 1 cm.',
          style: AppText.ui(size: 12, color: Pal.muted, height: 1.35)),
      if (cat?.variant != null || it.productUrl != null) ...[
        const SizedBox(height: 10),
        if (cat?.variant != null) Text('Varijanta: ${cat!.variant}', style: AppText.ui(size: 12, color: Pal.inkSoft)),
        if (it.productUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: OutlinedButton.icon(
              onPressed: () => web.window.open(it.productUrl!, '_blank'),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(it.retailer == null ? 'Otvori proizvod' : 'Otvori u trgovini ${it.retailer}'),
            ),
          ),
      ],
      const SectionTitle('Boja'),
      Swatches(colors: itemColors, value: it.color, onPick: (v) => c.updateItem(it.id, color: v)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () => c.duplicateItem(it.id),
          icon: const Icon(Icons.copy_all_outlined, size: 18),
          label: const Text('Dupliciraj'),
        ),
        if (cat != null)
          OutlinedButton.icon(
            onPressed: () => c.updateItem(it.id, w: cat.w, d: cat.d, h: cat.h, color: cat.color),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Vrati izvorne mjere'),
          ),
      ]),
    ];
  }

  // ---------------------------------------------------------------- prostorija
  List<Widget> _room(Room? r) {
    if (r == null) return [];
    final poly = c.plan.roomPolygon(r);
    final area = roomNetArea(c.plan, r);
    final mat = floorById(r.floor);
    return [
      _header(r.name, Icons.crop_square, subtitle: 'Neto ${fmtM2(area)}, opseg ${fmtM(polygonPerimeter(poly))} m'),
      const SizedBox(height: 10),
      TextFormField(
        key: _k('name'),
        initialValue: r.name,
        decoration: const InputDecoration(labelText: 'Naziv prostorije'),
        onFieldSubmitted: (v) => c.updateRoom(r.id, name: v.trim().isEmpty ? r.name : v.trim()),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final n in const ['Dnevni boravak', 'Kuhinja', 'Spavaća soba', 'Dječja soba', 'Kupaonica', 'Hodnik', 'Radna soba', 'Ostava'])
          ActionChip(
            label: Text(n, style: AppText.ui(size: 11.5)),
            visualDensity: VisualDensity.compact,
            side: const BorderSide(color: Pal.line),
            backgroundColor: Colors.white,
            onPressed: () => c.updateRoom(r.id, name: n),
          ),
      ]),
      const SectionTitle('Pod'),
      for (final m in floorMaterials)
        _MaterialTile(material: m, selected: m.id == r.floor, area: area, onTap: () => c.updateRoom(r.id, floor: m.id)),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: () => c.setAllFloors(mat.id), child: Text('${mat.name} u svim prostorijama')),
      const SizedBox(height: 10),
      Text('Prostorije se prepoznaju same iz zatvorenih zidova. Brisanjem prostorije brišu se njeni zidovi koje ne dijeli s drugima.',
          style: AppText.ui(size: 12, color: Pal.muted, height: 1.35)),
    ];
  }

  // ---------------------------------------------------------------- ništa
  List<Widget> _none(BuildContext context) {
    final st = c.stats;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text('Ništa nije odabrano', style: AppText.ui(size: 15, weight: FontWeight.w700)),
      ),
      const SizedBox(height: 4),
      Text('Klikni zid, prostoriju, vrata ili komad namještaja da vidiš i promijeniš njegove mjere.',
          style: AppText.ui(size: 12.5, color: Pal.muted, height: 1.4)),
      const SectionTitle('Projekt'),
      StatRow('Neto površina', fmtM2(st.netArea), strong: true),
      StatRow('Tlocrtna (bruto) površina', fmtM2(st.footprint)),
      StatRow('Prostorija', '${st.rooms.length}'),
      StatRow('Vrata i prozori', '${st.doors} / ${st.windows}'),
      const SectionTitle('Zidovi'),
      Row(children: [
        Expanded(
          child: NumField(
            key: const ValueKey('wall-height-all'),
            label: 'Visina novih zidova',
            value: c.plan.wallHeight,
            onSubmit: (v) => c.mutate(() {
              c.plan.wallHeight = v.clamp(2.0, 6.0);
              c.plan.restackLevels();
            }),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: () => c.applyToAllWalls(height: c.plan.wallHeight), child: const Text('Na sve')),
      ]),
      if (c.plan.image != null) ...[
        const SectionTitle('Nacrt u pozadini'),
        Row(children: [
          Text('Prozirnost', style: AppText.ui(size: 12.5)),
          Expanded(child: Slider(value: c.plan.image!.opacity, min: 0.05, max: 1, onChanged: c.setImageOpacity)),
        ]),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: () => runDetection(context, c),
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Prepoznaj zidove'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              c.setTool(Tool.calibrate);
              onCalibrate?.call();
            },
            icon: const Icon(Icons.straighten, size: 18),
            label: const Text('Postavi mjerilo'),
          ),
          OutlinedButton.icon(onPressed: c.removeImage, icon: const Icon(Icons.hide_image_outlined, size: 18), label: const Text('Ukloni nacrt')),
        ]),
      ],
      const SectionTitle('Prečaci'),
      for (final (k, v) in const [
        ('V', 'Odabir i pomicanje'),
        ('W', 'Crtanje zidova (upiši duljinu + Enter)'),
        ('R', 'Prostorija (povuci pravokutnik)'),
        ('D / P', 'Vrata / prozor'),
        ('M', 'Mjerenje'),
        ('Ctrl+Z', 'Poništi'),
        ('Del', 'Obriši odabrano'),
        ('0', 'Prikaži cijeli tlocrt'),
      ])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(
              constraints: const BoxConstraints(minWidth: 50),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Pal.paper, borderRadius: BorderRadius.circular(5), border: Border.all(color: Pal.line)),
              child: Text(k, textAlign: TextAlign.center, style: AppText.narrow(size: 11.5, weight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(v, style: AppText.ui(size: 12.5, color: Pal.inkSoft))),
          ]),
        ),
    ];
  }
}

class _MaterialTile extends StatelessWidget {
  const _MaterialTile({required this.material, required this.selected, required this.area, required this.onTap});
  final FloorMaterial material;
  final bool selected;
  final double area;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: selected ? Pal.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(children: [
                Container(
                  width: 30,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Color(material.color),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: selected ? Pal.accent : Pal.line),
                  ),
                  child: CustomPaint(painter: _TexturePainter(material.texture)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(material.name, style: AppText.ui(size: 12.5, weight: selected ? FontWeight.w600 : FontWeight.w400))),
                Text('${material.pricePerM2.round()} €/m²', style: AppText.narrow(size: 11.5, color: Pal.muted)),
              ]),
            ),
          ),
        ),
      );
}

class _TexturePainter extends CustomPainter {
  _TexturePainter(this.kind);
  final String kind;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black.withAlpha(40)
      ..strokeWidth = 1;
    switch (kind) {
      case 'wood':
        for (var y = 5.0; y < size.height; y += 5) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      case 'tile':
      case 'largeTile':
      case 'stone':
        final step = kind == 'tile' ? 7.5 : 11.0;
        for (var y = step; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
        for (var x = step; x < size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _TexturePainter old) => old.kind != kind;
}
