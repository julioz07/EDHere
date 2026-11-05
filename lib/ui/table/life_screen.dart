import 'package:flutter/material.dart' hide Table, Intent;
import 'package:mesa_core/mesa_core.dart';

import '../../app/theme.dart';
import '../../game/game_controller.dart';
import '../../l10n/l10n.dart';
import '../widgets/card_art.dart';
import '../widgets/life_delta.dart';

/// O que se conta no ecrã das vidas.
enum _Mode { life, commander, poison }

/// As vidas de todos em grande, cada um sobre a ilustração do seu comandante.
/// Tocar na metade esquerda tira 1, na direita dá 1; manter premido muda 10.
class LifeScreen extends StatefulWidget {
  const LifeScreen({super.key, required this.ctrl});
  final GameController ctrl;

  @override
  State<LifeScreen> createState() => _LifeScreenState();
}

class _LifeScreenState extends State<LifeScreen> {
  _Mode _mode = _Mode.life;
  GameController get ctrl => widget.ctrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final s = ctrl.state;
        final seats = s.players.keys.toList()..sort();
        // o meu comandante: no modo "Comandante" conta o dano que ele faz a cada um
        final mine = s.cards.values.where((c) => c.isCommander && ctrl.mySeats.contains(c.owner)).firstOrNull;
        final hasCommanders = s.cards.values.any((c) => c.isCommander);
        final wide = MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
        final cols = seats.length <= 2 ? (wide ? 2 : 1) : (wide ? (seats.length > 4 ? 3 : seats.length) : 2);
        return Scaffold(
          backgroundColor: const Color(0xFF0E1116),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: Text(tr('Vidas')),
          ),
          body: SafeArea(
            top: false,
            child: Column(children: [
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  final rows = (seats.length / cols).ceil();
                  final h = (box.maxHeight - 12 - (rows - 1) * 8) / rows;
                  final w = (box.maxWidth - 24 - (cols - 1) * 8) / cols;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final (i, seat) in seats.indexed)
                        SizedBox(
                          width: w,
                          height: h,
                          child: _panel(context, seat, GameColors.player(i), mine),
                        ),
                    ]),
                  );
                }),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SegmentedButton<_Mode>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    foregroundColor: Colors.white,
                    selectedForegroundColor: theme.colorScheme.onPrimary,
                    selectedBackgroundColor: theme.colorScheme.primary,
                    side: const BorderSide(color: Colors.white30),
                  ),
                  segments: [
                    ButtonSegment(value: _Mode.life, icon: const Icon(Icons.favorite_rounded), label: Text(tr('Vida'))),
                    if (hasCommanders && mine != null)
                      ButtonSegment(
                          value: _Mode.commander, icon: const Icon(Icons.star_rounded), label: Text(tr('Comandante'))),
                    ButtonSegment(
                        value: _Mode.poison, icon: const Icon(Icons.coronavirus_outlined), label: Text(tr('Veneno'))),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) => setState(() => _mode = v.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  switch (_mode) {
                    _Mode.life => tr('Toca à esquerda para tirar 1 e à direita para dar 1. Mantém premido para 10.'),
                    _Mode.commander => tr('O dano que o teu comandante faz a cada jogador (também desconta na vida).'),
                    _Mode.poison => tr('Veneno de cada jogador: com 10, perde.'),
                  },
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _panel(BuildContext context, int seat, Color color, CardInstance? mine) {
    final theme = Theme.of(context);
    final s = ctrl.state;
    final p = s.players[seat]!;
    final cmd = s.cards.values.where((c) => c.isCommander && c.owner == seat).firstOrNull;
    final card = cmd == null ? null : ctrl.card(cmd.oracleId, printId: cmd.printId);
    final dead = p.defeated;
    // o meu comandante não se ataca a si próprio
    final cmdHere = _mode == _Mode.commander && mine != null && mine.owner != seat;
    final value = switch (_mode) {
      _Mode.life => p.life,
      _Mode.commander => cmdHere ? p.commanderDamage[mine.id] ?? 0 : null,
      _Mode.poison => p.counters[PlayerCounter.poison] ?? 0,
    };
    void change(int d) {
      switch (_mode) {
        case _Mode.life:
          ctrl.life(seat, d);
        case _Mode.commander:
          if (cmdHere && (p.commanderDamage[mine.id] ?? 0) + d >= 0) ctrl.commanderDamage(seat, mine.id, d);
        case _Mode.poison:
          if ((p.counters[PlayerCounter.poison] ?? 0) + d >= 0) ctrl.playerCounter(seat, PlayerCounter.poison, d);
      }
    }

    final danger = switch (_mode) {
      _Mode.life => p.life <= 0,
      _Mode.commander => (value ?? 0) >= 21,
      _Mode.poison => (value ?? 0) >= 10,
    };
    Widget half(int d, Alignment a, String glyph) => Expanded(
          child: Semantics(
            button: true,
            label: '${p.name}: ${d > 0 ? '+1' : '−1'}',
            child: InkWell(
              onTap: value == null ? null : () => change(d),
              onLongPress: value == null ? null : () => change(d * 10),
              child: Align(
                alignment: a,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  // sem nada para contar (o meu comandante contra mim), sem botões
                  child: value == null
                      ? null
                      : Text(glyph,
                          style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w300,
                              color: d < 0 ? GameColors.attack : GameColors.lifeGain)),
                ),
              ),
            ),
          ),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: s.activeSeat == seat ? color : color.withOpacity(0.4), width: 2),
        ),
        child: ArtBanner.card(
          card,
          scrim: ArtScrim.full,
          child: Opacity(
            opacity: dead ? 0.45 : 1,
            child: Stack(children: [
              Material(
                type: MaterialType.transparency,
                child: Row(children: [half(-1, Alignment.centerLeft, '−'), half(1, Alignment.centerRight, '+')]),
              ),
              IgnorePointer(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(value == null ? '—' : '$value',
                          style: theme.textTheme.displayMedium?.copyWith(
                              color: danger ? GameColors.attack : Colors.white, fontWeight: FontWeight.w900)),
                    ),
                    if (_mode == _Mode.life) SizedBox(height: 18, child: LifeDelta(life: p.life, fontSize: 14)),
                  ]),
                ),
              ),
              Positioned(
                left: 12,
                top: 8,
                right: 12,
                child: IgnorePointer(
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(ctrl.mySeats.contains(seat) ? tr('{v} (tu)', {'v': p.name}) : p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(color: Colors.white)),
                    ),
                    if (dead) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.dangerous_outlined, size: 16, color: Colors.white70),
                    ],
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
