import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor/plan_editor.dart';
import '../state/plan_controller.dart';
import '../viewer/viewer_3d.dart';
import 'catalog_panel.dart';
import 'properties_panel.dart';
import 'web_files.dart';

enum Layout { plan, split, view3d }

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});

  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  final c = PlanController();
  final editorKey = GlobalKey<PlanEditorState>();
  Layout layout = Layout.split;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    c.init().then((_) => setState(() => ready = true));
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _importPlanImage() async {
    final f = await pickFile('image/*');
    if (f == null) return;
    try {
      await c.loadImageBytes(f.bytes, f.type);
      if (layout == Layout.view3d) setState(() => layout = Layout.split);
      c.setTool(Tool.calibrate);
      WidgetsBinding.instance.addPostFrameCallback((_) => editorKey.currentState?.fit());
      _snack('Nacrt učitan. Klikni dvije točke poznate udaljenosti (npr. kotu zida) za mjerilo, '
          'zatim precrtaj zidove alatom "Zid" ili "Soba".');
    } catch (e) {
      _snack('Slika se ne može učitati: $e');
    }
  }

  Future<void> _open() async {
    final f = await pickFile('.json,application/json');
    if (f == null) return;
    try {
      await c.importJson(utf8.decode(f.bytes));
      editorKey.currentState?.fit();
    } catch (e) {
      _snack('Neispravna datoteka projekta.');
    }
  }

  void _save() {
    final safe = c.plan.name.replaceAll(RegExp(r'[^\w\-čćžšđČĆŽŠĐ ]'), '').trim();
    downloadText(c.exportJson(), '${safe.isEmpty ? 'projekt' : safe}.planstratiq.json');
  }

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

  Future<void> _confirmNew() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novi projekt?'),
        content: const Text('Trenutni projekt bit će zamijenjen. Spremi ga prije ako ga želiš zadržati.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Odustani')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Novi projekt')),
        ],
      ),
    );
    if (ok == true) {
      c.newPlan();
      c.setTool(Tool.room);
      if (layout == Layout.view3d) setState(() => layout = Layout.split);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): c.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): c.undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): c.redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): c.redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): c.redo,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Scaffold(
            appBar: _appBar(context),
            body: Column(children: [
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _ToolRail(c: c),
                  const VerticalDivider(width: 1),
                  Expanded(child: _mainArea()),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 310,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (c.selection.kind != SelKind.none || c.plan.image != null || c.plan.isEmpty) ...[
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 460),
                          child: SingleChildScrollView(child: PropertiesPanel(c: c)),
                        ),
                        const Divider(height: 1),
                      ],
                      Expanded(child: CatalogPanel(c: c)),
                    ]),
                  ),
                ]),
              ),
              _StatusBar(c: c),
            ]),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      titleSpacing: 12,
      title: Row(children: [
        Icon(Icons.architecture, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        const Text('Planstratiq', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 16),
        TextButton.icon(
          onPressed: _rename,
          icon: const Icon(Icons.edit, size: 16),
          label: Text(c.plan.name),
        ),
      ]),
      actions: [
        IconButton(tooltip: 'Poništi (Ctrl+Z)', onPressed: c.canUndo ? c.undo : null, icon: const Icon(Icons.undo)),
        IconButton(tooltip: 'Ponovi (Ctrl+Y)', onPressed: c.canRedo ? c.redo : null, icon: const Icon(Icons.redo)),
        const SizedBox(width: 8),
        SegmentedButton<Layout>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: Layout.plan, icon: Icon(Icons.grid_on), label: Text('2D')),
            ButtonSegment(value: Layout.split, icon: Icon(Icons.vertical_split), label: Text('2D + 3D')),
            ButtonSegment(value: Layout.view3d, icon: Icon(Icons.view_in_ar), label: Text('3D')),
          ],
          selected: {layout},
          onSelectionChanged: (s) => setState(() => layout = s.first),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: _importPlanImage,
          icon: const Icon(Icons.upload_file),
          label: const Text('Učitaj nacrt'),
        ),
        PopupMenuButton<String>(
          tooltip: 'Datoteka',
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            switch (v) {
              case 'new':
                _confirmNew();
              case 'open':
                _open();
              case 'save':
                _save();
              case 'demo':
                c.loadDemo();
                editorKey.currentState?.fit();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'new', child: ListTile(leading: Icon(Icons.add), title: Text('Novi projekt (od nule)'))),
            PopupMenuItem(value: 'open', child: ListTile(leading: Icon(Icons.folder_open), title: Text('Otvori projekt…'))),
            PopupMenuItem(value: 'save', child: ListTile(leading: Icon(Icons.save_alt), title: Text('Spremi projekt (Ctrl+S)'))),
            PopupMenuItem(value: 'demo', child: ListTile(leading: Icon(Icons.house), title: Text('Učitaj demo kuću'))),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _mainArea() {
    final editor = PlanEditor(key: editorKey, c: c);
    final viewer = Viewer3D(c: c);
    return switch (layout) {
      Layout.plan => editor,
      Layout.view3d => viewer,
      Layout.split => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: editor),
          const VerticalDivider(width: 1),
          Expanded(child: viewer),
        ]),
    };
  }
}

