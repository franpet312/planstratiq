import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../editor/plan_editor.dart';
import '../editor/plan_export.dart';
import '../models/plan.dart';
import '../models/templates.dart';
import '../state/plan_controller.dart';
import '../state/project_store.dart';
import '../viewer/viewer_3d.dart';
import 'catalog_panel.dart';
import 'common.dart';
import 'home_page.dart' show LogoMark;
import 'plan_preview.dart';
import 'properties_panel.dart';
import 'summary_panel.dart';
import 'web_files.dart';

enum ViewLayout { plan, split, view3d }

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.projectId, this.initialImage});
  final String projectId;
  final PickedFile? initialImage;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final PlanController c;
  final editorKey = GlobalKey<PlanEditorState>();
  final zoom = ValueNotifier<double>(50);
  ViewLayout? _layout;
  int tab = 0; // 0 katalog, 1 svojstva, 2 pregled
  Selection _lastSel = Selection.none;

  @override
  void initState() {
    super.initState();
    final store = ProjectStore.instance;
    c = PlanController(
      projectId: widget.projectId,
      initial: store.load(widget.projectId) ?? Plan(name: 'Moj dom'),
      onSave: (p) => store.save(widget.projectId, p),
    );
    c.addListener(_onChange);
    final img = widget.initialImage;
    if (img != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyImage(img));
    }
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    c.dispose();
    zoom.dispose();
    super.dispose();
  }

  void _onChange() {
    if (c.selection != _lastSel) {
      _lastSel = c.selection;
      if (c.selection.kind != SelKind.none && tab == 0 && c.tool != Tool.place) setState(() => tab = 1);
    }
  }

  bool get _narrow => MediaQuery.of(context).size.width < 900;

  ViewLayout get layout => _layout ?? (_narrow ? ViewLayout.plan : ViewLayout.split);

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  // ---------------------------------------------------------------- akcije
  Future<void> _applyImage(PickedFile f) async {
    try {
      await c.loadImageBytes(f.bytes, f.type);
      if (layout == ViewLayout.view3d) setState(() => _layout = ViewLayout.split);
      c.setTool(Tool.calibrate);
      WidgetsBinding.instance.addPostFrameCallback((_) => editorKey.currentState?.fit());
      _snack('Nacrt je učitan. Klikni dvije točke čiju stvarnu udaljenost znaš, npr. početak i kraj kotiranog zida.');
    } catch (e) {
      _snack('Slika se ne može učitati. Probaj s JPG ili PNG datotekom.');
    }
  }

  Future<void> _uploadImage() async {
    final f = await pickFile('image/*');
    if (f != null) await _applyImage(f);
  }

  Future<void> _exportPlanPng() async {
    final png = await renderPlanPng(c);
    if (png == null) {
      _snack('Tlocrt je prazan, nema što spremiti.');
      return;
    }
    downloadBytes(png, '${c.plan.name} – tlocrt.png', mime: 'image/png');
  }

  void _exportCsv() => downloadText(buildCsv(c), '${c.plan.name} – troškovnik.csv', mime: 'text/csv;charset=utf-8');

  void _exportJson() => downloadText(c.exportJson(), '${c.plan.name}.planstratiq.json');

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: c.plan.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Naziv projekta'),
        content: TextField(controller: ctrl, autofocus: true, onSubmitted: (s) => Navigator.pop(ctx, s)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Odustani')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Spremi')),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty) c.rename(v.trim());
  }

  Future<void> _chooseTemplate() async {
    final t = await showDialog<PlanTemplate>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kreni od predloška'),
        content: SizedBox(
          width: 560,
          child: Row(children: [
            for (final t in templates)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Pal.line)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx, t),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        AspectRatio(aspectRatio: 1.3, child: PlanPreview(plan: buildTemplatePlan(t))),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.name, style: AppText.ui(size: 14, weight: FontWeight.w600)),
                            Text(t.description, style: AppText.ui(size: 12, color: Pal.muted)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Odustani'))],
      ),
    );
    if (t != null) {
      c.replaceWith(t.build);
      WidgetsBinding.instance.addPostFrameCallback((_) => editorKey.currentState?.fit());
      _snack('Predložak je postavljen. Možeš ga poništiti s Ctrl+Z.');
    }
  }

  void _emptyAction(String a) {
    switch (a) {
      case 'room':
        c.setTool(Tool.room);
      case 'wall':
        c.setTool(Tool.wall);
      case 'image':
        _uploadImage();
      case 'template':
        _chooseTemplate();
    }
  }

  // ---------------------------------------------------------------- izgled
  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): c.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): c.undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): c.redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): c.redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): c.redo,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _exportJson,
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Scaffold(
            backgroundColor: Pal.paper,
            body: Column(children: [
              _topBar(),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: _main()),
                  if (!_narrow) ...[
                    const VerticalDivider(width: 1, color: Pal.line),
                    SizedBox(width: 340, child: _inspector()),
                  ],
                ]),
              ),
            ]),
            bottomNavigationBar: _narrow ? _mobileBar() : null,
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    final narrow = _narrow;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Pal.line))),
      child: Row(children: [
        IconBtn(icon: Icons.arrow_back, tooltip: 'Moji projekti', onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 4),
        if (!narrow) ...[
          SizedBox(width: 20, height: 20, child: CustomPaint(painter: LogoMark())),
          const SizedBox(width: 12),
        ],
        Flexible(
          child: InkWell(
            onTap: _rename,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.plan.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.ui(size: 14.5, weight: FontWeight.w700)),
                ValueListenableBuilder(
                  valueListenable: c.saveState,
                  builder: (_, s, __) => Text(s, style: AppText.ui(size: 11.5, color: Pal.muted)),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (!narrow) const Spacer(),
        _layoutSwitch(narrow),
        if (!narrow) const Spacer(),
        IconBtn(icon: Icons.undo, tooltip: 'Poništi (Ctrl+Z)', onTap: c.canUndo ? c.undo : null),
        IconBtn(icon: Icons.redo, tooltip: 'Ponovi (Ctrl+Y)', onTap: c.canRedo ? c.redo : null),
        if (!narrow) ...[
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: _uploadImage,
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text('Nacrt'),
          ),
        ],
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: 'Izvoz i projekt',
          icon: const Icon(Icons.ios_share, color: Pal.inkSoft, size: 20),
          onSelected: (v) {
            switch (v) {
              case 'png':
                _exportPlanPng();
              case 'csv':
                _exportCsv();
              case 'json':
                _exportJson();
              case 'image':
                _uploadImage();
              case 'template':
                _chooseTemplate();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'png', child: ListTile(dense: true, leading: Icon(Icons.image_outlined), title: Text('Tlocrt kao slika (PNG)'))),
            PopupMenuItem(value: 'csv', child: ListTile(dense: true, leading: Icon(Icons.table_view_outlined), title: Text('Troškovnik (CSV)'))),
            PopupMenuItem(value: 'json', child: ListTile(dense: true, leading: Icon(Icons.save_alt), title: Text('Projekt kao datoteka'))),
            PopupMenuDivider(),
            PopupMenuItem(value: 'image', child: ListTile(dense: true, leading: Icon(Icons.upload_file_outlined), title: Text('Učitaj sliku nacrta'))),
            PopupMenuItem(value: 'template', child: ListTile(dense: true, leading: Icon(Icons.dashboard_customize_outlined), title: Text('Zamijeni predloškom'))),
          ],
        ),
        const SizedBox(width: 4),
      ]),
    );
  }

  Widget _layoutSwitch(bool narrow) {
    Widget seg(ViewLayout l, IconData icon, String label) => IconBtn(
          icon: icon,
          tooltip: label,
          label: narrow ? null : label,
          active: layout == l,
          onTap: () => setState(() => _layout = l),
          size: 34,
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Pal.paper, borderRadius: BorderRadius.circular(11), border: Border.all(color: Pal.lineSoft)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(ViewLayout.plan, Icons.grid_on, 'Tlocrt'),
        if (!narrow) seg(ViewLayout.split, Icons.vertical_split_outlined, 'Oboje'),
        seg(ViewLayout.view3d, Icons.view_in_ar_outlined, '3D'),
      ]),
    );
  }

  Widget _main() {
    final editor = _editorArea();
    final viewer = Viewer3D(c: c, compact: layout == ViewLayout.split);
    return switch (layout) {
      ViewLayout.plan => editor,
      ViewLayout.view3d => viewer,
      ViewLayout.split => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: editor),
          const VerticalDivider(width: 1, color: Pal.line),
          Expanded(child: viewer),
        ]),
    };
  }

  Widget _editorArea() => Stack(children: [
        Positioned.fill(child: PlanEditor(key: editorKey, c: c, onEmptyAction: _emptyAction, zoom: zoom)),
        Positioned(left: 12, top: 12, child: _ToolDock(c: c, onCancel: () => editorKey.currentState?.cancelTool())),
        Positioned(left: 12, bottom: 12, child: _ZoomControls(editorKey: editorKey, zoom: zoom)),
        Positioned(bottom: 64, left: 72, right: 12, child: Center(child: _ToolHint(c: c))),
        if (c.plan.isEmpty && c.plan.image == null && c.tool == Tool.select)
          Positioned.fill(child: Center(child: _EmptyState(onAction: _emptyAction))),
      ]);

  Widget _inspector() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Pal.lineSoft))),
          child: Row(children: [
            _tab(0, 'Katalog'),
            _tab(1, c.selection.kind == SelKind.none ? 'Svojstva' : 'Odabrano'),
            _tab(2, 'Pregled i cijene'),
          ]),
        ),
        Expanded(
          child: ColoredBox(
            color: Colors.white,
            child: IndexedStack(index: tab, children: [
              CatalogPanel(c: c),
              PropertiesPanel(c: c, onCalibrate: () => _snack('Klikni dvije točke na nacrtu čiju udaljenost znaš.')),
              SummaryPanel(c: c, onExportCsv: _exportCsv, onExportPlan: _exportPlanPng),
            ]),
          ),
        ),
      ]);

  Widget _tab(int i, String label) => Expanded(
        child: InkWell(
          onTap: () => setState(() => tab = i),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tab == i ? Pal.accent : Colors.transparent, width: 2))),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.ui(size: 12.5, weight: FontWeight.w600, color: tab == i ? Pal.ink : Pal.muted)),
          ),
        ),
      );

  Widget _mobileBar() => Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Pal.line))),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SafeArea(
          top: false,
          child: Row(children: [
            Expanded(child: _mobileBtn(Icons.chair_outlined, 'Katalog', 0)),
            Expanded(child: _mobileBtn(Icons.tune, c.selection.kind == SelKind.none ? 'Svojstva' : 'Odabrano', 1)),
            Expanded(child: _mobileBtn(Icons.receipt_long_outlined, 'Pregled', 2)),
          ]),
        ),
      );

  Widget _mobileBtn(IconData icon, String label, int i) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openSheet(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: Pal.inkSoft),
            const SizedBox(height: 2),
            Text(label, style: AppText.ui(size: 11.5, weight: FontWeight.w600, color: Pal.inkSoft)),
          ]),
        ),
      );

  void _openSheet(int i) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.3,
        builder: (ctx, scroll) => ListenableBuilder(
          listenable: c,
          builder: (ctx, _) => Column(children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Pal.line, borderRadius: BorderRadius.circular(2))),
            Expanded(
              child: switch (i) {
                0 => CatalogPanel(c: c, onPicked: () => Navigator.pop(ctx)),
                1 => PropertiesPanel(c: c),
                _ => SummaryPanel(c: c, onExportCsv: _exportCsv, onExportPlan: _exportPlanPng),
              },
            ),
          ]),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- alati

