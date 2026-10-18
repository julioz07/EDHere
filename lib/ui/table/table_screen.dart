import 'package:flutter/material.dart' hide Table, Intent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesa_core/mesa_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/theme.dart';
import '../../data/providers.dart';
import '../../data/settings.dart';
import '../../game/game_controller.dart';
import '../widgets/card_view.dart';
import '../widgets/mana.dart';
import '../widgets/responsive.dart';
import 'table_card.dart';
import 'table_sheets.dart';

const _phases = [
  ('upkeep', 'Manutenção'),
  ('draw', 'Compra'),
  ('main1', 'Principal 1'),
  ('combat', 'Combate'),
  ('main2', 'Principal 2'),
  ('end', 'Final'),
];

/// Formatos em que o primeiro mulligan é grátis (multijogador de Commander).
const _freeMulligan = {'commander', 'brawl', 'paupercommander', 'oathbreaker'};

/// Layout da mesa conforme o espaço: no telemóvel ao alto, tudo em coluna;
/// em ecrãs largos (tablet, ou telemóvel deitado) as zonas vão para o lado.
({bool wide, bool short}) tableLayoutFor(Size size) {
  final landscape = size.width > size.height;
  final wide = size.width >= wideBreakpoint || (landscape && size.width >= 560);
  return (wide: wide, short: size.height < 520);
}

/// A mesa: campo do jogador em vista, zonas, mão e barra de turno.
/// Serve o playtest e o jogo em rede.
class TableScreen extends ConsumerStatefulWidget {
  const TableScreen({super.key, required this.ctrl, this.title, this.onLeave, this.banner, this.onNewGame});

  final GameController ctrl;
  final String? title;

  /// Chamado ao sair (fecha a sala, por exemplo).
  final Future<void> Function()? onLeave;

  /// Aviso no topo (ligação perdida, etc.).
  final Widget? banner;

