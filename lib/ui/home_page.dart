import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/geometry.dart';
import '../models/plan.dart';
import '../models/templates.dart';
import '../state/project_store.dart';
import 'editor_page.dart';
import 'plan_preview.dart';
import 'web_files.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  final store = ProjectStore.instance;
  late List<ProjectMeta> projects;
  final Map<String, Plan?> _plans = {};
  late final Map<String, Plan> _templatePlans = {for (final t in templates) t.id: buildTemplatePlan(t)};
  late final AnimationController _draw = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (MediaQuery.of(context).disableAnimations) {
        _draw.value = 1;
      } else {
        _draw.forward();
      }
    });
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  void _reload() {
    projects = store.list();
    _plans.clear();
    for (final p in projects) {
      _plans[p.id] = store.load(p.id);
    }
  }

  Future<void> _open(String id, {PickedFile? image}) async {
    await Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => EditorPage(projectId: id, initialImage: image),
      transitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
    if (mounted) setState(_reload);
  }

  void _newEmpty() => _open(store.create(Plan(name: 'Moj dom')));

  void _fromTemplate(PlanTemplate t) => _open(store.create(buildTemplatePlan(t)));

  Future<void> _fromImage() async {
    final f = await pickFile('image/*');
    if (f == null) return;
    final name = f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name;
    _open(store.create(Plan(name: name.isEmpty ? 'Iz nacrta' : name)), image: f);
  }

  Future<void> _import() async {
    final f = await pickFile('.json,application/json');
    if (f == null) return;
    try {
      final plan = Plan.fromJson(jsonDecode(utf8.decode(f.bytes)) as Map<String, dynamic>);
      _open(store.create(plan));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Datoteka nije Planstratiq projekt (.json).')));
      }
    }
  }

  Future<void> _rename(ProjectMeta m) async {
    final ctrl = TextEditingController(text: m.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Preimenuj projekt'),
        content: TextField(controller: ctrl, autofocus: true, onSubmitted: (s) => Navigator.pop(ctx, s)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Odustani')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Preimenuj')),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty) setState(() {
      store.rename(m.id, v.trim());
      _reload();
    });
  }

  Future<void> _delete(ProjectMeta m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Obrisati „${m.name}”?'),
        content: const Text('Projekt će se trajno ukloniti iz ovog preglednika. Ako ga želiš sačuvati, prvo ga izvezi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Odustani')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Pal.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Obriši projekt'),
          ),
        ],
      ),
    );
    if (ok == true) setState(() {
      store.delete(m.id);
      _reload();
    });
  }

  String _ago(int ms) {
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return 'upravo sada';
    if (d.inMinutes < 60) return 'prije ${d.inMinutes} min';
    if (d.inHours < 24) return 'prije ${d.inHours} h';
    if (d.inDays < 30) return 'prije ${d.inDays} ${d.inDays == 1 ? 'dan' : 'dana'}';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${t.day}. ${t.month}. ${t.year}.';
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 980;
    return Scaffold(
      backgroundColor: Pal.paper,
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: _topBar()),
        SliverToBoxAdapter(child: _hero(wide)),
        SliverToBoxAdapter(child: _section('Moji projekti', projects.isEmpty ? null : '${projects.length}')),
        if (projects.isEmpty)
          SliverToBoxAdapter(
            child: _constrained(Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: SizedBox(
                width: double.infinity,
                child: Text('Još nemaš projekata. Kreni od praznog papira, nacrta ili jednog od predložaka ispod.',
                    style: AppText.ui(size: 14, color: Pal.muted)),
              ),
            )),
          )
        else
          _grid([for (final m in projects) _projectCard(m)]),
        SliverToBoxAdapter(child: _section('Kreni od predloška', null)),
        _grid([
          for (final t in templates) _templateCard(t),
          _blankCard(),
        ]),
        SliverToBoxAdapter(child: _footer()),
      ]),
    );
  }

  Widget _constrained(Widget child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 28), child: child),
        ),
      );

  Widget _topBar() => _constrained(Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(children: [
          const _Logo(),
          const Spacer(),
          TextButton.icon(onPressed: _import, icon: const Icon(Icons.file_open_outlined, size: 18), label: const Text('Otvori datoteku projekta')),
        ]),
      ));

  Widget _hero(bool wide) {
    final copy = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('Nacrtaj dom\nprije nego ga sagradiš.',
          style: AppText.ui(size: wide ? 52 : 36, weight: FontWeight.w800, height: 1.04, spacing: -1.2)),
      const SizedBox(height: 18),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: Text(
          'Precrtaj postojeći nacrt ili crtaj od nule, pomiči zidove dok mjere ne sjednu, opremi prostorije namještajem stvarnih '
          'dimenzija i prošeći kroz kuću u 3D-u. Radi u pregledniku, projekti ostaju na tvom računalu.',
          style: AppText.ui(size: 16, color: Pal.inkSoft, height: 1.5),
        ),
      ),
      const SizedBox(height: 26),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
          onPressed: _newEmpty,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Novi projekt'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
        ),
        OutlinedButton.icon(
          onPressed: _fromImage,
          icon: const Icon(Icons.upload_file_outlined, size: 18),
          label: const Text('Učitaj sliku nacrta'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16), backgroundColor: Colors.white),
        ),
      ]),
    ]);
    final drawing = AspectRatio(
      aspectRatio: 1.15,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Pal.line),
          boxShadow: const [BoxShadow(color: Color(0x141C2226), blurRadius: 30, offset: Offset(0, 14))],
        ),
        child: Stack(children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _draw,
              builder: (_, __) => PlanPreview(
                plan: _templatePlans['house']!,
                detailed: true,
                reveal: Curves.easeInOutCubic.transform(_draw.value),
                padding: 0.1,
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 12,
            child: Text('Predložak: obiteljska kuća, 120 m²', style: AppText.narrow(size: 12, color: Pal.muted)),
          ),
        ]),
      ),
    );
    return _constrained(Padding(
      padding: EdgeInsets.only(top: wide ? 36 : 16, bottom: 48),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(flex: 5, child: copy),
              const SizedBox(width: 48),
              Expanded(flex: 6, child: drawing),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [copy, const SizedBox(height: 32), drawing]),
    ));
  }

  Widget _section(String title, String? count) => _constrained(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(title, style: AppText.ui(size: 20, weight: FontWeight.w700, spacing: -0.3)),
          if (count != null) ...[
            const SizedBox(width: 8),
            Text(count, style: AppText.narrow(size: 16, color: Pal.muted)),
          ],
        ]),
      ));

  Widget _grid(List<Widget> children) => SliverToBoxAdapter(
        child: _constrained(Padding(
          padding: const EdgeInsets.only(bottom: 36),
          child: LayoutBuilder(builder: (context, box) {
            final cols = (box.maxWidth / 270).floor().clamp(1, 4);
            final w = (box.maxWidth - (cols - 1) * 16) / cols;
            return Wrap(spacing: 16, runSpacing: 16, children: [for (final c in children) SizedBox(width: w, child: c)]);
          }),
        )),
      );

  Widget _card({required Widget preview, required String title, required String subtitle, required VoidCallback onTap, Widget? menu}) =>
      Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Pal.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
              aspectRatio: 1.45,
              child: Container(
                decoration: const BoxDecoration(color: Color(0xFFF6F8F7), border: Border(bottom: BorderSide(color: Pal.lineSoft))),
                child: preview,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.ui(size: 14.5, weight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.ui(size: 12.5, color: Pal.muted, height: 1.35)),
                  ]),
                ),
                if (menu != null) menu,
              ]),
            ),
          ]),
        ),
      );

  Widget _projectCard(ProjectMeta m) {
    final plan = _plans[m.id];
    return _card(
      preview: plan == null || plan.isEmpty
          ? Center(child: Text('Prazan tlocrt', style: AppText.ui(size: 12.5, color: Pal.muted)))
          : PlanPreview(plan: plan),
      title: m.name,
      subtitle: '${m.area > 0 ? '${fmtM2(m.area)}, ' : ''}${m.rooms} ${m.rooms == 1 ? 'prostorija' : 'prostorija'}. Uređeno ${_ago(m.updated)}.',
      onTap: () => _open(m.id),
      menu: PopupMenuButton<String>(
        tooltip: 'Više',
        icon: const Icon(Icons.more_horiz, color: Pal.muted),
        onSelected: (v) {
          switch (v) {
            case 'open':
              _open(m.id);
            case 'rename':
              _rename(m);
            case 'dup':
              setState(() {
                store.duplicate(m.id);
                _reload();
              });
            case 'export':
              final p = store.load(m.id);
              if (p != null) downloadText(const JsonEncoder.withIndent('  ').convert(p.toJson()), '${m.name}.planstratiq.json');
            case 'delete':
              _delete(m);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'open', child: Text('Otvori')),
          PopupMenuItem(value: 'rename', child: Text('Preimenuj')),
          PopupMenuItem(value: 'dup', child: Text('Napravi kopiju')),
          PopupMenuItem(value: 'export', child: Text('Spremi kao datoteku')),
          PopupMenuDivider(),
          PopupMenuItem(value: 'delete', child: Text('Obriši', style: TextStyle(color: Pal.danger))),
        ],
      ),
    );
  }

  Widget _templateCard(PlanTemplate t) =>
      _card(preview: PlanPreview(plan: _templatePlans[t.id]!), title: t.name, subtitle: t.description, onTap: () => _fromTemplate(t));

  Widget _blankCard() => _card(
        preview: CustomPaint(painter: _BlankPaper()),
        title: 'Prazan papir',
        subtitle: 'Nacrtaj prostorije od nule, zid po zid ili pravokutnicima',
        onTap: _newEmpty,
      );

  Widget _footer() => _constrained(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Projekti se spremaju automatski u ovaj preglednik. Za prijenos na drugo računalo spremi projekt kao datoteku i otvori je tamo.',
            style: AppText.ui(size: 12.5, color: Pal.muted, height: 1.4),
          ),
        ]),
      ));
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 26, height: 26, child: CustomPaint(painter: LogoMark())),
        const SizedBox(width: 10),
        Text('Planstratiq', style: AppText.ui(size: 18, weight: FontWeight.w800, spacing: -0.4)),
      ]);
}

