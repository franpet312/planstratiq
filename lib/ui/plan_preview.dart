import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../editor/plan_export.dart';
import '../editor/plan_painter.dart';
import '../models/plan.dart';

/// Statični prikaz tlocrta (sličice projekata, predlošci, naslovna).
class PlanPreview extends StatelessWidget {
  const PlanPreview({super.key, required this.plan, this.detailed = false, this.reveal = 1, this.padding = 0.12});
  final Plan plan;

  /// Detaljan prikaz s kotama i natpisima (naslovna slika).
  final bool detailed;

  /// 0..1 – koliki dio crteža je otkriven (za animaciju crtanja).
  final double reveal;
  final double padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final size = box.biggest;
        final b = planBounds(plan);
        if (b == null || size.isEmpty) return const SizedBox();
        final (minX, minY, maxX, maxY) = b;
        final pw = size.width * (1 - 2 * padding), ph = size.height * (1 - 2 * padding);
        final scale = math.min(pw / math.max(maxX - minX, 1), ph / math.max(maxY - minY, 1));
        final pan = Offset(size.width / 2, size.height / 2) - Offset((minX + maxX) / 2, (minY + maxY) / 2) * scale;
        return ClipRect(
          clipper: _RevealClipper(reveal),
          child: CustomPaint(
            size: size,
            painter: PlanPainter(PlanPaintState(plan: plan, scale: scale, pan: pan, preview: !detailed, printMode: detailed)),
          ),
        );
      });
}

class _RevealClipper extends CustomClipper<Rect> {
  _RevealClipper(this.t);
  final double t;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * t, size.height);
  @override
  bool shouldReclip(covariant _RevealClipper old) => old.t != t;
}