  /// Só o anfitrião: volta todos ao lobby para outra partida.
  final VoidCallback? onNewGame;

  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<TableScreen> {
  GameController get ctrl => widget.ctrl;
  Reveal? _shownReveal;
  late bool _wasOver = ctrl.state.over;
  late int _lastLogSeq = ctrl.state.log.isEmpty ? 0 : ctrl.state.log.last.seq;
  final Set<int> _mulliganAsked = {};

  /// Resultado de dado/moeda/sorteio a mostrar em grande por cima da mesa.
  (String, String)? _bigResult;
  int _bigResultId = 0;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    if (settings.keepScreenOn) WakelockPlus.enable();
    ctrl.autoDraw = settings.autoDraw;
    ctrl.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onChange());
  }

  @override
  void dispose() {
    ctrl.removeListener(_onChange);
    WakelockPlus.disable();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    final s = ctrl.state;
    final r = s.revealed;
    if (r != null && !identical(r, _shownReveal)) {
      _shownReveal = r;
      final forMe = r.to == null || ctrl.mySeats.contains(r.to);
      if (forMe && !(ctrl.isNetwork && ctrl.mySeats.contains(r.seat))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showRevealDialog(context, ctrl, r);
        });
      }
    }
    _showNewResults();
    if (s.over && !_wasOver) {
      _wasOver = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _onGameOver());
    } else if (!s.over) {
      _wasOver = false;
    }
    _maybeAskMulligan();
  }

  /// Dados, moeda e sorteio aparecem em grande para toda a gente ver.
  void _showNewResults() {
    final log = ctrl.state.log;
    for (final e in log.where((e) => e.seq > _lastLogSeq)) {
      if (e.type == Ev.rollDie || e.type == Ev.flipCoin || e.type == Ev.randomPlayer) {
        final text = ctrl.logText(e);
        final i = text.lastIndexOf(': ');
        final value = i < 0 ? text : text.substring(i + 2);
        final label = i < 0 ? '' : text.substring(0, i);
        final id = ++_bigResultId;
        setState(() => _bigResult = (value, label));
        Future.delayed(const Duration(milliseconds: 2600), () {
          if (mounted && _bigResultId == id) setState(() => _bigResult = null);
        });
      }
    }
    if (log.isNotEmpty) _lastLogSeq = log.last.seq;
  }

  /// No início do jogo, cada mão inicial pergunta "manter ou mulligan".
  void _maybeAskMulligan() {
    final s = ctrl.state;
    if (!s.started || s.over || s.turn > 1) return;
    for (final seat in ctrl.mySeats) {
      if (_mulliganAsked.contains(seat)) continue;
      final hand = ctrl.zones(seat).hand;
      if (hand.length < 7 || (ctrl.mulligans[seat] ?? 0) > 0) continue;
      _mulliganAsked.add(seat);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _askMulligan(seat);
      });
      return; // uma de cada vez (no hot-seat, a seguinte vem depois)
    }
  }

  Future<void> _askMulligan(int seat) async {
    while (true) {
      if (!mounted) return;
      final count = ctrl.mulligans[seat] ?? 0;
      final free = _freeMulligan.contains(ctrl.state.format);
      final toBottom = free ? count - 1 : count;
      final name = ctrl.state.players[seat]?.name ?? '';
      final keep = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ListenableBuilder(
          listenable: ctrl,
          builder: (ctx, _) {
            final hand = ctrl.zones(seat).hand;
            final next = free ? count : count + 1;
            return AlertDialog(
              title: Text(ctrl.mySeats.length > 1 ? 'Mão inicial de $name' : 'A tua mão inicial'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (count > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('Mulligan $count'
                          '${toBottom > 0 ? ' · ao manter, pões $toBottom no fundo' : ' (grátis)'}'),
                    ),
                  GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 4,
                    childAspectRatio: cardAspect,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    children: [
                      for (final pc in hand)
                        if (ctrl.card(pc.oracleId, printId: pc.printId) case final c?)
                          CardImage(c, radius: 4)
                        else
                          const CardBack(),
                    ],
                  ),
                ]),
              ),
              actions: [
                TextButton(
                  onPressed: hand.length <= 1 ? null : () => Navigator.pop(ctx, false),
                  child: Text(next == 0 ? 'Mulligan (grátis)' : 'Mulligan'),
                ),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Manter')),
              ],
            );
          },
        ),
      );
      if (!mounted || keep == null) return;
      ctrl.actAs(seat);
      if (keep) {
        if (toBottom > 0) await showBottomPicker(context, ctrl, toBottom);
        break;
      }
      ctrl.mulligan();
      // Em rede a nova mão chega pelo anfitrião: espera um instante.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    _maybeAskMulligan();
  }

  Future<bool> _confirmLeave() async {
    if (!ref.read(settingsProvider).confirmLeave) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair da mesa?'),
        content: Text(ctrl.isNetwork ? 'Podes voltar a entrar depois.' : 'O playtest termina.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ficar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sair')),
        ],
      ),
    );
    return ok == true;
  }

  /// Escolher o vencedor; o fim do jogo chega a todos os dispositivos.
  Future<void> _finishGame() async {
    final players = ctrl.state.players.values.toList();
    final winner = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Quem ganhou?'),
        children: [
          for (final p in players)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p.seat),
              child: Text(ctrl.mySeats.contains(p.seat) && ctrl.isNetwork ? '${p.name} (tu)' : p.name,
                  style: const TextStyle(fontSize: 16)),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, -1),
            child: const Text('Sem vencedor', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
    if (winner == null || !mounted) return;
    ctrl.gameOver(winner < 0 ? null : winner);
  }

  /// Cada dispositivo guarda a partida no seu histórico e mostra o resultado.
  Future<void> _onGameOver() async {
    if (!mounted) return;
    final s = ctrl.state;
    ref.read(deckStoreProvider).saveGame(ctrl.record(winnerSeat: s.winner));
    final winner = s.winner == null ? null : s.players[s.winner];
    final iWon = s.winner != null && ctrl.mySeats.contains(s.winner) && ctrl.mySeats.length == 1;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.emoji_events_rounded, color: winner == null ? null : Colors.amber, size: 40),
        title: Text(winner == null
            ? 'Jogo terminado'
            : iWon
                ? 'Ganhaste!'
                : '${winner.name} ganhou'),
        content: Text('Turno ${s.turn} · guardado no histórico.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'view'), child: const Text('Ver a mesa')),
          if (!ctrl.isNetwork)
            FilledButton(onPressed: () => Navigator.pop(ctx, 'close'), child: const Text('Fechar'))
          else if (widget.onNewGame != null)
            FilledButton(onPressed: () => Navigator.pop(ctx, 'again'), child: const Text('Nova partida')),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'close':
        Navigator.of(context).pop();
      case 'again':
        widget.onNewGame?.call();
    }
  }

  void _menu() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        void run(VoidCallback f) {
          Navigator.pop(ctx);
          f();
        }

        return SafeArea(
          child: ListenableBuilder(
            listenable: ctrl,
            builder: (ctx, _) => SingleChildScrollView(
              child: Wrap(children: [
                SwitchListTile(
                  title: const Text('Compra automática no início do turno'),
                  value: ctrl.autoDraw,
                  onChanged: (v) => set(() => ctrl.autoDraw = v),
                ),
                ListTile(
                  leading: const Icon(Icons.bolt),
                  title: Text('Storm neste turno: ${ctrl.state.storm}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        onPressed: ctrl.state.storm > 0 ? () => ctrl.storm(-1) : null,
                        icon: const Icon(Icons.remove_circle_outline)),
                    IconButton(onPressed: () => ctrl.storm(1), icon: const Icon(Icons.add_circle_outline)),
                  ]),
                ),
                ListTile(
                  leading:
                      Icon(ctrl.state.dayNight == 'night' ? Icons.nightlight_round : Icons.wb_sunny_outlined),
                  title: const Text('Dia / noite'),
                  trailing: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: '-', label: Text('—')),
                      ButtonSegment(value: 'day', label: Text('Dia')),
                      ButtonSegment(value: 'night', label: Text('Noite')),
                    ],
                    selected: {ctrl.state.dayNight ?? '-'},
                    onSelectionChanged: (v) => ctrl.dayNight(v.first == '-' ? null : v.first),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.emoji_events_outlined),
                  title: const Text('Terminar jogo'),
                  subtitle: const Text('Escolhe o vencedor; fica no histórico de todos'),
                  onTap: () => run(_finishGame),
                ),
                ListTile(
                  leading: const Icon(Icons.toll_outlined),
                  title: const Text('Criar token'),
                  onTap: () => run(() => showTokenSheet(context, ctrl)),
                ),
                ListTile(
                  leading: const Icon(Icons.gps_fixed, color: targetGlow),
                  title: const Text('Apontar para… (carta ou jogador)'),
                  onTap: () => run(() => showTargetPicker(context, ctrl)),
                ),
                ListTile(
                  leading: const Icon(Icons.undo),
                  title: const Text('Desvirar tudo'),
                  onTap: () => run(() => ctrl.send(Intent(Ev.untapAll, {'seat': ctrl.actor}))),
                ),
                ListTile(
                  leading: const Icon(Icons.casino_outlined),
                  title: const Text('Lançar d6'),
                  onTap: () => run(() => ctrl.rollDie(6)),
                ),
                ListTile(
                  leading: const Icon(Icons.casino),
                  title: const Text('Lançar d20'),
                  onTap: () => run(() => ctrl.rollDie(20)),
                ),
                ListTile(
                  leading: const Icon(Icons.toll),
                  title: const Text('Lançar moeda'),
                  onTap: () => run(ctrl.flipCoin),
                ),
                ListTile(
                  leading: const Icon(Icons.shuffle_on_outlined),
                  title: const Text('Escolher jogador ao acaso'),
                  onTap: () => run(ctrl.randomPlayer),
                ),
                ListTile(
                  leading: const Icon(Icons.clear_all),
                  title: const Text('Limpar os meus alvos e o destaque'),
                  onTap: () => run(() {
                    ctrl.send(const Intent(Ev.arrow, {}));
                    ctrl.highlight(null);
                  }),
                ),
                ListTile(
                  leading: const Icon(Icons.visibility),
                  title: const Text('Revelar a minha mão a todos'),
                  onTap: () => run(() {
                    final hand = ctrl.zones(ctrl.actor).hand;
                    if (hand.isNotEmpty) {
                      ctrl.send(ctrl.table
                          .revealHidden(ctrl.actor, Zone.hand, [for (final c in hand) c.pid], what: 'a mão'));
                    }
                  }),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave()) {
          await widget.onLeave?.call();
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final s = ctrl.state;
          final theme = Theme.of(context);
          final active = s.players[s.activeSeat];
          final phaseLabel = _phases.firstWhere((p) => p.$1 == s.phase, orElse: () => _phases[2]).$2;
          final myTurn = ctrl.mySeats.contains(s.activeSeat) && ctrl.isNetwork;
          final layout = tableLayoutFor(MediaQuery.sizeOf(context));
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: layout.short ? 44 : 48,
              titleSpacing: 0,
              title: Text(
                s.over
                    ? 'Jogo terminado'
                    : myTurn
                        ? 'T${s.turn} · o teu turno'
                        : 'T${s.turn} · ${active?.name ?? ''}',
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                if (s.storm > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.bolt, size: 16),
                      label: Text('${s.storm}'),
                    ),
                  ),
                if (s.dayNight != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(s.dayNight == 'night' ? Icons.nightlight_round : Icons.wb_sunny,
                        color: s.dayNight == 'night' ? Colors.indigo.shade200 : Colors.amber),
                  ),
                ActionChip(
                  label: Text(phaseLabel, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    final i = _phases.indexWhere((p) => p.$1 == s.phase);
                    ctrl.send(Intent(Ev.setPhase, {'phase': _phases[(i + 1) % _phases.length].$1}));
                  },
                ),
                IconButton(
                  tooltip: 'Desfazer',
                  onPressed: ctrl.canUndo ? ctrl.undo : null,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: 'Registo',
                  onPressed: () => showLogSheet(context, ctrl),
                  icon: const Icon(Icons.receipt_long),
                ),
                IconButton(tooltip: 'Mais', onPressed: _menu, icon: const Icon(Icons.more_vert)),
              ],
            ),
            body: Stack(children: [
              LayoutBuilder(builder: (context, box) {
                final lastLog = s.log.isEmpty ? '' : ctrl.logText(s.log.last);
                if (!layout.wide) {
                  return Column(children: [
                    if (widget.banner != null) widget.banner!,
                    _PlayersStrip(ctrl: ctrl),
                    Expanded(child: TableBattlefield(ctrl: ctrl)),
                    TableZonesRow(ctrl: ctrl),
                    TableHand(ctrl: ctrl),
                    _BottomBar(ctrl: ctrl, lastLog: lastLog),
                  ]);
                }
                // Ecrã largo: o campo fica com a altura toda; zonas e "Passar
                // turno" passam para uma coluna à direita. Num telemóvel deitado
                // (pouca altura) a mão e a coluna encolhem.
                final handH = (box.maxHeight * 0.24).clamp(84.0, 168.0);
                final panelW = layout.short ? 96.0 : 128.0;
                return Column(children: [
                  if (widget.banner != null) widget.banner!,
                  Expanded(
                    child: Row(children: [
                      Expanded(
                        child: Column(children: [
                          _PlayersStrip(ctrl: ctrl, compact: layout.short),
                          Expanded(child: TableBattlefield(ctrl: ctrl)),
                          TableHand(ctrl: ctrl, height: handH),
                        ]),
                      ),
                      Container(
                        width: panelW,
                        decoration: BoxDecoration(
                          border: Border(left: BorderSide(color: theme.colorScheme.outline)),
                        ),
                        child: SafeArea(
                          left: false,
                          child: Column(children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: TableZonesRow(
                                    ctrl: ctrl, vertical: true, pileWidth: layout.short ? 42 : 72),
                              ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                              child: GestureDetector(
                                onTap: () => showLogSheet(context, ctrl),
                                child: Text(lastLog,
                                    maxLines: layout.short ? 2 : 4,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  minimumSize: Size.fromHeight(layout.short ? 44 : 64),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                ),
                                onPressed: ctrl.mySeats.contains(s.activeSeat) || !ctrl.isNetwork
                                    ? ctrl.passTurn
                                    : null,
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.skip_next),
                                  if (!layout.short) const Text('Passar turno', textAlign: TextAlign.center),
                                ]),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ]);
              }),
              if (_bigResult case final r?) BigResult(value: r.$1, label: r.$2),
            ]),
          );
        },
      ),
    );
  }
}

