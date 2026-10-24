import 'dart:math';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';

import '../../bot/forge_table.dart';
import '../../l10n/l10n.dart';
import '../widgets/card_view.dart';

/// Destaque de uma jogada do bot (como no Arena): a carta em grande no meio da
/// mesa com o que vai fazer, ou as criaturas que atacam. Some sozinho ao fim
/// da pausa do Forge; tocar fecha-o antes.
class BotSpotlight extends StatelessWidget {
  const BotSpotlight({super.key, required this.spot, required this.state, required this.lookup, required this.onClose});

  final ForgeSpot spot;
  final ForgeTableState? state;
  final ForgeCardLookup lookup;
  final VoidCallback onClose;

  db.Card? _card(int? id, String? name) {
    final onTable = id == null ? null : state?.card(id)?.card;
    if (onTable != null) return onTable;
    return name == null ? null : lookup.byName(name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final who = state?.player(spot.by ?? -1)?.name ?? tr('O bot');
    final attack = spot.kind == 'attack';
    final title = switch (spot.kind) {
      'cast' => tr('{v} lança', {'v': who}),
      'ability' => tr('{v} ativa', {'v': who}),
      'trigger' => tr('Habilidade de {v}', {'v': who}),
      'land' => tr('{v} joga um terreno', {'v': who}),
      _ => spot.cards.length == 1
          ? tr('{v} ataca com 1 criatura', {'v': who})
          : tr('{v} ataca com {n} criaturas', {'v': who, 'n': spot.cards.length}),
    };
    // a carta ocupa boa parte do ecrã, mas cabe sempre com o texto por baixo
    final big = min(size.width * 0.55, size.height * 0.36).clamp(120.0, 300.0);
    final Widget cards;
    if (attack) {
      final n = spot.cards.length;
      final w = n <= 1 ? big : (size.width * 0.8 / n - 8).clamp(56.0, big * 0.7);
      cards = Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < n; i++)
          _SpotCard(
            card: _card(spot.cards[i], i < spot.names.length ? spot.names[i] : null),
            name: i < spot.names.length ? spot.names[i] : '',
            width: w,
            glow: theme.colorScheme.error,
          ),
      ]);
    } else {
      cards = _SpotCard(
          card: _card(spot.cardId, spot.name), name: spot.name ?? '', width: big, glow: theme.colorScheme.primary);
    }
    // o texto da pilha do Forge traz o nome da carta e um id entre parênteses: fica só o efeito
    final effect = spot.kind == 'land' || attack ? null : _effect(spot.text, spot.name);
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black.withOpacity(0.55),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            cards,
            if (effect != null && effect.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(effect,
                    textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white)),
              ),
            ],
            if (spot.targets != null) ...[
              const SizedBox(height: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.gps_fixed, color: Color(0xFFFF8A80), size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(spot.targets!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFFFF8A80))),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  static String? _effect(String? text, String? name) {
    if (text == null) return null;
    // sem os ids "(123)" e sem a causa do gatilho que o Forge junta no fim ("[Cambio di zona: ...]")
    var t = text.replaceAll(RegExp(r'\s*\(\d+\)'), '').replaceAll(RegExp(r'\s*\[[^\]]*\]\s*$'), '').trim();
    if (name != null && t.startsWith(name)) {
      t = t.substring(name.length).replaceFirst(RegExp(r'^\s*[-:]\s*'), '').trim();
    }
    return t;
  }
}

class _SpotCard extends StatelessWidget {
  const _SpotCard({required this.card, required this.name, required this.width, required this.glow});

  final db.Card? card;
  final String name;
  final double width;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.05),
        boxShadow: [BoxShadow(color: glow.withOpacity(0.8), blurRadius: 24, spreadRadius: 2)],
      ),
      child: card == null
          ? AspectRatio(
              aspectRatio: cardAspect,
              child: Card(child: Center(child: Text(name, textAlign: TextAlign.center))),
            )
          : CardImage(card!, preferNormal: true, radius: width * 0.05),
    );
  }
}