class _ToolRail extends StatelessWidget {
  const _ToolRail({required this.c});
  final PlanController c;

  @override
  Widget build(BuildContext context) {
    Widget tool(Tool t, IconData icon, String tip) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: IconButton(
            tooltip: tip,
            isSelected: c.tool == t,
            style: IconButton.styleFrom(
              backgroundColor: c.tool == t ? Theme.of(context).colorScheme.primaryContainer : null,
            ),
            onPressed: () => c.setTool(t),
            icon: Icon(icon),
          ),
        );
    return SizedBox(
      width: 56,
      child: Column(children: [
        const SizedBox(height: 8),
        tool(Tool.select, Icons.near_me_outlined, 'Odabir i pomicanje'),
        tool(Tool.wall, Icons.timeline, 'Zid – crtaj zidove klik po klik'),
        tool(Tool.room, Icons.crop_square, 'Soba – povuci pravokutnik'),
        tool(Tool.door, Icons.door_front_door_outlined, 'Vrata – klikni na zid'),
        tool(Tool.window, Icons.window_outlined, 'Prozor – klikni na zid'),
        tool(Tool.calibrate, Icons.straighten, 'Mjerilo nacrta'),
        const Divider(indent: 10, endIndent: 10),
        IconButton(
          tooltip: 'Obriši odabrano (Del)',
          onPressed: c.selection.kind == SelKind.none ? null : c.deleteSelection,
          icon: const Icon(Icons.delete_outline),
        ),
      ]),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.c});
  final PlanController c;

  @override
  Widget build(BuildContext context) {
    final text = switch (c.tool) {
      Tool.select =>
        'Klikni element za odabir · povuci zid da ga pomakneš · povuci prazno za pomak pogleda · kotačić = zoom · Del briše · R rotira namještaj',
      Tool.wall =>
        'Klikni početak zida pa klikaj dalje · klik na istu točku, Esc ili desni klik završava · hvata se na 45°/90° i postojeće točke',
      Tool.room => 'Povuci pravokutnik za novu prostoriju – zidovi se kreiraju automatski i spajaju sa susjednima',
      Tool.door => 'Klikni na zid gdje želiš vrata (kasnije ih možeš povući duž zida)',
      Tool.window => 'Klikni na zid gdje želiš prozor',
      Tool.calibrate => 'Klikni dvije točke na nacrtu čiju stvarnu udaljenost znaš (npr. kotiranu duljinu zida)',
      Tool.place => 'Klikni na tlocrt da postaviš: ${c.placing?.name ?? ''} · Esc odustaje',
    };
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Text(text, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
    );
  }
}
