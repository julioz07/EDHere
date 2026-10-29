import 'dart:math';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../l10n/l10n.dart';
import '../table/table_card.dart';
import '../widgets/card_view.dart';

/// Onde está cada coisa na mesa (cartas e zonas), para as cartas voarem de
/// um sítio para o outro e as setas ligarem atacantes e alvos.
///
/// Cada carta desenhada regista-se com a chave "c<id>"; as zonas sem cartas
/// à vista (mão do bot, grimório, cemitério, exílio) e as barras dos
/// jogadores registam-se com "hand:<id>", "lib:<id>", "grave:<id>",
/// "exile:<id>" e "player:<id>".
class TableGeometry {
  final _keys = <String, GlobalKey>{};

  GlobalKey key(String id) => _keys.putIfAbsent(id, () => GlobalKey(debugLabel: id));

  /// O retângulo de [id] em coordenadas de [origin] (a área da mesa), ou null se não estiver à vista.
  Rect? rect(String id, RenderBox origin) {
    final ro = _keys[id]?.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize || !origin.attached) return null;
    return ro.localToGlobal(Offset.zero, ancestor: origin) & ro.size;
  }

  /// Todas as posições conhecidas agora (antes de a mesa mudar).
  Map<String, Rect> snapshot(RenderBox origin) => {
        for (final id in _keys.keys)
          if (rect(id, origin) case final r?) id: r,
      };
}

/// Uma carta a voar de [from] para o sítio [toKey] (que só se mede depois de a mesa mudar).
class FlightSpec {
  FlightSpec({required this.cardId, required this.card, required this.from, required this.toKey, this.vanish = false});

  final int cardId;
  final db.Card? card;
  final Rect from;
  final String toKey;

  /// Vai para uma zona sem cartas à vista (cemitério, mão do bot): encolhe e desaparece.
  final bool vanish;
}

/// A camada por cima da mesa onde as cartas voam. As cartas que estão a voar
/// para um lugar na mesa ficam escondidas lá até chegarem (ver [hidden]).
class FlightLayer extends StatefulWidget {
  const FlightLayer({super.key, required this.duration, required this.onLanded});

  /// Duração de cada voo (acompanha a velocidade do bot).
  final Duration duration;

  /// Uma carta chegou ao destino (deixa de estar escondida).
  final void Function(int cardId) onLanded;

  @override
  State<FlightLayer> createState() => FlightLayerState();
}

class _Flight {
  _Flight(this.spec, this.to, this.controller);
  final FlightSpec spec;
  final Rect to;
  final AnimationController controller;
}

class FlightLayerState extends State<FlightLayer> with TickerProviderStateMixin {
  final _flights = <_Flight>[];

  /// Começa os voos; [resolve] dá o retângulo de destino de cada um (null = não voa).
  void launch(List<FlightSpec> specs, Rect? Function(String key) resolve) {
    assert(() {
      for (final s in specs) {
        debugPrint('forge flight ${s.cardId} ${s.card?.name} -> ${s.toKey} to=${resolve(s.toKey)}');
      }
      return true;
    }());
    var delay = 0;
    for (final s in specs) {
      final to = resolve(s.toKey);
      if (to == null || (to.center - s.from.center).distance < 4) {
        widget.onLanded(s.cardId);
        continue;
      }
      final c = AnimationController(vsync: this, duration: widget.duration);
      final f = _Flight(s, to, c);
      c.addStatusListener((st) {
        if (st != AnimationStatus.completed) return;
        widget.onLanded(s.cardId);
        if (!mounted) return;
        setState(() => _flights.remove(f));
        c.dispose();
      });
      _flights.add(f);
      // várias cartas de uma vez saem uma a seguir à outra
      Future<void>.delayed(Duration(milliseconds: delay), () {
        if (mounted) c.forward();
      });
      delay += 70;
    }
    setState(() {});
  }

