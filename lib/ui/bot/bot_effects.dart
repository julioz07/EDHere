import 'dart:math';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../bot/forge_table.dart';
import '../../l10n/l10n.dart';
import '../widgets/card_view.dart';
import '../widgets/mana.dart';

/// Destaque de uma jogada do bot (como no Arena): a carta em grande sobre o
/// campo do bot com o que vai fazer, ou as criaturas que atacam. Não tapa a
/// mesa nem os toques (a lição do Runeterra: os efeitos nunca bloqueiam quem
/// joga) e some sozinho ao fim da pausa do Forge.
class BotSpotlight extends StatelessWidget {
  const BotSpotlight({super.key, required this.spot, required this.state, required this.lookup});

  final ForgeSpot spot;
  final ForgeTableState? state;
  final ForgeCardLookup lookup;

  db.Card? _card(int? id, String? name) {
    final onTable = id == null ? null : state?.card(id)?.card;
    if (onTable != null) return onTable;
    return name == null ? null : lookup.byName(name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 560;
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
    // grande o suficiente para se ler, mas a deixar ver a mesa à volta
    final big = min(size.width * (wide ? 0.22 : 0.42), size.height * 0.3).clamp(100.0, 240.0);
    final Widget cards;
    if (attack) {
      final n = spot.cards.length;
      final w = n <= 1 ? big : (size.width * 0.7 / n - 8).clamp(48.0, big * 0.7);
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
    final caption = Container(
      constraints: BoxConstraints(maxWidth: wide ? 340 : size.width * 0.86),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.72), borderRadius: BorderRadius.circular(12)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
        if (effect != null && effect.isNotEmpty) ...[
          const SizedBox(height: 4),
          OracleText(effect,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white)),
        ],
        if (spot.targets != null) ...[
          const SizedBox(height: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.gps_fixed, color: GameColors.target, size: 16),
            const SizedBox(width: 6),
            Flexible(
              // o Forge escreve "[Marwyn, the Nurturer (201)]": sem parênteses retos nem ids
              child: Text(spot.targets!.replaceAll(RegExp(r' \(\d+\)'), '').replaceAll(RegExp(r'[\[\]]'), ''),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: GameColors.target)),
            ),
          ]),
        ],
      ]),
    );
    return IgnorePointer(
      child: Align(
        // por cima do campo do bot, a deixar livre a barra de baixo e a mão
        alignment: const Alignment(0, -0.55),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(spot),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Transform.translate(
                offset: Offset(0, -30 * (1 - v)), child: Transform.scale(scale: 0.8 + 0.2 * v, child: child)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: wide && !attack
                ? Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
                    cards,
                    const SizedBox(width: 14),
                    caption,
                  ])
                : Column(mainAxisSize: MainAxisSize.min, children: [cards, const SizedBox(height: 10), caption]),
          ),
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
        borderRadius: BorderRadius.circular(width * cardCorner),
        boxShadow: [BoxShadow(color: glow.withOpacity(0.8), blurRadius: 24, spreadRadius: 2)],
      ),
      child: card == null
          ? AspectRatio(
              aspectRatio: cardAspect,
              child: Card(child: Center(child: Text(name, textAlign: TextAlign.center))),
            )
          : CardImage(card!, preferNormal: true),
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
  const PhaseBar(
      {super.key,
      required this.phase,
      required this.mine,
      required this.compact,
      this.stops = const {},
      this.onTap,
      this.color});

  /// A cor de quem joga o turno (a fase atual acende nela); sem ela, a do tema.
  final Color? color;

  /// Os segmentos onde o jogo pára à minha espera neste turno (um ponto em cima).
  final Set<int> stops;

  /// Tocar na barra abre as paragens.
  final VoidCallback? onTap;

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
    final on = color ?? (mine ? scheme.primary : scheme.tertiary);
    // texto escuro nas cores claras (o laranja do bot), branco nas escuras
    final onText = ThemeData.estimateBrightnessForColor(on) == Brightness.dark ? Colors.white : const Color(0xFF10172E);
    final current = _segment(phase);
    final segments = [
      (Icons.wb_twilight, tr('Início')),
      (Icons.looks_one_outlined, tr('Principal 1')),
      (Icons.flash_on, tr('Combate')),
      (Icons.looks_two_outlined, tr('Principal 2')),
      (Icons.nightlight_outlined, tr('Fim')),
    ];
    return GestureDetector(
      onTap: onTap,
      // no tablet, uma faixa centrada: cinco comprimidos a toda a largura pareciam um formulário
      child: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          for (var i = 0; i < segments.length; i++)
            Expanded(
              // no telemóvel a fase atual é mais larga, para o nome caber
              flex: compact && i == current ? 4 : 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: i == current ? on : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (stops.contains(i))
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: i == current ? onText : GameColors.stop,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Icon(segments[i].$1, size: 14, color: i == current ? onText : scheme.onSurfaceVariant),
                  if (!compact || i == current) ...[
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        // no combate, o passo em que está
                        i == current && i == 2 && phase != 'COMBAT_BEGIN' ? _combatStep(phase) : segments[i].$2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: i == current ? onText : scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
        ]),
      ),
      )),
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
        final color = lost ? GameColors.attack : GameColors.lifeGain;
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

