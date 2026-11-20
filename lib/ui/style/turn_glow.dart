import 'package:flutter/material.dart';

import '../../app/style_tokens.dart';

/// Marca quem tem a vez. Encantado: moldura que "respira" a ouro (2,4 s),
/// parada com "remover animações". Clássico: [classic] (o destaque de hoje),
/// ou só o filho.
class TurnGlow extends StatefulWidget {
  const TurnGlow({super.key, required this.child, required this.active, this.classic, this.radius = 12});

  final Widget child;
  final bool active;
  final Widget Function(Widget child)? classic;
  final double radius;

  @override
  State<TurnGlow> createState() => _TurnGlowState();
}

class _TurnGlowState extends State<TurnGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(TurnGlow old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.active && !reduce && context.edhStyle.isEnchanted) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.edhStyle;
    if (!c.isEnchanted) return widget.classic?.call(widget.child) ?? widget.child;
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        // O brilho fica por fora (passa o anel das molduras do kit) e o fio
        // por cima do filho, para não ser tapado por ele.
        final r = BorderRadius.circular(widget.radius);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: r,
            boxShadow: [
              BoxShadow(color: c.goldLight.withOpacity(.35 + .35 * t), blurRadius: 14 + 10 * t, spreadRadius: 5),
            ],
          ),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: r,
              border: Border.all(color: Color.lerp(c.gold, c.goldPale, t)!, width: 2),
            ),
            child: child,
          ),
        );
      },
    );
  }
}