/// Faixa no início de cada turno: "O teu turno" ou "Turno do bot".
class TurnBanner extends StatelessWidget {
  const TurnBanner({super.key, required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = mine ? scheme.primary : scheme.tertiary;
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16)],
            ),
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: mine ? scheme.onPrimary : scheme.onTertiary)),
          ),
        ),
      ),
    );
  }
}

/// As fases do turno numa faixa: início, principal 1, combate, principal 2 e
/// fim, com a atual acesa na cor de quem joga e o passo do combate por extenso.
class PhaseBar extends StatelessWidget {
  const PhaseBar({super.key, required this.phase, required this.mine, required this.compact});

  /// O PhaseType do Forge.
  final String? phase;
  final bool mine;
  final bool compact;

  static int? _segment(String? p) => switch (p) {
        'UNTAP' || 'UPKEEP' || 'DRAW' => 0,
        'MAIN1' => 1,
        'COMBAT_BEGIN' ||
        'COMBAT_DECLARE_ATTACKERS' ||
        'COMBAT_DECLARE_BLOCKERS' ||
        'COMBAT_FIRST_STRIKE_DAMAGE' ||
        'COMBAT_DAMAGE' ||
        'COMBAT_END' =>
          2,
        'MAIN2' => 3,
        'END_OF_TURN' || 'CLEANUP' => 4,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = mine ? scheme.primary : scheme.tertiary;
    final current = _segment(phase);
    final segments = [
      (Icons.wb_twilight, tr('Início')),
      (Icons.looks_one_outlined, tr('Principal 1')),
      (Icons.flash_on, tr('Combate')),
      (Icons.looks_two_outlined, tr('Principal 2')),
      (Icons.nightlight_outlined, tr('Fim')),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        for (var i = 0; i < segments.length; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: i == current ? on : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(segments[i].$1, size: 14, color: i == current ? scheme.onPrimary : scheme.onSurfaceVariant),
                if (!compact || i == current) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      // no combate, o passo em que está
                      i == current && i == 2 && phase != 'COMBAT_BEGIN' ? _combatStep(phase) : segments[i].$2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: i == current ? scheme.onPrimary : scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ]),
            ),
          ),
      ]),
    );
  }

  static String _combatStep(String? p) => switch (p) {
        'COMBAT_DECLARE_ATTACKERS' => tr('Atacantes'),
        'COMBAT_DECLARE_BLOCKERS' => tr('Bloqueadores'),
        'COMBAT_FIRST_STRIKE_DAMAGE' || 'COMBAT_DAMAGE' => tr('Dano'),
        'COMBAT_END' => tr('Fim do combate'),
        _ => tr('Combate'),
      };
}

/// A vida de um jogador: treme e pisca a vermelho ao descer, brilha a verde ao
/// subir, com a diferença a subir por cima ("-3", "+2").
class AnimatedLife extends StatefulWidget {
  const AnimatedLife({super.key, required this.life, this.style});

  final int life;
  final TextStyle? style;

  @override
  State<AnimatedLife> createState() => _AnimatedLifeState();
}

class _AnimatedLifeState extends State<AnimatedLife> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  int _delta = 0;

  @override
  void didUpdateWidget(AnimatedLife old) {
    super.didUpdateWidget(old);
    if (old.life != widget.life) {
      _delta = widget.life - old.life;
      _anim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final t = _anim.value;
        final active = _anim.isAnimating;
        final lost = _delta < 0;
        final color = lost ? const Color(0xFFE53935) : const Color(0xFF43A047);
        // tremer só ao perder, a amortecer
        final shake = active && lost ? sin(t * pi * 10) * 6 * (1 - t) : 0.0;
        final glow = active ? (1 - t) : 0.0;
        return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          Transform.translate(
            offset: Offset(shake, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: glow > 0
                    ? [BoxShadow(color: color.withOpacity(0.7 * glow), blurRadius: 16, spreadRadius: 3)]
                    : null,
              ),
              child: Text('${widget.life}',
                  style:
                      widget.style?.copyWith(color: glow > 0.3 ? Color.lerp(widget.style?.color, color, glow) : null)),
            ),
          ),
          if (active)
            Positioned(
              top: -18 - 18 * t,
              child: Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: Text(lost ? '$_delta' : '+$_delta',
                    style:
                        Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.bold)),
              ),
            ),
        ]);
      },
    );
  }
}