  @override
  void dispose() {
    for (final f in _flights) {
      f.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(clipBehavior: Clip.none, children: [
        for (final f in _flights)
          AnimatedBuilder(
            animation: f.controller,
            builder: (context, _) {
              final t = Curves.easeInOutCubic.transform(f.controller.value);
              final r = Rect.lerp(f.spec.from, f.to, t)!;
              // sobe um pouco a meio do voo (um arco) e cresce, como uma carta levantada da mesa
              final lift = sin(pi * t) * min(60.0, (f.to.center - f.spec.from.center).distance * 0.2);
              final scale = f.spec.vanish ? 1 + 0.1 * sin(pi * t) - 0.5 * t : 1 + 0.18 * sin(pi * t);
              final opacity = f.spec.vanish ? (1 - max(0.0, t - 0.6) / 0.4).clamp(0.0, 1.0) : 1.0;
              final w = f.spec.vanish ? f.spec.from.width : r.width;
              return Positioned(
                left: r.center.dx - w / 2,
                top: r.center.dy - w / cardAspect / 2 - lift,
                width: w,
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: scale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(w * cardCorner),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 12 * sin(pi * t) + 2)],
                      ),
                      child: f.spec.card == null
                          ? const AspectRatio(aspectRatio: cardAspect, child: CardBack())
                          : CardImage(f.spec.card!),
                    ),
                  ),
                ),
              );
            },
          ),
      ]),
    );
  }
}

/// Uma seta de combate: de [from] para [to], vermelha a atacar, azul a bloquear.
class CombatArrow {
  const CombatArrow(this.from, this.to, {required this.block});
  final String from;
  final String to;
  final bool block;
}

/// Desenha as setas de combate por cima da mesa (mede as posições ao pintar).
class CombatArrowsPainter extends CustomPainter {
  CombatArrowsPainter({required this.geo, required this.origin, required this.arrows, required this.pulse})
      : super(repaint: pulse);

  final TableGeometry geo;
  final GlobalKey origin;
  final List<CombatArrow> arrows;
  final Animation<double> pulse;

  static const attackColor = GameColors.attack;
  static const blockColor = GameColors.block;

  @override
  void paint(Canvas canvas, Size size) {
    final box = origin.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    for (final a in arrows) {
      final from = geo.rect(a.from, box);
      final to = geo.rect(a.to, box);
      if (from == null || to == null) continue;
      final color = a.block ? blockColor : attackColor;
      // do meio da carta para a borda do alvo mais próxima
      final start = from.center;
      final end = Offset(to.center.dx, start.dy > to.center.dy ? to.bottom - 4 : to.top + 4);
      final mid = Offset.lerp(start, end, 0.5)!;
      final bend = (end - start).distance * 0.18;
      final normal = Offset(-(end - start).dy, (end - start).dx) / max(1, (end - start).distance);
      final ctrl = mid + normal * bend;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
      final glow = 0.55 + 0.35 * pulse.value;
      canvas.drawPath(
          path,
          Paint()
            ..color = Colors.black.withOpacity(0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9
            ..strokeCap = StrokeCap.round);
      canvas.drawPath(
          path,
          Paint()
            ..color = color.withOpacity(glow)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round);
      // ponta da seta
      final dir = (end - ctrl) / max(1, (end - ctrl).distance);
      final side = Offset(-dir.dy, dir.dx);
      final head = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo((end - dir * 16 + side * 9).dx, (end - dir * 16 + side * 9).dy)
        ..lineTo((end - dir * 16 - side * 9).dx, (end - dir * 16 - side * 9).dy)
        ..close();
      canvas.drawPath(head, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(CombatArrowsPainter oldDelegate) => true;
}

/// A carta em grande por cima da mesa (tocar sem largar), como no Arena: ver
/// sem sair do jogo. Fecha com um toque; "Ficha" abre a ficha completa.
class CardPeek extends StatelessWidget {
  const CardPeek({super.key, required this.card, required this.onClose, required this.onDetails});

  final db.Card card;
  final VoidCallback onClose;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = min(size.width * 0.75, size.height * 0.55 * cardAspect).clamp(160.0, 420.0);
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black.withOpacity(0.6),
        alignment: Alignment.center,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.85, end: 1),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: w, child: CardImage(card, preferNormal: true)),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size(120, EdhSize.buttonCompact)),
              onPressed: onDetails,
              icon: const Icon(Icons.info_outline),
              label: Text(tr('Ficha completa')),
            ),
          ]),
        ),
      ),
    );
  }
}
