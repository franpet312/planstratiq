import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../app/theme.dart';
import '../models/catalog.dart';
import '../models/geometry.dart';
import '../state/plan_controller.dart';
import '../ui/common.dart';
import '../ui/web_files.dart';
import 'engine_bridge.dart';

/// Izvana (orbit), treće lice (lik) i prvo lice (šetnja).
enum ViewMode3D { orbit, third, walk }

class Viewer3D extends StatefulWidget {
  const Viewer3D({super.key, required this.c, this.compact = false});
  final PlanController c;
  final bool compact;

  @override
  State<Viewer3D> createState() => _Viewer3DState();
}

class _Viewer3DState extends State<Viewer3D> {
  static ViewMode3D _mode = ViewMode3D.orbit;
  static double _hour = 15;
  final engine = Engine3D.instance;
  int _sentRevision = -1;
  Selection _sentSel = Selection.none;
  Timer? _debounce;
  bool _timeOpen = false;
  bool _measure = false;
  static bool _showAll = false;

  PlanController get c => widget.c;

  @override
  void initState() {
    super.initState();
    c.addListener(_onPlanChanged);
    engine.addListener(_onEngine);
  }

  @override
  void dispose() {
    c.removeListener(_onPlanChanged);
    engine.removeListener(_onEngine);
    _debounce?.cancel();
    c.walker.value = null;
    super.dispose();
  }