/// Resultado de um dado, moeda ou sorteio, em grande no meio da mesa.
class BigResult extends StatelessWidget {
  const BigResult({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          builder: (context, t, child) => Transform.scale(scale: t, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.94),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.colorScheme.primary, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 18)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(value,
                  style: theme.textTheme.displayMedium
                      ?.copyWith(fontWeight: FontWeight.w900, color: theme.colorScheme.primary)),
              if (label.isNotEmpty) Text(label, style: theme.textTheme.bodyMedium),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PlayersStrip extends StatelessWidget {
  const _PlayersStrip({required this.ctrl, this.compact = false});
  final GameController ctrl;

  /// Telemóvel deitado: menos altura.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = ctrl.state;
    final seats = s.players.keys.toList()..sort();
    final theme = Theme.of(context);
    return SizedBox(
      height: compact ? 52 : 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 3 : 6),
        children: [
          for (final seat in seats)
            Builder(builder: (context) {
              final p = s.players[seat]!;
              final isActive = s.activeSeat == seat;
              final viewing = ctrl.viewSeat == seat;
              final maxCmd = p.commanderDamage.values.fold(0, (m, v) => v > m ? v : m);
              final poison = p.counters[PlayerCounter.poison] ?? 0;
              final targeted = s.targets.any((t) => t.seat == seat);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => viewing ? showPlayerSheet(context, ctrl, seat) : ctrl.setView(seat),
                  onLongPress: () => showPlayerSheet(context, ctrl, seat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: viewing ? theme.colorScheme.primaryContainer : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: targeted
                            ? targetGlow
                            : isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                        width: isActive || targeted ? 2.5 : 1,
                      ),
                      boxShadow: targeted
                          ? [BoxShadow(color: targetGlow.withOpacity(0.8), blurRadius: 12, spreadRadius: 1)]
                          : null,
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (targeted) ...[
                        const Icon(Icons.gps_fixed, color: targetGlow, size: 20),
                        const SizedBox(width: 6),
                      ],
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            if (s.monarch == seat)
                              const Icon(Icons.workspace_premium, size: 14, color: Colors.amber),
                            if (s.initiative == seat) const Icon(Icons.flag, size: 14, color: Colors.teal),
                            if (ctrl.offline.contains(seat))
                              const Padding(
                                padding: EdgeInsets.only(right: 3),
                                child: Tooltip(
                                    message: 'Sem ligação',
                                    child: Icon(Icons.wifi_off, size: 14, color: EdhColors.bad)),
                              ),
                            Text(p.name,
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(decoration: p.defeated ? TextDecoration.lineThrough : null)),
                          ]),
                          Text('✋${p.handCount}  📚${p.libraryCount}', style: theme.textTheme.labelSmall),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Text('${p.life}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: p.life <= 0 || p.defeated ? EdhColors.bad : null)),
                      if (poison > 0 || maxCmd > 0) ...[
                        const SizedBox(width: 6),
                        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          if (poison > 0)
                            Text('☠$poison', style: const TextStyle(fontSize: 11, color: Colors.green)),
                          if (maxCmd > 0)
                            Text('★$maxCmd',
                                style: TextStyle(
                                    fontSize: 11, color: maxCmd >= 21 ? EdhColors.bad : Colors.amber)),
                        ]),
                      ],
                    ]),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// Campo de batalha de um lugar (o que está em vista, se [seat] for null).
class TableBattlefield extends ConsumerStatefulWidget {
  const TableBattlefield({super.key, required this.ctrl, this.seat, this.rows = 3.3});
  final GameController ctrl;
  final int? seat;

