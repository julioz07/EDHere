import 'package:flutter/material.dart' hide Table, Intent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesa_core/mesa_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/theme.dart';
import '../../data/providers.dart';
import '../../game/game_controller.dart';
import 'table_screen.dart';
import 'table_sheets.dart';
import 'table_turns.dart';
import '../widgets/life_delta.dart';
import '../../l10n/l10n.dart';

/// Mesa partilhada: dois jogadores frente a frente com um tablet (ou
/// telemóvel) no meio. A metade de cima está virada para quem está do outro
/// lado. Com [openHands] as mãos ficam à vista (para ensinar); senão ficam
/// tapadas até o dono tocar em "Ver".
class TabletTableScreen extends ConsumerStatefulWidget {
  const TabletTableScreen({super.key, required this.ctrl, this.openHands = false, this.confirmLeave});

  final GameController ctrl;
  final bool openHands;

  /// Troca a pergunta "Sair da mesa?" (o playtest pergunta se grava).
  final Future<bool> Function(BuildContext context)? confirmLeave;

  @override
  ConsumerState<TabletTableScreen> createState() => _TabletTableScreenState();
}

class _TabletTableScreenState extends ConsumerState<TabletTableScreen> {
  GameController get ctrl => widget.ctrl;
  late bool _wasOver = ctrl.state.over;

  /// Fixa a orientação enquanto se joga: o tablet está pousado na mesa e,
  /// ao mexer-lhe, o ecrã não pode rodar.
  static const _orientation = MethodChannel('edhere/orientation');

  static Future<void> _lockOrientation(bool lock) async {
    try {
      await _orientation.invokeMethod<void>(lock ? 'lock' : 'unlock');
    } on MissingPluginException {
      // Fora do Android não há canal (o iOS fica para quando houver versão).
    } on PlatformException {
      // Sem bloqueio, o jogo continua.
    }
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _lockOrientation(true);
    ctrl.addListener(_onChange);
  }

  @override
  void dispose() {
    ctrl.removeListener(_onChange);
    WakelockPlus.disable();
    _lockOrientation(false);
    super.dispose();
  }

  void _onChange() {
    final over = ctrl.state.over;
    if (over && !_wasOver) WidgetsBinding.instance.addPostFrameCallback((_) => _onGameOver());
    _wasOver = over;
  }