class _ToolDock extends StatelessWidget {
  const _ToolDock({required this.c, required this.onCancel});
  final PlanController c;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    Widget t(Tool tool, IconData icon, String tip) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: IconBtn(
            icon: icon,
            tooltip: tip,
            active: c.tool == tool,
            onTap: () {
              onCancel();
              c.setTool(tool);
            },
          ),
        );
    return FloatPanel(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        t(Tool.select, Icons.near_me_outlined, 'Odabir i pomicanje  V'),
        const Padding(padding: EdgeInsets.symmetric(vertical: 3), child: SizedBox(width: 24, child: Divider())),
        t(Tool.room, Icons.crop_square, 'Prostorija: povuci pravokutnik  R'),
        t(Tool.wall, Icons.polyline_outlined, 'Zidovi: klik po klik, upiši duljinu  W'),
        t(Tool.door, Icons.door_front_door_outlined, 'Vrata: klikni na zid  D'),
        t(Tool.window, Icons.window_outlined, 'Prozor: klikni na zid  P'),
        t(Tool.balcony, Icons.balcony_outlined, 'Balkonska vrata: klikni na zid'),
        t(Tool.passage, Icons.space_bar, 'Prolaz bez vrata: klikni na zid'),
        const Padding(padding: EdgeInsets.symmetric(vertical: 3), child: SizedBox(width: 24, child: Divider())),
        t(Tool.measure, Icons.straighten, 'Mjerenje udaljenosti  M'),
        if (c.plan.image != null) t(Tool.calibrate, Icons.photo_size_select_small, 'Mjerilo nacrta'),
      ]),
    );
  }
}

