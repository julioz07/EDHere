import 'package:flutter/material.dart' hide Table, Intent;
import 'package:mesa_core/mesa_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/theme.dart';
import '../../game/game_controller.dart';
import 'table_screen.dart';
import 'table_sheets.dart';

/// Modo tablet: vários jogadores à volta de um tablet, cada um com a sua
/// área virada para o seu lado. As mãos ficam tapadas até o dono tocar em
/// "Ver".
class TabletTableScreen extends StatefulWidget {
  const TabletTableScreen({super.key, required this.ctrl});

  final GameController ctrl;

  @override
  State<TabletTableScreen> createState() => _TabletTableScreenState();
}

class _TabletTableScreenState extends State<TabletTableScreen> {
  GameController get ctrl => widget.ctrl;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seats = ctrl.state.players.keys.toList()..sort();
    // Metade de cima virada para quem está do outro lado.
    final top = seats.length <= 2 ? seats.take(1).toList() : seats.take((seats.length + 1) ~/ 2).toList();
    final bottom = seats.where((s) => !top.contains(s)).toList();

    Widget row(List<int> list, {required bool flipped}) => Expanded(
          child: RotatedBox(
            quarterTurns: flipped ? 2 : 0,
            child: Row(children: [
              for (final s in flipped ? list.reversed : list) Expanded(child: _SeatArea(ctrl: ctrl, seat: s)),
            ]),
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: ctrl,
          builder: (context, _) => Column(children: [
            row(top, flipped: true),
            _CenterBar(ctrl: ctrl),
            if (bottom.isNotEmpty) row(bottom, flipped: false),
          ]),
        ),
      ),
    );
  }
}

class _CenterBar extends StatelessWidget {
  const _CenterBar({required this.ctrl});
  final GameController ctrl;

  @override
  Widget build(BuildContext context) {
    final s = ctrl.state;
    final theme = Theme.of(context);
    return Container(
      height: 44,
      color: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        IconButton(
          tooltip: 'Sair',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        Text('Turno ${s.turn} · ${s.players[s.activeSeat]?.name ?? ''}', style: theme.textTheme.titleSmall),
        const Spacer(),
        IconButton(
          tooltip: 'Desfazer',
          onPressed: () {
            final last = ctrl.table.lastUndoableSeq;
            if (last == null) return;
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
          tooltip: 'Registo',
          onPressed: () => showLogSheet(context, ctrl),
          icon: const Icon(Icons.receipt_long),
        ),
        IconButton(
            tooltip: 'd20', onPressed: () => ctrl.rollDie(20), icon: const Icon(Icons.casino_outlined)),
      ]),
    );
  }
}

class _SeatArea extends StatelessWidget {
  const _SeatArea({required this.ctrl, required this.seat});
  final GameController ctrl;
  final int seat;

  @override
  Widget build(BuildContext context) {
    final s = ctrl.state;
    final p = s.players[seat]!;
    final theme = Theme.of(context);
    final active = s.activeSeat == seat;
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(
          color: active ? theme.colorScheme.primary : theme.colorScheme.outline,
          width: active ? 3 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(children: [
            Text(p.name, style: theme.textTheme.titleSmall),
            const SizedBox(width: 8),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => ctrl.sendAs(seat, Intent(Ev.life, {'seat': seat, 'delta': -1})),
              icon: const Icon(Icons.remove),
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
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => ctrl.sendAs(seat, Intent(Ev.life, {'seat': seat, 'delta': 1})),
              icon: const Icon(Icons.add),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Token',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                ctrl.actAs(seat);
                showTokenSheet(context, ctrl);
              },
              icon: const Icon(Icons.toll_outlined),
            ),
            if (active)
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
                onPressed: () => ctrl.sendAs(seat, const Intent(Ev.passTurn, {})),
                child: const Text('Passar'),
              ),
          ]),
        ),
        Expanded(child: TableBattlefield(ctrl: ctrl, seat: seat)),
        TableZonesRow(ctrl: ctrl, seat: seat),
        TableHand(ctrl: ctrl, seat: seat, hidden: true, height: 104),
      ]),
    );
  }
}