  /// Quantas filas de cartas cabem na altura (menos filas = cartas maiores).
  final double rows;

  @override
  ConsumerState<TableBattlefield> createState() => _BattlefieldState();
}

class _BattlefieldState extends ConsumerState<TableBattlefield> {
  int? _dragId;
  Offset _drag = Offset.zero;

  GameController get ctrl => widget.ctrl;

  @override
  Widget build(BuildContext context) {
    final s = ctrl.state;
    final seat = widget.seat ?? ctrl.viewSeat;
    final cards = s.cards.values.where((c) => c.zone == Zone.battlefield && c.controller == seat).toList();
    // Anexos ficam por baixo da carta a que estão presos.
    cards.sort((a, b) {
      final la = a.attachedTo != null ? 0 : 1, lb = b.attachedTo != null ? 0 : 1;
      return la != lb ? la.compareTo(lb) : a.order.compareTo(b.order);
    });
    final canAct = ctrl.mySeats.contains(seat) || !ctrl.isNetwork;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final bg = settings.backgroundImage;

    return LayoutBuilder(builder: (context, box) {
      // Margem para as cartas nunca ficarem encostadas às extremidades.
      const pad = 10.0;
      // Cabem ~6 cartas na largura e ~3 filas na altura (paisagem).
      final byWidth = box.maxWidth / 6.4;
      final byHeight = box.maxHeight / widget.rows * cardAspect;
      final cw = ((byWidth < byHeight ? byWidth : byHeight) * settings.cardScale).clamp(40.0, 220.0);
      final ch = cw / cardAspect;
      final spanX = (box.maxWidth - cw - 2 * pad).clamp(1.0, double.infinity);
      final spanY = (box.maxHeight - ch - 2 * pad).clamp(1.0, double.infinity);
      Offset topLeft(CardInstance c) {
        var x = pad + c.x * spanX;
        var y = pad + c.y * spanY;
        if (c.attachedTo != null) {
          final siblings = cards.where((o) => o.attachedTo == c.attachedTo).toList();
          final k = siblings.indexOf(c) + 1;
          x -= 10.0 * k;
          y -= 14.0 * k;
        }
        if (_dragId == c.id || (c.attachedTo != null && c.attachedTo == _dragId)) {
          x += _drag.dx;
          y += _drag.dy;
        }
        if (c.tapped) {
          // Rodada, a carta ocupa a altura na horizontal: mantém-na dentro do campo.
          final m = (ch - cw) / 2;
          x = x.clamp(m + pad, (box.maxWidth - cw - m - pad).clamp(m + pad, double.infinity));
          y = y.clamp(pad - m, (box.maxHeight - ch + m - pad).clamp(pad - m, double.infinity));
        }
        return Offset(x, y);
      }

      final centers = {for (final c in cards) c.id: topLeft(c) + Offset(cw / 2, ch / 2)};

      // Arrastar uma carta da mão para o campo: fica onde for largada.
      return DragTarget<PrivateCard>(
        onWillAcceptWithDetails: (d) => canAct && ctrl.zones(seat).hand.any((c) => c.pid == d.data.pid),
        onAcceptWithDetails: (d) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final local = box.globalToLocal(d.offset);
          ctrl.actAs(seat);
          ctrl.playFromHand(d.data,
              x: ((local.dx - pad) / spanX).clamp(0.0, 1.0), y: ((local.dy - pad) / spanY).clamp(0.0, 1.0));
        },
        builder: (context, candidates, _) => Container(
          foregroundDecoration: candidates.isEmpty
              ? null
              : BoxDecoration(border: Border.all(color: theme.colorScheme.primary, width: 3)),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
            image: bg == null
                ? null
                : DecorationImage(
                    image: bg,
                    fit: BoxFit.cover,
                    colorFilter:
                        ColorFilter.mode(Colors.black.withOpacity(settings.backgroundDim), BlendMode.darken),
                  ),
          ),
          child: Stack(clipBehavior: Clip.hardEdge, children: [
            if (cards.isEmpty && bg == null)
              Center(
                child: Text('Campo de ${s.players[seat]?.name ?? ''}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            for (final c in cards)
              Positioned(
                left: topLeft(c).dx,
                top: topLeft(c).dy,
                child: GestureDetector(
                  onTap: () {
                    ctrl.actAs(seat);
                    showCardActions(context, ctrl, c);
                  },
                  onDoubleTap: canAct && settings.doubleTapToTap
                      ? () {
                          ctrl.actAs(seat);
                          ctrl.toggleTap(c);
                        }
                      : null,
                  onPanStart: canAct
                      ? (_) => setState(() {
                            ctrl.actAs(seat);
                            _dragId = c.id;
                            _drag = Offset.zero;
                          })
                      : null,
                  onPanUpdate: canAct ? (d) => setState(() => _drag += d.delta) : null,
                  onPanEnd: canAct
                      ? (_) {
                          final p = topLeft(c);
                          setState(() {
                            _dragId = null;
                            _drag = Offset.zero;
                          });
                          final nx = ((p.dx - pad) / spanX).clamp(0.0, 1.0);
                          final ny = ((p.dy - pad) / spanY).clamp(0.0, 1.0);
                          ctrl.setPosition(c, nx, ny);
                        }
                      : null,
                  child: TableCardView(
                    instance: c,
                    card: ctrl.card(c.oracleId, printId: c.printId),
                    width: cw,
                    highlighted: s.highlight == c.id,
                    targeted: s.targets.any((t) => t.card == c.id),
                    targeting: s.targets.any((t) => t.from == c.id),
                  ),
                ),
              ),
            IgnorePointer(
              child: CustomPaint(
                size: Size(box.maxWidth, box.maxHeight),
                painter: _ArrowPainter(
                  [
                    for (final t in s.targets)
                      if (t.from != null &&
                          t.card != null &&
                          centers[t.from] != null &&
                          centers[t.card] != null)
                        (centers[t.from]!, centers[t.card]!),
                  ],
                  targetGlow,
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.arrows, this.color);
  final List<(Offset, Offset)> arrows;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in arrows) {
      canvas.drawLine(a, b, paint);
      final dir = (b - a);
      final len = dir.distance;
      if (len < 1) continue;
      final u = dir / len;
      final n = Offset(-u.dy, u.dx);
      final head = Path()
        ..moveTo(b.dx, b.dy)
        ..lineTo((b - u * 16 + n * 9).dx, (b - u * 16 + n * 9).dy)
        ..lineTo((b - u * 16 - n * 9).dx, (b - u * 16 - n * 9).dy)
        ..close();
      canvas.drawPath(head, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => true;
}

/// Zona de comando, grimório, cemitério e exílio de um lugar.
class TableZonesRow extends StatelessWidget {
  const TableZonesRow({super.key, required this.ctrl, this.seat, this.vertical = false, this.pileWidth = 44});
  final GameController ctrl;
  final int? seat;

  /// Em coluna (barra lateral da mesa no tablet).
  final bool vertical;
  final double pileWidth;

  @override
  Widget build(BuildContext context) {
    final s = ctrl.state;
    final seat = this.seat ?? ctrl.viewSeat;
    final p = s.players[seat];
    final mine = ctrl.mySeats.contains(seat);
    final command = s.zoneCards(seat, Zone.command).toList();
    final grave = s.zoneCards(seat, Zone.graveyard).toList();
    final exile = s.zoneCards(seat, Zone.exile).toList();
    final w = pileWidth;
    Widget gap() => vertical ? const SizedBox(height: 10) : const SizedBox(width: 8);

    Widget pile(String label, int count, Widget? top, VoidCallback onTap, {VoidCallback? onLong}) =>
        GestureDetector(
          onTap: onTap,
          onLongPress: onLong,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: w,
              child: Stack(alignment: Alignment.center, children: [
                top ??
                    AspectRatio(
                      aspectRatio: cardAspect,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(context).colorScheme.outline),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                  child: Text('$count',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ]),
            ),
            Text(label, style: const TextStyle(fontSize: 10)),
          ]),
        );

    return Padding(
      padding: vertical ? const EdgeInsets.fromLTRB(8, 10, 8, 4) : const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: Flex(
          direction: vertical ? Axis.vertical : Axis.horizontal,
          mainAxisSize: vertical ? MainAxisSize.min : MainAxisSize.max,
          children: [
            for (final c in command)
              Padding(
                padding: vertical ? const EdgeInsets.only(bottom: 8) : const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () {
                    ctrl.actAs(seat);
                    showCardActions(context, ctrl, c);
                  },
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TableCardView(
                        instance: c,
                        card: ctrl.card(c.oracleId, printId: c.printId),
                        width: w,
                        tax: p?.commanderTax(c.id),
                        showTapped: false),
                    const Text('Comando', style: TextStyle(fontSize: 10)),
                  ]),
                ),
              ),
            // Comandante fora da zona de comando: o lugar fica marcado.
            if (command.isEmpty && s.cards.values.any((c) => c.isCommander && c.owner == seat))
              Padding(
                padding: vertical ? const EdgeInsets.only(bottom: 8) : const EdgeInsets.only(right: 6),
                child: pile('Comando', 0, null, () {}),
              ),
            if (vertical) const SizedBox(height: 6) else const Spacer(),
            pile(
              'Grimório',
              p?.libraryCount ?? 0,
              (p?.libraryCount ?? 0) > 0 ? const CardBack() : null,
              mine
                  ? () {
                      ctrl.actAs(seat);
                      ctrl.draw();
                    }
                  : () {},
              onLong: mine
                  ? () {
                      ctrl.actAs(seat);
                      showLibraryMenu(context, ctrl);
                    }
                  : null,
            ),
            gap(),
            pile(
              'Cemitério',
              grave.length,
              grave.isEmpty
                  ? null
                  : TableCardView(
                      instance: grave.last,
                      card: ctrl.card(grave.last.oracleId, printId: grave.last.printId),
                      width: w,
                      showTapped: false),
              () => showZoneList(context, ctrl, seat, Zone.graveyard),
            ),
            gap(),
            pile(
              'Exílio',
              exile.length,
              exile.isEmpty
                  ? null
                  : TableCardView(
                      instance: exile.last,
                      card: ctrl.card(exile.last.oracleId, printId: exile.last.printId),
                      width: w,
                      showTapped: false),
              () => showZoneList(context, ctrl, seat, Zone.exile),
            ),
            if (mine) ...[
              if (!vertical) const SizedBox(width: 4),
              IconButton(
                tooltip: 'Grimório',
                onPressed: () {
                  ctrl.actAs(seat);
                  showLibraryMenu(context, ctrl);
                },
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ]),
    );
  }
}

/// Mão de um lugar. Com [hidden], mostra os versos até alguém tocar em
/// "Ver" (para o modo tablet, em que todos veem o ecrã).
class TableHand extends ConsumerStatefulWidget {
  const TableHand({super.key, required this.ctrl, this.seat, this.hidden = false, this.height = 136});
  final GameController ctrl;
  final int? seat;
  final bool hidden;
  final double height;

  @override
  ConsumerState<TableHand> createState() => _TableHandState();
}

class _TableHandState extends ConsumerState<TableHand> {
  bool _peek = false;
  GameController get ctrl => widget.ctrl;

  @override
  Widget build(BuildContext context) {
    final seat = widget.seat ?? ctrl.viewSeat;
    final theme = Theme.of(context);
    if (!ctrl.mySeats.contains(seat)) {
      return SizedBox(
        height: 36,
        child: Center(
          child: Text(
              'Mão de ${ctrl.state.players[seat]?.name}: ${ctrl.state.players[seat]?.handCount ?? 0} cartas',
              style: theme.textTheme.bodySmall),
        ),
      );
    }
    // Mostra primeiro os feitiços por custo e os terrenos no fim (só a vista).
    final sortHand = ref.watch(settingsProvider).sortHand;
    final hand = [...ctrl.zones(seat).hand];
    if (sortHand) {
      hand.sort((a, b) {
        final ca = ctrl.card(a.oracleId), cb = ctrl.card(b.oracleId, printId: b.printId);
        final la = (ca?.isLand ?? false) ? 1 : 0, lb = (cb?.isLand ?? false) ? 1 : 0;
        if (la != lb) return la.compareTo(lb);
        final mv = (ca?.mv ?? 0).compareTo(cb?.mv ?? 0);
        return mv != 0 ? mv : (ca?.name ?? '').compareTo(cb?.name ?? '');
      });
    }
    final covered = widget.hidden && !_peek;
    // Linha do custo de mana por cima de cada carta, sempre legível.
    final costH = (widget.height * 0.12).clamp(10.0, 17.0);
    final cardW = (widget.height - 10 - costH) * cardAspect;
    final list = hand.isEmpty
        ? Center(child: Text('Mão vazia', style: theme.textTheme.bodySmall))
        : ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: hand.length,
            separatorBuilder: (_, __) => const SizedBox(width: 4),
            itemBuilder: (context, i) {
              final pc = hand[i];
              final card = ctrl.card(pc.oracleId, printId: pc.printId);
              final item = GestureDetector(
                onTap: covered
                    ? () => setState(() => _peek = true)
                    : () {
                        ctrl.actAs(seat);
                        showHandCardActions(context, ctrl, pc);
                      },
                onDoubleTap: covered
                    ? null
                    : () {
                        ctrl.actAs(seat);
                        ctrl.playFromHand(pc);
                      },
                child: SizedBox(
                  width: cardW,
                  child: Column(children: [
                    SizedBox(
                      height: costH,
                      child: Builder(builder: (_) {
                        if (covered || card == null) return const SizedBox.shrink();
                        final cost = card.faces.isNotEmpty && card.faces.first.manaCost.isNotEmpty
                            ? card.faces.first.manaCost
                            : card.manaCost;
                        // Sem custo (terrenos): nada. Um FittedBox à volta de algo
                        // sem tamanho dá uma escala inválida e apaga a lista toda.
                        if (cost.isEmpty) return const SizedBox.shrink();
                        return FittedBox(child: ManaCost(cost, size: costH - 2));
                      }),
                    ),
                    const SizedBox(height: 2),
                    covered || card == null ? const CardBack() : CardImage(card, radius: 5),
                  ]),
                ),
              );
              if (covered) return item;
              // Tocar e manter, e arrastar para o campo.
              return LongPressDraggable<PrivateCard>(
                data: pc,
                delay: const Duration(milliseconds: 250),
                onDragStarted: () => ctrl.actAs(seat),
                feedback: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: cardW * 1.15,
                    child: card == null ? const CardBack() : CardImage(card, radius: 6),
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.3, child: item),
                child: item,
              );
            },
          );
    return SizedBox(
      height: widget.height,
      child: !widget.hidden
          ? list
          : Row(children: [
              Expanded(child: list),
              IconButton(
                tooltip: _peek ? 'Esconder a mão' : 'Ver a mão',
                onPressed: () => setState(() => _peek = !_peek),
                icon: Icon(_peek ? Icons.visibility_off : Icons.visibility),
              ),
            ]),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.ctrl, required this.lastLog});
  final GameController ctrl;
  final String lastLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myTurn = ctrl.mySeats.contains(ctrl.state.activeSeat);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 6),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.colorScheme.outline))),
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => showLogSheet(context, ctrl),
              child: Text(lastLog,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: myTurn || !ctrl.isNetwork ? ctrl.passTurn : null,
            icon: const Icon(Icons.skip_next),
            label: const Text('Passar turno'),
          ),
        ]),
      ),
    );
  }
}