  Future<bool> _confirmLeave() async {
    if (widget.confirmLeave case final ask?) return ask(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sair da mesa?')),
        content: Text(tr('O jogo termina e não fica no histórico (usa "Terminar jogo" para o guardar).')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Ficar'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sair'))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _finish() async {
    final players = ctrl.state.players.values.toList();
    final winner = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Quem ganhou?')),
        children: [
          for (final p in players)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p.seat),
              child: Text(p.name, style: const TextStyle(fontSize: 16)),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, -1),
            child: Text(tr('Sem vencedor'), style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
    if (winner == null || !mounted) return;
    ctrl.gameOver(winner < 0 ? null : winner);
  }

  Future<void> _onGameOver() async {
    if (!mounted) return;
    final s = ctrl.state;
    ref.read(deckStoreProvider).saveGame(ctrl.record(winnerSeat: s.winner));
    final winner = s.winner == null ? null : s.players[s.winner];
    final close = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.emoji_events_rounded, color: winner == null ? null : GameColors.gold, size: 40),
        title: Text(winner == null ? tr('Jogo terminado') : tr('{v} ganhou', {'v': winner.name})),
        content: Text(tr('Turno {turn} · guardado no histórico.', {'turn': s.turn})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Ver a mesa'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Fechar'))),
        ],
      ),
    );
    if (close == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final seats = ctrl.state.players.keys.toList()..sort();
    // Metade de cima virada para quem está do outro lado.
    final top = seats.take(1).toList();
    final bottom = seats.skip(1).toList();

    // Cada metade fica virada para o seu jogador. Com o ecrã deitado, os
    // jogadores sentam-se nas pontas: o ecrã divide-se à esquerda e à direita
    // e cada metade roda 90°, para cada um ter uma área alta e não uma faixa
    // fina. Com o ecrã ao alto, divide-se em cima e em baixo.
    // TableTurns: os menus e detalhes abertos numa metade aparecem virados
    // para o jogador dessa metade.
    Widget half(List<int> list, int turns) => Expanded(
          child: TableTurns(
            turns: turns,
            child: RotatedBox(
              quarterTurns: turns,
              child: Row(children: [
                for (final s in list) Expanded(child: _SeatArea(ctrl: ctrl, seat: s, openHand: widget.openHands)),
              ]),
            ),
          ),
        );

    Widget bar(int turns) => TableTurns(
        turns: turns,
        child: RotatedBox(
          quarterTurns: turns,
          child: _CenterBar(
            ctrl: ctrl,
            onClose: () async {
              if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
            },
            onFinish: _finish,
          ),
        ));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
      },
      // Mesa densa: a letra do sistema só aumenta até 115% (ver TableScreen).
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: Scaffold(
          body: SafeArea(
            child: ListenableBuilder(
              listenable: ctrl,
              builder: (context, _) {
                final size = MediaQuery.sizeOf(context);
                if (size.width > size.height) {
                  return Row(children: [
                    half(top, 1),
                    bar(3),
                    if (bottom.isNotEmpty) half(bottom, 3),
                  ]);
                }
                return Column(children: [
                  half(top, 2),
                  bar(0),
                  if (bottom.isNotEmpty) half(bottom, 0),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterBar extends StatelessWidget {
  const _CenterBar({required this.ctrl, required this.onClose, required this.onFinish});
  final GameController ctrl;
  final VoidCallback onClose;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final s = ctrl.state;
    final theme = Theme.of(context);
    return Container(
      height: 44,
      color: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        IconButton(tooltip: tr('Sair'), icon: const Icon(Icons.close), onPressed: onClose),
        Flexible(
          child: Text(
            s.over
                ? tr('Jogo terminado')
                : tr('Turno {turn} · {v}', {'turn': s.turn, 'v': s.players[s.activeSeat]?.name ?? ''}),
            style: theme.textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: tr('Desfazer'),
          onPressed: () {
            // Desfaz a última ação, seja de quem for (todos estão à mesa).
            for (final seat in ctrl.mySeats) {
              if (ctrl.table.canUndo(seat)) {
                ctrl.sendAs(seat, ctrl.table.undo());
                break;
              }
            }
          },
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: tr('Registo'),
          onPressed: () => showLogSheet(context, ctrl),
          icon: const Icon(Icons.receipt_long),
        ),
        IconButton(
          tooltip: tr('Lançar d20'),
          onPressed: () => ctrl.rollDie(20),
          icon: const Icon(Icons.casino_outlined),
        ),
        IconButton(tooltip: tr('Moeda'), onPressed: ctrl.flipCoin, icon: const Icon(Icons.toll)),
        IconButton(
          tooltip: tr('Terminar jogo'),
          onPressed: s.over ? null : onFinish,
          icon: const Icon(Icons.emoji_events_outlined),
        ),
      ]),
    );
  }
}

class _SeatArea extends StatelessWidget {
  const _SeatArea({required this.ctrl, required this.seat, required this.openHand});
  final GameController ctrl;
  final int seat;
  final bool openHand;

  @override
  Widget build(BuildContext context) {
    final s = ctrl.state;
    final p = s.players[seat]!;
    final theme = Theme.of(context);
    final active = s.activeSeat == seat;
    final last = s.log.isEmpty ? null : s.log.last;
    final showResult = last != null && (last.type == Ev.rollDie || last.type == Ev.flipCoin) && last.actor == seat;
    // a cor do lugar, como na faixa dos jogadores e na mesa do bot: forte na vez dele
    final color = GameColors.player((s.players.keys.toList()..sort()).indexOf(seat));
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(
          color: active ? color : color.withOpacity(0.45),
          width: active ? 3 : 1.5,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Expanded(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(children: [
                Flexible(
                  child: Text(p.name, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 4),
                LifeStepButton(
                  up: false,
                  onChange: (d) => ctrl.sendAs(seat, Intent(Ev.life, {'seat': seat, 'delta': d})),
                ),
                GestureDetector(
                  onTap: () {
                    ctrl.actAs(seat);
                    showPlayerSheet(context, ctrl, seat);
                  },
                  child: Text('${p.life}',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800, color: p.life <= 0 ? EdhColors.bad : null)),
                ),
                LifeStepButton(
                  up: true,
                  onChange: (d) => ctrl.sendAs(seat, Intent(Ev.life, {'seat': seat, 'delta': d})),
                ),
                LifeDelta(life: p.life),
                if (showResult)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.casino_outlined, size: 16),
                      label: Text(ctrl.logText(last).split(': ').last),
                    ),
                  ),
                const Spacer(),
                // Com texto: só com o ícone, ninguém percebia onde se criam tokens.
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () {
                    ctrl.actAs(seat);
                    showTokenSheet(context, ctrl);
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: Text(tr('Token')),
                ),
                if (active)
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, EdhSize.buttonCompact)),
                    onPressed: () => ctrl.sendAs(seat, const Intent(Ev.passTurn, {})),
                    child: Text(tr('Passar')),
                  ),
              ]),
            ),
            // Duas filas de cartas por metade: cartas maiores do que no ecrã inteiro.
            Expanded(child: TableBattlefield(ctrl: ctrl, seat: seat, rows: 2.3)),
            TableHand(ctrl: ctrl, seat: seat, hidden: !openHand, height: 100),
          ]),
        ),
        SizedBox(
          width: 78,
          child: SingleChildScrollView(
            child: TableZonesRow(ctrl: ctrl, seat: seat, vertical: true, pileWidth: 50),
          ),
        ),
      ]),
    );
  }
}
