import 'package:flutter/material.dart';

import '../../app/style_tokens.dart';

/// Gema redonda com brilho, na cor do lugar do jogador. No Clássico, [classic]
/// (o ponto de cor que o ecrã já tinha) ou nada.
class ManaOrb extends StatelessWidget {
  const ManaOrb({super.key, required this.color, this.size = 18, this.classic});

  final Color color;
  final double size;
  final Widget? classic;

  @override
  Widget build(BuildContext context) {
    if (!context.edhStyle.isEnchanted) return classic ?? const SizedBox.shrink();
    final hsl = HSLColor.fromColor(color);
    final light = hsl.withLightness((hsl.lightness + .28).clamp(0.0, 1.0)).toColor();
    final dark = hsl.withLightness((hsl.lightness - .25).clamp(0.0, 1.0)).toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient:
            RadialGradient(center: const Alignment(-.3, -.4), colors: [light, color, dark], stops: const [0, .55, 1]),
        border: Border.all(color: Colors.black.withOpacity(.5)),
        boxShadow: [BoxShadow(color: color.withOpacity(.6), blurRadius: size * .35)],
      ),
    );
  }
}
