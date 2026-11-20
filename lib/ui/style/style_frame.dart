import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/style_tokens.dart';

/// Moldura do kit (rebordo de carta com gema no topo). No Clássico, [classic]
/// embrulha o filho como o ecrã fazia (um Card, um Container...).
class StyleFrame extends StatelessWidget {
  const StyleFrame({
    super.key,
    required this.child,
    required this.classic,
    this.highlighted = false,
    this.showGem = true,
    this.padding = const EdgeInsets.all(14),
    this.radius = 14,
  });

  final Widget child;
  final Widget Function(Widget child) classic;

  /// O item ativo ou do próprio jogador.
  final bool highlighted;
  final bool showGem;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.edhStyle;
    if (!c.isEnchanted) return classic(child);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final frame = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.surfaceHigh, c.surface]),
        border: Border.all(color: (highlighted ? c.goldLight : c.gold).withOpacity(highlighted ? .9 : .6)),
        // A ordem conta: sombra, anel de ouro exterior, intervalo escuro por cima.
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(dark ? .55 : .12),
              blurRadius: dark ? 26 : 14,
              offset: const Offset(0, 8)),
          BoxShadow(color: c.gold.withOpacity(.2), spreadRadius: 4),
          BoxShadow(color: c.background, spreadRadius: 3),
          if (highlighted) BoxShadow(color: c.goldLight.withOpacity(.18), blurRadius: 18),
        ],
      ),
      child: child,
    );
    if (!showGem) return frame;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        frame,
        Positioned(top: -5, left: 0, right: 0, child: Center(child: GoldGem(color: c.goldPale))),
      ],
    );
  }
}

/// Pequeno losango dourado com brilho (ornamento das molduras).
class GoldGem extends StatelessWidget {
  const GoldGem({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color, context.edhStyle.gold]),
            boxShadow: [BoxShadow(color: color.withOpacity(.7), blurRadius: 8)],
          ),
        ),
      );
}