/// Znak: tlocrt s jednim otvorom vrata.
class LogoMark extends CustomPainter {
  LogoMark({this.color = Pal.ink});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.13
      ..strokeCap = StrokeCap.square;
    final path = Path()
      ..moveTo(s * 0.42, s * 0.08)
      ..lineTo(s * 0.92, s * 0.08)
      ..lineTo(s * 0.92, s * 0.92)
      ..lineTo(s * 0.08, s * 0.92)
      ..lineTo(s * 0.08, s * 0.45);
    canvas.drawPath(path, p);
    canvas.drawLine(Offset(s * 0.5, s * 0.08), Offset(s * 0.5, s * 0.55), p..strokeWidth = s * 0.08);
    canvas.drawArc(Rect.fromCircle(center: Offset(s * 0.08, s * 0.08), radius: s * 0.34), 0, 1.5708, false,
        Paint()
          ..color = Pal.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.07);
  }

  @override
  bool shouldRepaint(covariant LogoMark old) => old.color != color;
}

class _BlankPaper extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFFE3E8E5);
    for (var x = 0.0; x < size.width; x += 16) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y < size.height; y += 16) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final c = size.center(Offset.zero);
    final plus = Paint()
      ..color = Pal.accent
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c - const Offset(14, 0), c + const Offset(14, 0), plus);
    canvas.drawLine(c - const Offset(0, 14), c + const Offset(0, 14), plus);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