  void _onPlanChanged() {
    if (c.selection != _sentSel) {
      _sentSel = c.selection;
      engine.setSelection(c.selection);
    }
    if (c.revision == _sentRevision) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 30), _push);
  }

  void _push() {
    _sentRevision = c.revision;
    engine.setPlan(c);
    engine.setSelection(c.selection);
  }

  void _onEngine(String type, Object? data) {
    if (!mounted) return;
    switch (type) {
      case 'level':
        // hodanje stubištem: prijeđi na etažu iznad/ispod
        final dir = ((data as Map)['dir'] as num).toInt();
        c.switchLevel(c.plan.active + dir);
      case 'select':
        final m = data as Map;
        final kind = switch (m['kind']) {
          'item' => SelKind.item,
          'wall' => SelKind.wall,
          'room' => SelKind.room,
          _ => SelKind.none,
        };
        c.select(kind == SelKind.none ? Selection.none : Selection(kind, m['id'] as String));
      case 'move':
        final m = data as Map;
        final it = c.plan.itemById(m['id'] as String);
        if (it != null) {
          c.mutate(() => c.setItemPos(it.id, Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble())));
          _push(); // i kad se objekt nije pomaknuo (sudar), vrati ga na pravo mjesto u 3D-u
        }
      case 'pose':
        if (data == null) {
          c.walker.value = null;
        } else {
          final m = data as Map;
          c.walker.value = (Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble()), (m['yaw'] as num).toDouble());
        }
    }
  }

  void _setMode(ViewMode3D m) {
    setState(() => _mode = m);
    engine.setMode(m.name);
  }

  void _snapshot() {
    final png = engine.screenshotPng();
    if (png == null) return;
    downloadBytes(png, '${c.plan.name.isEmpty ? 'planstratiq' : c.plan.name} – 3D.png', mime: 'image/png');
  }

  @override
  Widget build(BuildContext context) {
    final rooms = c.stats.rooms.where((r) => r.levelIndex == c.plan.active).toList();
    return DragTarget<CatalogItem>(
      onAcceptWithDetails: (d) {
        final rb = context.findRenderObject() as RenderBox?;
        if (rb == null) return;
        final p = engine.groundPoint(rb.globalToLocal(d.offset));
        if (p != null) c.mutate(() => c.placeItemSmart(d.data, Offset(roundTo(p.dx, 0.01), roundTo(p.dy, 0.01))));
      },
      builder: (context, cand, rej) => Stack(children: [
        Positioned.fill(
          child: HtmlElementView.fromTagName(
            tagName: 'div',
            onElementCreated: (Object element) {
              final el = element as web.HTMLElement;
              el.style.width = '100%';
              el.style.height = '100%';
              engine.mount(el);
              engine.setMode(_mode.name);
              engine.setTime(_hour);
              engine.setShowAll(_showAll);
              _push();
            },
          ),
        ),
        if (cand.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: Pal.accent, width: 3), color: Pal.accent.withAlpha(20)),
              ),
            ),
          ),
        Positioned(
          top: 12,
          left: 12,
          child: FloatPanel(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconBtn(
                icon: Icons.threed_rotation,
                tooltip: 'Pogled izvana: okretanje, zoom, odabir i pomicanje namještaja',
                label: widget.compact ? null : 'Izvana',
                active: _mode == ViewMode3D.orbit,
                onTap: () => _setMode(ViewMode3D.orbit),
              ),
              const SizedBox(width: 2),
              IconBtn(
                icon: Icons.person_outline,
                tooltip: 'Treće lice: lik hoda kućom, kamera ga prati',
                label: widget.compact ? null : 'Treće lice',
                active: _mode == ViewMode3D.third,
                onTap: () => _setMode(ViewMode3D.third),
              ),
              const SizedBox(width: 2),
              IconBtn(
                icon: Icons.visibility_outlined,
                tooltip: 'Prvo lice: gledaš kroz oči osobe',
                label: widget.compact ? null : 'Prvo lice',
                active: _mode == ViewMode3D.walk,
                onTap: () => _setMode(ViewMode3D.walk),
              ),
            ]),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            FloatPanel(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconBtn(
                  icon: _hour < 7.5 || _hour > 18.5 ? Icons.wb_twilight : Icons.wb_sunny_outlined,
                  tooltip: 'Doba dana i sjene',
                  active: _timeOpen,
                  onTap: () => setState(() => _timeOpen = !_timeOpen),
                ),
                IconBtn(
                  icon: Icons.roofing,
                  tooltip: c.plan.roof ? 'Sakrij krov' : 'Prikaži krov',
                  active: c.plan.roof,
                  onTap: () {
                    final on = !c.plan.roof;
                    c.setRoof(on);
                    if (on) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                        content: Text('Oblik, nagib i boju krova mijenjaš u desnom panelu kad ništa nije odabrano.'),
                        duration: Duration(seconds: 3),
                      ));
                    }
                  },
                ),
                IconBtn(
                  icon: Icons.straighten,
                  tooltip: _measure ? 'Završi mjerenje' : 'Izmjeri udaljenost: klikni dvije točke',
                  active: _measure,
                  onTap: () {
                    setState(() => _measure = !_measure);
                    engine.setMeasure(_measure);
                  },
                ),
                if (_mode == ViewMode3D.orbit && c.plan.levels.length > 1)
                  IconBtn(
                    icon: Icons.layers_outlined,
                    tooltip: _showAll ? 'Prikaži samo do odabrane etaže' : 'Prikaži sve etaže',
                    active: _showAll,
                    onTap: () {
                      setState(() => _showAll = !_showAll);
                      engine.setShowAll(_showAll);
                    },
                  ),
                IconBtn(icon: Icons.photo_camera_outlined, tooltip: 'Spremi sliku ovog prikaza', onTap: _snapshot),
                if (_mode == ViewMode3D.orbit)
                  IconBtn(icon: Icons.center_focus_strong_outlined, tooltip: 'Centriraj pogled na kuću', onTap: engine.frame),
              ]),
            ),
            if (_timeOpen) ...[
              const SizedBox(height: 8),
              FloatPanel(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                child: SizedBox(
                  width: 230,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('Doba dana', style: AppText.ui(size: 12, weight: FontWeight.w600, color: Pal.muted)),
                      const Spacer(),
                      Text('${_hour.floor() % 24}:${((_hour % 1) * 60).round().toString().padLeft(2, '0')} h',
                          style: AppText.narrow(size: 14, weight: FontWeight.w700)),
                    ]),
                    Slider(
                      value: _hour,
                      min: 0,
                      max: 24,
                      divisions: 96,
                      onChanged: (v) {
                        setState(() => _hour = v);
                        engine.setTime(v);
                      },
                    ),
                    Text(_hour < 5.5 || _hour > 20.5 ? 'Noć: svijetle lampe i lusteri koje si postavio.' : 'Sjever je na vrhu tlocrta.',
                        style: AppText.ui(size: 11.5, color: Pal.muted)),
                  ]),
                ),
              ),
            ],
          ]),
        ),
        if (_mode != ViewMode3D.orbit && rooms.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 56,
            child: Center(
              child: FloatPanel(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Idi u', style: AppText.ui(size: 12, color: Pal.muted)),
                    ),
                    for (final r in rooms)
                      Padding(
                        padding: const EdgeInsets.all(2),
                        child: ActionChip(
                          label: Text(r.room.name, style: AppText.ui(size: 12, weight: FontWeight.w500)),
                          visualDensity: VisualDensity.compact,
                          side: const BorderSide(color: Pal.line),
                          backgroundColor: Colors.white,
                          onPressed: () => engine.walkTo(labelPoint(c.plan.roomPolygon(r.room))),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        if (c.plan.levels.length > 1)
          Positioned(
            right: 12,
            top: 64,
            child: FloatPanel(
              padding: const EdgeInsets.all(4),
              child: IntrinsicWidth(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = c.plan.levels.length - 1; i >= 0; i--)
                  InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: () => c.switchLevel(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: i == c.plan.active ? Pal.accentSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(c.plan.levels[i].name,
                          style: AppText.ui(
                              size: 12,
                              weight: FontWeight.w600,
                              color: i == c.plan.active ? Pal.accentDeep : Pal.inkSoft)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
