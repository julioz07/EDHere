import 'package:flutter/material.dart';

/// Separador ativo no Encantado: linha dourada com brilho e um losango.
class GoldTabIndicator extends Decoration {
  const GoldTabIndicator({required this.color, required this.gem});

  final Color color;
  final Color gem;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _GoldTabPainter(color, gem);

  @override
  bool operator ==(Object other) => other is GoldTabIndicator && other.color == color && other.gem == gem;

  @override
  int get hashCode => Object.hash(color, gem);
}

class _GoldTabPainter extends BoxPainter {
  _GoldTabPainter(this.color, this.gem);

  final Color color;
  final Color gem;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size!;
    final w = size.width * .56;
    final left = offset.dx + (size.width - w) / 2;
    final y = offset.dy + size.height - 2;
    final bar = Rect.fromLTWH(left, y, w, 2);
    canvas.drawRect(
        bar,
        Paint()
          ..color = color.withOpacity(.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawRect(bar, Paint()..color = color);
    final cx = offset.dx + size.width / 2;
    final d = Path()
      ..moveTo(cx, y - 3)
      ..lineTo(cx + 4, y + 1)
      ..lineTo(cx, y + 5)
      ..lineTo(cx - 4, y + 1)
      ..close();
    canvas.drawPath(d, Paint()..color = gem);
  }
}
