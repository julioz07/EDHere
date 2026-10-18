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

/// A mesa: campo do jogador em vista, zonas, mão e barra de turno.
/// Serve o playtest e o jogo em rede.
class TableScreen extends ConsumerStatefulWidget {
  const TableScreen({super.key, required this.ctrl, this.title, this.onLeave, this.banner});

  final GameController ctrl;
  final String? title;

  /// Chamado ao sair (fecha a sala, por exemplo).
  final Future<void> Function()? onLeave;

  /// Aviso no topo (ligação perdida, etc.).
  final Widget? banner;

  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<TableScreen> {
  GameController get ctrl => widget.ctrl;
  Reveal? _shownReveal;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    if (settings.keepScreenOn) WakelockPlus.enable();
    ctrl.autoDraw = settings.autoDraw;
    ctrl.addListener(_onChange);
  }

  @override
  void dispose() {
    ctrl.removeListener(_onChange);
    WakelockPlus.disable();
    super.dispose();
  }

  void _onChange() {
    final r = ctrl.state.revealed;
    if (r != null && !identical(r, _shownReveal)) {
      _shownReveal = r;
      final forMe = r.to == null || ctrl.mySeats.contains(r.to);
      if (forMe && !(ctrl.isNetwork && ctrl.mySeats.contains(r.seat))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showRevealDialog(context, ctrl, r);
        });
      }
    }
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
              child: Text(p.name, style: const TextStyle(fontSize: 16)),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, -1),
            child: const Text('Sem vencedor', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
    if (winner == null || !mounted) return;
    ref.read(deckStoreProvider).saveGame(ctrl.record(winnerSeat: winner < 0 ? null : winner));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Jogo guardado no histórico.')),
    );
    if (!ctrl.isNetwork) Navigator.of(context).pop();
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
          child: Wrap(children: [
            SwitchListTile(
              title: const Text('Compra automática no início do turno'),
              value: ctrl.autoDraw,
              onChanged: (v) => set(() => ctrl.autoDraw = v),
            ),
            ListTile(
              leading: const Icon(Icons.emoji_events_outlined),
              title: const Text('Terminar jogo e guardar no histórico'),
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
                  ctrl.send(ctrl.table.revealHidden(ctrl.actor, Zone.hand,
                      [for (final c in hand) c.pid], what: 'a mão'));
                }
              }),
            ),
          ]),
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
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 48,
              titleSpacing: 0,
              title: Text(
                'T${s.turn} · ${active?.name ?? ''}',
                style: theme.textTheme.titleMedium,
              ),
              actions: [
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
            body: Column(children: [
              if (widget.banner != null) widget.banner!,
              _PlayersStrip(ctrl: ctrl),
              Expanded(child: TableBattlefield(ctrl: ctrl)),
              TableZonesRow(ctrl: ctrl),
              TableHand(ctrl: ctrl),
              _BottomBar(ctrl: ctrl, lastLog: s.log.isEmpty ? '' : ctrl.logText(s.log.last)),
            ]),
          );
        },
      ),
    );
  }
}

class _PlayersStrip extends StatelessWidget {
  const _PlayersStrip({required this.ctrl});
  final GameController ctrl;

  @override
  Widget build(BuildContext context) {
    final s = ctrl.state;
    final seats = s.players.keys.toList()..sort();
    final theme = Theme.of(context);
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                            if (s.monarch == seat) const Icon(Icons.workspace_premium, size: 14, color: Colors.amber),
                            if (s.initiative == seat) const Icon(Icons.flag, size: 14, color: Colors.teal),
                            Text(p.name,
                                style: theme.textTheme.labelMedium?.copyWith(
                                    decoration: p.defeated ? TextDecoration.lineThrough : null)),
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
                          if (poison > 0) Text('☠$poison', style: const TextStyle(fontSize: 11, color: Colors.green)),
                          if (maxCmd > 0)
                            Text('★$maxCmd',
                                style: TextStyle(fontSize: 11, color: maxCmd >= 21 ? EdhColors.bad : Colors.amber)),
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
  const TableBattlefield({super.key, required this.ctrl, this.seat});
  final GameController ctrl;
  final int? seat;

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
    final cards = s.cards.values
        .where((c) => c.zone == Zone.battlefield && c.controller == seat)
        .toList();
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
      final cw = (box.maxWidth / 6.4 * settings.cardScale).clamp(40.0, 200.0);
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

      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
          image: bg == null
              ? null
              : DecorationImage(
                  image: bg,
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(settings.backgroundDim), BlendMode.darken),
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
                    if (t.from != null && t.card != null && centers[t.from] != null && centers[t.card] != null)
                      (centers[t.from]!, centers[t.card]!),
                ],
                targetGlow,
              ),
            ),
          ),
        ]),
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
  const TableZonesRow({super.key, required this.ctrl, this.seat});
  final GameController ctrl;
  final int? seat;

  @override
  Widget build(BuildContext context) {
    final s = ctrl.state;
    final seat = this.seat ?? ctrl.viewSeat;
    final p = s.players[seat];
    final mine = ctrl.mySeats.contains(seat);
    final command = s.zoneCards(seat, Zone.command).toList();
    final grave = s.zoneCards(seat, Zone.graveyard).toList();
    final exile = s.zoneCards(seat, Zone.exile).toList();
    const w = 44.0;

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
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: Row(children: [
        for (final c in command)
          Padding(
            padding: const EdgeInsets.only(right: 6),
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
        const Spacer(),
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
        const SizedBox(width: 8),
        pile(
          'Cemitério',
          grave.length,
          grave.isEmpty
              ? null
              : TableCardView(instance: grave.last, card: ctrl.card(grave.last.oracleId, printId: grave.last.printId), width: w, showTapped: false),
          () => showZoneList(context, ctrl, seat, Zone.graveyard),
        ),
        const SizedBox(width: 8),
        pile(
          'Exílio',
          exile.length,
          exile.isEmpty
              ? null
              : TableCardView(instance: exile.last, card: ctrl.card(exile.last.oracleId, printId: exile.last.printId), width: w, showTapped: false),
          () => showZoneList(context, ctrl, seat, Zone.exile),
        ),
        if (mine) ...[
          const SizedBox(width: 4),
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
          child: Text('Mão de ${ctrl.state.players[seat]?.name}: ${ctrl.state.players[seat]?.handCount ?? 0} cartas',
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
              return GestureDetector(
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