class _ToolHint extends StatelessWidget {
  const _ToolHint({required this.c});
  final PlanController c;

  @override
  Widget build(BuildContext context) {
    final text = switch (c.tool) {
      Tool.select => null,
      Tool.wall => 'Klikni početak zida, pa svaki sljedeći kut. Upiši duljinu i pritisni Enter za točnu mjeru. Esc završava.',
      Tool.room => 'Povuci pravokutnik. Zidovi se spajaju sa susjednim prostorijama, a površina se računa sama.',
      Tool.door => 'Klikni na zid gdje želiš vrata. Poslije ih možeš povući duž zida.',
      Tool.window => 'Klikni na zid gdje želiš prozor.',
      Tool.balcony => 'Klikni na vanjski zid gdje želiš balkonska vrata.',
      Tool.passage => 'Klikni na zid gdje želiš prolaz bez vrata.',
      Tool.measure => 'Klikni dvije točke da izmjeriš udaljenost. Treći klik počinje novo mjerenje.',
      Tool.calibrate => 'Klikni dvije točke na nacrtu čiju stvarnu udaljenost znaš, npr. početak i kraj kotiranog zida.',
      Tool.place => 'Klikni gdje želiš postaviti: ${c.placing?.name ?? ''}. Uz zid se sam okrene. Shift+klik postavlja više komada.',
    };
    if (text == null) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
        decoration: BoxDecoration(color: Pal.ink.withAlpha(235), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(text, style: AppText.ui(size: 12.5, color: Colors.white, height: 1.35))),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => c.setTool(Tool.select),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text('Gotovo', style: AppText.ui(size: 12.5, weight: FontWeight.w700, color: const Color(0xFF8FD3CC))),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({required this.editorKey, required this.zoom});
  final GlobalKey<PlanEditorState> editorKey;
  final ValueNotifier<double> zoom;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(valueListenable: zoom, builder: (context, scale, _) => _build(scale));

  Widget _build(double scale) {
    final ed = editorKey.currentState;
    // mjerilo: odaberi lijepu duljinu oko 80 px
    const nice = [0.5, 1.0, 2.0, 5.0, 10.0, 20.0];
    final meters = nice.firstWhere((m) => m * scale >= 60, orElse: () => 20);
    return FloatPanel(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconBtn(icon: Icons.remove, tooltip: 'Udalji  −', size: 32, onTap: () => ed?.zoomBy(1 / 1.25)),
        IconBtn(icon: Icons.add, tooltip: 'Približi  +', size: 32, onTap: () => ed?.zoomBy(1.25)),
        IconBtn(icon: Icons.fit_screen_outlined, tooltip: 'Cijeli tlocrt  0', size: 32, onTap: () => ed?.fit()),
        const SizedBox(width: 8),
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: meters * scale,
            height: 6,
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Pal.ink), right: BorderSide(color: Pal.ink), bottom: BorderSide(color: Pal.ink)),
            ),
          ),
          Text(meters < 1 ? '50 cm' : '${meters.round()} m', style: AppText.narrow(size: 10.5, color: Pal.inkSoft)),
        ]),
        const SizedBox(width: 8),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAction});
  final void Function(String) onAction;

  @override
  Widget build(BuildContext context) {
    Widget action(IconData icon, String title, String sub, String id) => Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Pal.line)),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onAction(id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(icon, color: Pal.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: AppText.ui(size: 13.5, weight: FontWeight.w600)),
                    Text(sub, style: AppText.ui(size: 12, color: Pal.muted)),
                  ]),
                ),
              ]),
            ),
          ),
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: FloatPanel(
        radius: 14,
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Papir je prazan', style: AppText.ui(size: 18, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Odaberi kako želiš početi. Sve mjere možeš kasnije mijenjati.', style: AppText.ui(size: 13, color: Pal.muted)),
          const SizedBox(height: 14),
          action(Icons.crop_square, 'Nacrtaj prostoriju', 'Povuci pravokutnik, pa dodaj sljedeću uz nju', 'room'),
          const SizedBox(height: 8),
          action(Icons.polyline_outlined, 'Crtaj zid po zid', 'Za prostorije nepravilnog oblika', 'wall'),
          const SizedBox(height: 8),
          action(Icons.upload_file_outlined, 'Precrtaj nacrt', 'Učitaj sliku ili sken tlocrta kao podlogu', 'image'),
          const SizedBox(height: 8),
          action(Icons.dashboard_customize_outlined, 'Kreni od predloška', 'Kuća ili stan s rasporedom namještaja', 'template'),
        ]),
      ),
    );
  }
}
