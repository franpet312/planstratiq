import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../app/theme.dart';
import '../models/catalog_gen.dart';
import '../models/collision.dart';
import '../models/geometry.dart';
import '../models/heating.dart';
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
      SelKind.room => _room(context, c.plan.roomById(s.id)),
      SelKind.note => _note(c.plan.noteById(s.id)),
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
      if (sides <= 1) ...[
        const SectionTitle('Balkon'),
        Text('Ploča s ogradom s vanjske strane zida. Ako zid nema balkonska vrata, dodat će se na sredinu.',
            style: AppText.ui(size: 12, color: Pal.muted, height: 1.35)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (id, label) in const [('balkon', 'Staklena ograda'), ('balkon_metal', 'Metalna ograda'), ('balkon_zid', 'Zidana ograda')])
            OutlinedButton.icon(
              onPressed: () => c.addBalcony(w.id, familyId: id),
              icon: const Icon(Icons.balcony_outlined, size: 18),
              label: Text(label),
            ),
        ]),
      ],
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
      if (o.type == OpeningType.balcony && c.wallSides(w) <= 1) ...[
        const SectionTitle('Balkon ispred vrata'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (id, label) in const [('balkon', 'Staklena ograda'), ('balkon_metal', 'Metalna ograda'), ('balkon_zid', 'Zidana ograda')])
            OutlinedButton.icon(
              onPressed: () => c.addBalcony(w.id, familyId: id, openingId: o.id),
              icon: const Icon(Icons.balcony_outlined, size: 18),
              label: Text(label),
            ),
        ]),
      ],
      if (openingStyles(o.type).isNotEmpty) ...[
        const SectionTitle('Izvedba'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (id, label) in openingStyles(o.type))
            ChoiceChip(label: Text(label), selected: o.style == id, onSelected: (_) => c.updateOpening(o.id, style: id)),
        ]),
      ],
      if (o.type == OpeningType.door && (o.style == '' || o.style == 'double' || o.style == 'folding')) ...[
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
  // razmaci do zidova i namještaja: upiši broj i objekt se pomakne točno toliko od prepreke
  List<Widget> _gapFields(PlacedItem it) {
    final gaps = {for (final g in itemGaps(plan, it, maxDist: 6)) g.side: g};
    if (gaps.isEmpty) return const [];
    Widget f(String side, String label) {
      final g = gaps[side];
      if (g == null) return const Expanded(child: SizedBox());
      return Expanded(
        child: NumField(
          key: _k('gap_$side'),
          label: label,
          value: g.distance * 100,
          suffix: 'cm',
          decimals: 0,
          onSubmit: (v) => c.setItemGap(it.id, side, v / 100),
        ),
      );
    }

    return [
      const SectionTitle('Udaljenost do zida / namještaja'),
      Row(children: [f('left', 'Lijevo'), const SizedBox(width: 6), f('right', 'Desno')]),
      Row(children: [f('back', 'Iza'), const SizedBox(width: 6), f('front', 'Ispred')]),
      Text('Iste mjere vidiš na tlocrtu (narančasto, u cm). Upiši broj i objekt se pomakne točno toliko od prepreke.',
          style: AppText.ui(size: 12, color: Pal.muted, height: 1.35)),
    ];
  }

  Plan get plan => c.plan;

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
      ..._gapFields(it),
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
      const SizedBox(height: 8),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: c.collisions,
        onChanged: c.setCollisions,
        title: Text('Sudaranje', style: AppText.ui(size: 13, weight: FontWeight.w500)),
        subtitle: Text('Namještaj ne ulazi u zidove ni u drugi namještaj (stolice se smiju podvući pod stol).',
            style: AppText.ui(size: 12, color: Pal.muted, height: 1.3)),
      ),
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
  List<Widget> _room(BuildContext context, Room? r) {
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
      const SectionTitle('Zidovi prostorije'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final f in wallFinishes)
          ChoiceChip(
            avatar: CircleAvatar(backgroundColor: Color(f.id == 'paint' ? (r.wallColor ?? 0xFFF6F5F1) : f.color), radius: 7),
            label: Text(f.name, style: AppText.ui(size: 11.5)),
            visualDensity: VisualDensity.compact,
            selected: r.wallFinish == f.id,
            onSelected: (_) => c.updateRoom(r.id, wallFinish: f.id, finishHeight: f.id.startsWith('tile') && r.wallFinish == 'paint' ? 0 : null),
          ),
      ]),
      if (r.wallFinish != 'paint') ...[
        const SizedBox(height: 10),
        Text('Visina obloge', style: AppText.ui(size: 12, color: Pal.muted)),
        const SizedBox(height: 6),
        SegmentedButton<double>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 1.2, label: Text('1,2 m')),
            ButtonSegment(value: 1.5, label: Text('1,5 m')),
            ButtonSegment(value: 2.1, label: Text('2,1 m')),
            ButtonSegment(value: 0, label: Text('Cijeli zid')),
          ],
          selected: {[1.2, 1.5, 2.1, 0.0].contains(r.finishHeight) ? r.finishHeight : 0.0},
          onSelectionChanged: (v) => c.updateRoom(r.id, finishHeight: v.first),
        ),
        const SizedBox(height: 4),
        Text('≈ ${fmtEur(finishById(r.wallFinish).pricePerM2)}/m², materijal i ugradnja', style: AppText.ui(size: 12, color: Pal.muted)),
      ],
      if (r.wallFinish == 'paint' || r.finishHeight > 0) ...[
        const SizedBox(height: 10),
        Text(r.wallFinish == 'paint' ? 'Boja zidova' : 'Boja iznad obloge', style: AppText.ui(size: 12, color: Pal.muted)),
        const SizedBox(height: 6),
        Swatches(
          colors: [for (final p in wallPaints) p.color],
          names: [for (final p in wallPaints) p.name],
          value: r.wallColor ?? -1,
          onPick: (v) => c.updateRoom(r.id, wallColor: v),
        ),
      ],
      ..._furnish(context, r),
      ..._kitchen(context, r),
      ..._roomClimate(r),
      const SectionTitle('Kopiranje'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () {
            c.select(Selection(SelKind.room, r.id));
            c.copySelection();
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Prostorija je kopirana sa zidovima, vratima, prozorima i namještajem. Prebaci se na drugu etažu (ili ostani) i klikni Zalijepi ili Ctrl+V.')));
          },
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('Kopiraj prostoriju'),
        ),
      ]),
      const SizedBox(height: 10),
      Text('Prostorije se prepoznaju same iz zatvorenih zidova. Brisanjem prostorije brišu se njeni zidovi koje ne dijeli s drugima.',
          style: AppText.ui(size: 12, color: Pal.muted, height: 1.35)),
    ];
  }

  // ---------------------------------------------------------------- ništa
  List<Widget> _furnish(BuildContext context, Room r) {
    final guess = PlanController.guessRoomType(r.name);
    const types = [
      ('bedroom', 'Spavaća soba'),
      ('living', 'Dnevni boravak'),
      ('dining', 'Blagovaonica'),
      ('kids', 'Dječja soba'),
      ('office', 'Radna soba'),
      ('bath', 'Kupaonica'),
      ('hall', 'Predsoblje'),
    ];
    void go(String type) {
      final msg = c.furnishRoom(r.id, type, styleId: _furnishStyle);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
    }

    return [
      const SectionTitle('Opremi prostoriju'),
      Text('Postavi namještaj sam – uz zidove, mimo vrata i prozora, bez sudaranja. Postojeći namještaj u prostoriji se zamjenjuje (Ctrl+Z vraća).',
          style: AppText.ui(size: 12, color: Pal.muted, height: 1.35)),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: () => go(guess),
        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
        label: Text('Opremi kao: ${types.firstWhere((t) => t.$1 == guess).$2}'),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (id, label) in types)
          if (id != guess) ActionChip(label: Text(label), visualDensity: VisualDensity.compact, onPressed: () => go(id)),
      ]),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        value: _furnishStyle,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Stil namještaja', isDense: true),
        items: [for (final st in styles) DropdownMenuItem(value: st.id, child: Text('${st.name} (${st.series})'))],
        onChanged: (v) => _furnishStyle = v ?? 'skandi',
      ),
    ];
  }

  List<Widget> _kitchen(BuildContext context, Room r) {
    void go(String layout, {bool island = false}) {
      final msg = c.addKitchen(r.id, layout, island: island);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }

    return [
      const SectionTitle('Kuhinja'),
      Text('Kuhinja uz zidove ove prostorije: donji i gornji elementi, radna ploča, sudoper, ploča za kuhanje i hladnjak. '
          'Ispod prozora idu samo donji elementi, a vrata se zaobilaze.',
          style: AppText.ui(size: 12, color: Pal.muted, height: 1.35)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        OutlinedButton(onPressed: () => go('I'), child: const Text('Uz jedan zid')),
        OutlinedButton(onPressed: () => go('L'), child: const Text('L')),
        OutlinedButton(onPressed: () => go('U'), child: const Text('U')),
        OutlinedButton(onPressed: () => go('L', island: true), child: const Text('L + otok')),
      ]),
    ];
  }

  List<Widget> _roomClimate(Room r) {
    final rc = roomClimate(c.plan).where((x) => x.room.id == r.id).firstOrNull;
    return [
      const SectionTitle('Grijanje i hlađenje'),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: r.floorHeating,
        onChanged: (v) => c.updateRoom(r.id, floorHeating: v),
        title: Text('Podno grijanje', style: AppText.ui(size: 13, weight: FontWeight.w500)),
        subtitle: Text('oko ${floorHeatingWPerM2.round()} W/m², ≈ ${fmtEur(floorHeatingPricePerM2)}/m²', style: AppText.ui(size: 12, color: Pal.muted)),
      ),
      if (rc != null) ...[
        StatRow('Treba za grijanje', fmtKw(rc.heatNeed)),
        StatRow('Ugrađeno grijanje', '${fmtKw(rc.heat)}  ${rc.heatOk ? '✓' : '– nedostaje ${fmtKw(rc.heatNeed - rc.heat)}'}'),
        StatRow('Hlađenje (treba / ima)', '${fmtKw(rc.coolNeed)} / ${fmtKw(rc.cool)}'),
        const SizedBox(height: 4),
        Text('Radijatori, klima i peć u ovoj prostoriji zbrajaju se sami (katalog: Grijanje i hlađenje). Okvirno, prema izolaciji kuće.',
            style: AppText.ui(size: 12, color: Pal.muted, height: 1.35)),
      ],
    ];
  }

  List<Widget> _note(Note? n) {
    if (n == null) return [];
    return [
      _header('Bilješka', Icons.sticky_note_2_outlined, subtitle: 'Vidi se na tlocrtu i u PDF-u'),
      const SizedBox(height: 10),
      _NoteEditor(key: ValueKey(n.id), c: c, note: n),
      const SizedBox(height: 10),
      Swatches(
        colors: const [0xFFFFE58A, 0xFFFFC9A8, 0xFFC8E6C9, 0xFFBBDEFB, 0xFFE1BEE7],
        names: const ['Žuta', 'Narančasta', 'Zelena', 'Plava', 'Ljubičasta'],
        value: n.color,
        onPick: (v) => c.updateNote(n.id, color: v),
      ),
    ];
  }

  List<Widget> _site() {
    final st = c.plan.site;
    final r = c.siteRect();
    Widget chips<T>(List<(T, String)> opts, T value, void Function(T) on) => Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (v, label) in opts)
            ChoiceChip(label: Text(label), selected: value == v, visualDensity: VisualDensity.compact, onSelected: (_) => on(v)),
        ]);
    Widget slider(String label, String value, double v, double min, double max, void Function(double) set) => Row(children: [
          SizedBox(width: 78, child: Text(label, style: AppText.ui(size: 12.5))),
          Expanded(
            child: Slider(
              value: v.clamp(min, max),
              min: min,
              max: max,
              onChangeStart: (_) => c.beginChange(),
              onChanged: (x) {
                set(x);
                c.liveUpdate();
              },
              onChangeEnd: (_) => c.endChange(),
            ),
          ),
          SizedBox(width: 48, child: Text(value, textAlign: TextAlign.right, style: AppText.narrow(size: 12.5))),
        ]);
    return [
      const SectionTitle('Parcela i okolina'),
      Text('Okolina', style: AppText.ui(size: 12, color: Pal.muted)),
      const SizedBox(height: 6),
      chips([('suburb', 'Susjedstvo'), ('countryside', 'Selo'), ('city', 'Grad'), ('none', 'Bez okoline')], st.surroundings,
          (v) => c.updateSite((s) => s.surroundings = v)),
      const SizedBox(height: 10),
      Text('Ulica je s ove strane parcele', style: AppText.ui(size: 12, color: Pal.muted)),
      const SizedBox(height: 6),
      chips([('S', 'Dolje (jug)'), ('N', 'Gore (sjever)'), ('E', 'Desno (istok)'), ('W', 'Lijevo (zapad)')], st.street,
          (v) => c.updateSite((s) => s.street = v)),
      const SizedBox(height: 10),
      Text('Ograda', style: AppText.ui(size: 12, color: Pal.muted)),
      const SizedBox(height: 6),
      chips([('wood', 'Drvena'), ('metal', 'Metalna'), ('panel', 'Žičana'), ('hedge', 'Živica'), ('wall', 'Zid'), ('none', 'Bez')], st.fence,
          (v) => c.updateSite((s) => s.fence = v)),
      if (st.fence != 'none') slider('Visina', '${fmtM(st.fenceHeight, 1)} m', st.fenceHeight, 0.5, 2.0, (x) => st.fenceHeight = (x * 10).round() / 10),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: st.driveway,
        onChanged: (v) => c.updateSite((s) => s.driveway = v),
        title: Text('Prilaz i staza do ulaznih vrata', style: AppText.ui(size: 13)),
      ),
      if (r != null) ...[
        slider('Širina', '${fmtM(r.width, 1)} m', r.width, 8, 80, (x) => st.width = x.roundToDouble()),
        slider('Dubina', '${fmtM(r.height, 1)} m', r.height, 8, 100, (x) => st.depth = x.roundToDouble()),
        slider('Pomak ↔', '${fmtM(st.offsetX, 1)} m', st.offsetX, -20, 20, (x) => st.offsetX = (x * 2).round() / 2),
        slider('Pomak ↕', '${fmtM(st.offsetY, 1)} m', st.offsetY, -20, 20, (x) => st.offsetY = (x * 2).round() / 2),
        Row(children: [
          Expanded(child: Text('Površina parcele ${fmtM(r.width * r.height, 0)} m²', style: AppText.ui(size: 12, color: Pal.muted))),
          TextButton(
            onPressed: () => c.updateSite((s) {
              s.width = 0;
              s.depth = 0;
              s.offsetX = 0;
              s.offsetY = 0;
            }),
            child: const Text('Automatski'),
          ),
        ]),
      ],
    ];
  }

  List<Widget> _roof() {
    final p = c.plan;
    Widget slider(String label, String value, double v, double min, double max, int div, void Function(double) set) => Row(children: [
          SizedBox(width: 72, child: Text(label, style: AppText.ui(size: 12.5))),
          Expanded(
            child: Slider(
              value: v.clamp(min, max),
              min: min,
              max: max,
              divisions: div,
              onChangeStart: (_) => c.beginChange(),
              onChanged: (x) {
                set(x);
                c.plan.roof = true;
                c.liveUpdate();
              },
              onChangeEnd: (_) => c.endChange(),
            ),
          ),
          SizedBox(width: 44, child: Text(value, textAlign: TextAlign.right, style: AppText.narrow(size: 12.5))),
        ]);
    return [
      const SectionTitle('Krov'),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: p.roof,
        onChanged: c.setRoof,
        title: Text('Prikaži krov u 3D-u', style: AppText.ui(size: 13, weight: FontWeight.w500)),
        subtitle: Text('Krov prati obris najviše etaže (i L, T i U kuće).', style: AppText.ui(size: 12, color: Pal.muted)),
      ),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (id, label) in const [('gable', 'Dvostrešni'), ('hip', 'Četverostrešni'), ('shed', 'Jednostrešni'), ('flat', 'Ravni')])
          ChoiceChip(
            label: Text(label),
            selected: p.roofType == id,
            onSelected: (_) => c.setRoofStyle(
              type: id,
              // jednostrešni krov preko cijele kuće treba manji nagib
              pitch: id == 'shed' && p.roofPitch > 15 ? 10 : (id != 'shed' && p.roofType == 'shed' && p.roofPitch < 20 ? 30 : null),
            ),
          ),
      ]),
      if (p.roofType != 'flat') ...[
        const SizedBox(height: 6),
        slider('Nagib', '${p.roofPitch.round()}°', p.roofPitch, 5, 60, 55, (x) => p.roofPitch = x.roundToDouble()),
        slider('Prepust', '${(p.roofOverhang * 100).round()} cm', p.roofOverhang, 0, 1.5, 30, (x) => p.roofOverhang = (x * 20).round() / 20),
        if (p.roofType == 'gable' || p.roofType == 'shed')
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: p.roofTurn,
            onChanged: (v) => c.setRoofStyle(turn: v),
            title: Text(p.roofType == 'shed' ? 'Zakreni smjer pada' : 'Zakreni sljeme za 90°', style: AppText.ui(size: 13)),
          ),
      ],
      const SizedBox(height: 6),
      Swatches(
        colors: const [0xFFA5533A, 0xFF8C3B2A, 0xFF5E4033, 0xFF3F4347, 0xFF6E7378, 0xFF2F4A3A, 0xFFB9B3A8],
        names: const ['Crijep', 'Tamni crijep', 'Smeđi', 'Antracit', 'Sivi lim', 'Zeleni', 'Svijetli'],
        value: p.roofColor,
        onPick: (v) => c.setRoofStyle(color: v),
      ),
    ];
  }

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
      if (c.clipboardLabel != null) ...[
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: c.paste,
          icon: const Icon(Icons.content_paste, size: 18),
          label: Text('Zalijepi ${c.clipboardLabel}'),
        ),
      ],
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
      ..._roof(),
      ..._site(),
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


class _NoteEditor extends StatefulWidget {
  const _NoteEditor({super.key, required this.c, required this.note});
  final PlanController c;
  final Note note;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final ctl = TextEditingController(text: widget.note.text);
  final focus = FocusNode();
  String? _before;

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (focus.hasFocus) {
        _before = widget.note.text;
      } else {
        _commit();
      }
    });
  }

  void _commit() {
    final t = ctl.text.trim();
    if (_before != null && t != _before) {
      widget.note.text = _before!; // da poništavanje vrati prijašnji tekst
      widget.c.updateNote(widget.note.id, text: t);
    }
    _before = null;
  }

  @override
  void dispose() {
    if (focus.hasFocus) _commit();
    ctl.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: ctl,
        focusNode: focus,
        minLines: 2,
        maxLines: 6,
        decoration: const InputDecoration(labelText: 'Tekst bilješke'),
        onChanged: (v) {
          widget.note.text = v;
          widget.c.liveUpdate();
        },
      );
}

/// Zadnji odabrani stil za automatsko opremanje (pamti se dok je aplikacija otvorena).
String _furnishStyle = 'skandi';
