import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../state/plan_controller.dart';

/// Most prema Three.js engineu iz web/planstratiq3d.js.
@JS('Planstratiq3D')
external _Engine get _engine;

extension type _Engine._(JSObject _) implements JSObject {
  external void mount(web.HTMLElement el);
  external void setPlan(String json);
  external void setMode(String mode);
  external void frame();
}

enum ViewMode3D { orbit, walk }

class Viewer3D extends StatefulWidget {
  const Viewer3D({super.key, required this.c});
  final PlanController c;

  @override
  State<Viewer3D> createState() => _Viewer3DState();
}

class _Viewer3DState extends State<Viewer3D> {
  ViewMode3D mode = ViewMode3D.orbit;
  int _sentRevision = -1;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.c.addListener(_onPlanChanged);
  }

  @override
  void dispose() {
    widget.c.removeListener(_onPlanChanged);
    _debounce?.cancel();
    super.dispose();
  }

  void _onPlanChanged() {
    if (widget.c.revision == _sentRevision) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 40), _push);
  }

  void _push() {
    _sentRevision = widget.c.revision;
    _engine.setPlan(jsonEncode(widget.c.plan.toSceneJson()));
  }

  void _setMode(ViewMode3D m) {
    setState(() => mode = m);
    _engine.setMode(m.name);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
        child: HtmlElementView.fromTagName(
          tagName: 'div',
          onElementCreated: (Object element) {
            final el = element as web.HTMLElement;
            el.style.width = '100%';
            el.style.height = '100%';
            _engine.mount(el);
            _engine.setMode(mode.name);
            _push();
          },
        ),
      ),
      Positioned(
        top: 12,
        left: 12,
        child: Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surface.withAlpha(235),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<ViewMode3D>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: ViewMode3D.orbit,
                      icon: Icon(Icons.threed_rotation),
                      label: Text('Pregled')),
                  ButtonSegment(
                      value: ViewMode3D.walk,
                      icon: Icon(Icons.directions_walk),
                      label: Text('Šetnja')),
                ],
                selected: {mode},
                onSelectionChanged: (s) => _setMode(s.first),
              ),
              if (mode == ViewMode3D.orbit)
                IconButton(
                  tooltip: 'Centriraj pogled',
                  icon: const Icon(Icons.center_focus_strong),
                  onPressed: () => _engine.frame(),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
