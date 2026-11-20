import 'package:flutter/material.dart';

import '../../app/style_tokens.dart';

/// Coroa de lendária, sobre o comandante. Não existe no Clássico.
class LegendCrown extends StatelessWidget {
  const LegendCrown({super.key, this.width = 24});

  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.edhStyle;
    if (!c.isEnchanted) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: CustomPaint(size: Size(width, width / 3), painter: _CrownPainter(c.goldLight)),
    );
  }
}

class _CrownPainter extends CustomPainter {
  _CrownPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Path()
      ..moveTo(0, s.height)
      ..lineTo(s.width * .12, s.height * .2)
      ..lineTo(s.width * .30, s.height * .7)
      ..lineTo(s.width * .50, 0)
      ..lineTo(s.width * .70, s.height * .7)
      ..lineTo(s.width * .88, s.height * .2)
      ..lineTo(s.width, s.height)
      ..close();
    canvas.drawPath(
        p,
        Paint()
          ..color = color.withOpacity(.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CrownPainter old) => old.color != color;
}
