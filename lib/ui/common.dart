import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';

/// Plutajuća ploča nad nacrtom ili 3D prikazom.
class FloatPanel extends StatelessWidget {
  const FloatPanel({super.key, required this.child, this.padding = const EdgeInsets.all(4), this.radius = 12});
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(242),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Pal.line),
          boxShadow: const [BoxShadow(color: Color(0x1A1C2226), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: Padding(padding: padding, child: child),
      );
}

/// Ikona-gumb s opisom; aktivno stanje je ispunjeno bojom naglaska.
class IconBtn extends StatelessWidget {
  const IconBtn({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
    this.size = 38,
    this.label,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = active ? Colors.white : (enabled ? Pal.inkSoft : Pal.muted.withAlpha(110));
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? Pal.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: SizedBox(
            height: size,
            width: label == null ? size : null,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 10),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 20, color: fg),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Text(label!, style: AppText.ui(size: 12.5, weight: FontWeight.w600, color: fg)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Naslov odjeljka u bočnom panelu.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Row(children: [
          Expanded(child: Text(text, style: AppText.ui(size: 12, weight: FontWeight.w600, color: Pal.muted))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Brojčano polje: primjenjuje vrijednost na Enter ili gubitak fokusa.
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
  late final TextEditingController ctrl = TextEditingController(text: _fmt(widget.value));
  final focus = FocusNode();

  String _fmt(double v) => v.toStringAsFixed(widget.decimals).replaceAll('.', ',');

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
    if (!focus.hasFocus) ctrl.text = _fmt(widget.value);
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
      ctrl.text = _fmt(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        focusNode: focus,
        style: AppText.narrow(size: 14, weight: FontWeight.w600),
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
        decoration: InputDecoration(labelText: widget.label, suffixText: widget.suffix),
        onSubmitted: (_) => _submit(),
      );
}

/// Odabir boje iz palete.
class Swatches extends StatelessWidget {
  const Swatches({super.key, required this.colors, required this.value, required this.onPick, this.names});
  final List<int> colors;
  final List<String>? names;
  final int value;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < colors.length; i++)
          Tooltip(
            message: names?[i] ?? '',
            child: InkWell(
              onTap: () => onPick(colors[i]),
              customBorder: const CircleBorder(),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Color(colors[i]),
                  shape: BoxShape.circle,
                  border: Border.all(color: colors[i] == value ? Pal.accent : Pal.line, width: colors[i] == value ? 2.5 : 1),
                ),
                child: colors[i] == value
                    ? Icon(Icons.check, size: 14, color: Color(colors[i]).computeLuminance() > 0.5 ? Pal.ink : Colors.white)
                    : null,
              ),
            ),
          ),
      ]);
}

/// Mali prekidač s oznakom.
class ToggleRow extends StatelessWidget {
  const ToggleRow({super.key, required this.label, required this.value, required this.onChanged, this.hint});
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: AppText.ui(size: 13, weight: FontWeight.w500)),
                if (hint != null) Text(hint!, style: AppText.ui(size: 11.5, color: Pal.muted)),
              ]),
            ),
            Switch(value: value, onChanged: onChanged, activeTrackColor: Pal.accent),
          ]),
        ),
      );
}

/// Redak "naziv ... vrijednost" za sažetke.
class StatRow extends StatelessWidget {
  const StatRow(this.label, this.value, {super.key, this.strong = false, this.muted = false});
  final String label;
  final String value;
  final bool strong;
  final bool muted;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(
            child: Text(label,
                style: AppText.ui(size: 13, weight: strong ? FontWeight.w600 : FontWeight.w400, color: muted ? Pal.muted : Pal.ink)),
          ),
          Text(value,
              style: AppText.narrow(size: strong ? 15 : 13.5, weight: strong ? FontWeight.w700 : FontWeight.w500, color: muted ? Pal.muted : Pal.ink)),
        ]),
      );
}

/// Vodoravna traka koja se može listati kotačićem miša (i povlačenjem mišem ako je [drag]).
/// Flutter na webu inače vodoravne liste ne lista kotačićem ni mišem.
class HStrip extends StatefulWidget {
  const HStrip({super.key, required this.builder, this.drag = true});
  final Widget Function(ScrollController controller) builder;
  final bool drag;

  @override
  State<HStrip> createState() => _HStripState();
}

class _HStripState extends State<HStrip> {
  final _ctl = ScrollController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.builder(_ctl);
    if (widget.drag) {
      child = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        }),
        child: child,
      );
    }
    return Listener(
      onPointerSignal: (e) {
        if (e is! PointerScrollEvent || !_ctl.hasClients) return;
        final pos = _ctl.position;
        if (pos.maxScrollExtent <= 0) return;
        final d = e.scrollDelta.dy.abs() > e.scrollDelta.dx.abs() ? e.scrollDelta.dy : e.scrollDelta.dx;
        GestureBinding.instance.pointerSignalResolver.register(e, (_) {
          _ctl.jumpTo((_ctl.offset + d).clamp(0.0, pos.maxScrollExtent));
        });
      },
      child: Scrollbar(controller: _ctl, thumbVisibility: false, child: child),
    );
  }
}