/// Três pontos a pulsar: o bot está a decidir.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key});

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Opacity(
              // cada ponto acende um pouco depois do anterior
              opacity: 0.25 + 0.75 * (0.5 + 0.5 * sin((_anim.value - i * 0.18) * 2 * pi)).clamp(0.0, 1.0),
              child: Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            ),
          ),
      ]),
    );
  }
}

/// O fim da partida: quem ganhou (com uma entrada animada), os turnos, um
/// gráfico da vida de cada jogador ao longo do jogo e "Revanche".
class GameOverPanel extends StatelessWidget {
  const GameOverPanel({
    super.key,
    required this.state,
    required this.meId,
    required this.history,
    required this.onRematch,
    required this.onLog,
    required this.onLeave,
  });

  final ForgeTableState state;

  /// Eu (null a ver bot contra bot).
  final int? meId;
  final Map<int, List<int>> history;
  final VoidCallback onRematch;
  final VoidCallback onLog;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winner = state.player(state.winner ?? -1);
    final won = meId != null && state.winner == meId;
    final lost = meId != null && state.winner != null && state.winner != meId;
    final title = winner == null
        ? tr('Empate')
        : won
            ? tr('Ganhaste!')
            : lost
                ? tr('O bot ganhou')
                : tr('{v} ganhou', {'v': winner.name});
    final color = won
        ? GameColors.lifeGain
        : lost
            ? GameColors.attack
            : theme.colorScheme.primary;
    // uma linha por jogador, na cor do lugar dele na mesa
    const colors = GameColors.players;
    return Container(
      color: Colors.black.withOpacity(0.6),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutBack,
        builder: (_, v, child) =>
            Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.scale(scale: 0.7 + 0.3 * v, child: child)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(
                    won
                        ? Icons.emoji_events
                        : lost
                            ? Icons.sentiment_dissatisfied
                            : Icons.flag,
                    size: 48,
                    color: color),
                const SizedBox(height: 8),
                Text(title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(tr('{n} turnos', {'n': state.turn}),
                    textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                SizedBox(
                  height: 120,
                  child: CustomPaint(
                    painter: _LifeChart(
                      [for (final p in state.players) history[p.id] ?? const <int>[]],
                      colors,
                      theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(alignment: WrapAlignment.center, spacing: 12, children: [
                  for (var i = 0; i < state.players.length; i++)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 10, height: 10, color: colors[i % colors.length]),
                      const SizedBox(width: 4),
                      Text('${state.players[i].name}: ${state.players[i].life}', style: theme.textTheme.bodySmall),
                    ]),
                ]),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: onRematch, icon: const Icon(Icons.replay), label: Text(tr('Revanche'))),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, EdhSize.buttonCompact)),
                        onPressed: onLog,
                        child: Text(tr('Registo'))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, EdhSize.buttonCompact)),
                        onPressed: onLeave,
                        child: Text(tr('Sair'))),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _LifeChart extends CustomPainter {
  _LifeChart(this.series, this.colors, this.grid);

  final List<List<int>> series;
  final List<Color> colors;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final s in series) ...s];
    if (all.isEmpty) return;
    final hi = all.reduce(max).toDouble();
    final lo = min(0, all.reduce(min)).toDouble();
    final n = series.map((s) => s.length).fold(0, max);
    if (n < 2) return;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var k = 0; k < series.length; k++) {
      final s = series[k];
      if (s.length < 2) continue;
      final path = Path();
      for (var i = 0; i < s.length; i++) {
        final x = size.width * i / (n - 1);
        final y = size.height * (1 - (s[i] - lo) / max(1, hi - lo));
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = colors[k % colors.length]
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round);
    }
  }

  @override
  bool shouldRepaint(_LifeChart oldDelegate) => true;
}

/// A moeda ao ar no início da partida (como no Arena): roda e mostra quem
/// ganhou o lançamento. Não bloqueia os toques e some sozinha.
class CoinFlip extends StatelessWidget {
  const CoinFlip({super.key, required this.won});

  final bool won;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1300),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            // 5 ou 6 voltas a abrandar, a acabar na face de quem ganhou (eu ou o bot)
            final angle = t * pi * (won ? 12 : 11);
            final face = cos(angle);
            final heads = face >= 0;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Transform.translate(
                offset: Offset(0, -80 * sin(pi * t)),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..scale(max(0.05, face.abs()), 1.0),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                          colors: heads
                              ? const [Color(0xFFFFE082), Color(0xFFFFA000)]
                              : const [Color(0xFFE0E0E0), Color(0xFF9E9E9E)]),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12)],
                    ),
                    child: Icon(heads ? Icons.person : Icons.smart_toy, size: 48, color: Colors.black54),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Opacity(
                opacity: ((t - 0.8) / 0.2).clamp(0.0, 1.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration:
                      BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(12)),
                  child: Text(won ? tr('Ganhaste o lançamento da moeda!') : tr('O bot ganhou o lançamento da moeda'),
                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
