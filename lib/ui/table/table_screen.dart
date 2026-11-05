import 'package:flutter/material.dart' hide Table, Intent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesa_core/mesa_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/theme.dart';
import '../../data/providers.dart';
import 'package:card_db/card_db.dart' show ImageRef;
import '../../data/settings.dart';
import '../../game/game_controller.dart';
import '../widgets/card_art.dart';
import '../widgets/card_view.dart';
import '../widgets/life_delta.dart';
import '../widgets/mana.dart';
import '../widgets/responsive.dart';
import 'hand_overview.dart';
import 'life_screen.dart';
import 'table_tour.dart';
import 'table_card.dart';
import 'table_turns.dart';
import 'table_sheets.dart';
import '../../l10n/l10n.dart';

List<(String, String)> get _phases => [
      ('upkeep', tr('Manutenção')),
      ('draw', tr('Compra')),
      ('main1', tr('Principal 1')),
      ('combat', tr('Combate')),
      ('main2', tr('Principal 2')),
      ('end', tr('Final')),
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
  const TableScreen(
      {super.key,
      required this.ctrl,
      this.title,
      this.onLeave,
      this.banner,
      this.onNewGame,
      this.matchStatus,
      this.afterGame,
      this.confirmLeave,
      this.hostsRoom = false,
      this.tour = true});

  final GameController ctrl;
  final String? title;

  /// Chamado ao sair (fecha a sala, por exemplo).
  final Future<void> Function()? onLeave;

  /// Aviso no topo (ligação perdida, etc.).
  final Widget? banner;

  /// Só o anfitrião: volta todos ao lobby para outra partida.
  final VoidCallback? onNewGame;

  /// Encontros 1 contra 1: o jogo e o resultado ("Jogo 2 · 1–0"), no
  /// cabeçalho e no fim de cada jogo.
  final String Function()? matchStatus;

  /// Encontros 1 contra 1: os botões do fim do jogo (sideboard e jogo
  /// seguinte, ou voltar à sala quando o encontro acabou); o último é o
  /// principal. Trocam o "Nova partida".
  final List<({String label, VoidCallback onPressed})> Function()? afterGame;

  /// Troca a pergunta "Sair da mesa?" (o playtest pergunta se grava).
  final Future<bool> Function(BuildContext context)? confirmLeave;

  /// Este dispositivo é o anfitrião: se sair, a sala fecha para todos.
  final bool hostsRoom;

  /// Mostrar a visita à mesa no primeiro jogo (o tutorial tem a sua).
  final bool tour;

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
    if (!ctrl.scripted) ctrl.autoDraw = settings.autoDraw;
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
    _fetchTokenImages();
  }

  /// Avisos que o jogador fechou ("Ignorar"); voltam se o valor descer e
  /// voltar a subir.
  final Set<String> _dismissed = {};

  /// Como nos contadores de vida: aos 0 de vida, 10 de veneno ou 21 de dano de um
  /// comandante, pergunta se o jogador foi derrotado. Só nos meus lugares, para
  /// não aparecer em todos os telemóveis. Fica à vista até se responder.
  String? _lethalReason(int seat) {
    final s = ctrl.state;
    final p = s.players[seat];
    if (p == null || p.defeated || !s.started || s.over || ctrl.scripted) return null;
    final poison = p.counters[PlayerCounter.poison] ?? 0;
    final cmd = p.commanderDamage.values.fold(0, (a, b) => a > b ? a : b);
    return p.life <= 0
        ? tr('{v} está com {n} de vida.', {'v': p.name, 'n': p.life})
        : poison >= 10
            ? tr('{v} tem {n} marcadores de veneno.', {'v': p.name, 'n': poison})
            : cmd >= 21
                ? tr('{v} levou {n} de dano de um só comandante.', {'v': p.name, 'n': cmd})
                : null;
  }

  /// Avisos no topo da mesa: derrota possível, só resta um jogador, fui eliminado.
  List<Widget> _notices(ThemeData theme) {
    final s = ctrl.state;
    final out = <Widget>[];
    // Num telemóvel pequeno o MaterialBanner (botões por baixo) tapava meio campo:
    // aí o aviso é uma faixa estreita, com texto pequeno e botões compactos.
    final small = MediaQuery.sizeOf(context).height < 700;
    Widget notice(IconData icon, String text, List<Widget> actions, {Color? color}) => small
        ? Material(
            color: color ?? theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Theme(
                // os botões do tema ocupam a largura toda; aqui ficam lado a lado
                data: theme.copyWith(
                  visualDensity: VisualDensity.compact,
                  filledButtonTheme: FilledButtonThemeData(
                      style: theme.filledButtonTheme.style
                          ?.copyWith(minimumSize: const WidgetStatePropertyAll(Size(64, 36)))),
                ),
                child: Row(children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(text, style: theme.textTheme.bodySmall, maxLines: 4, overflow: TextOverflow.ellipsis),
                      OverflowBar(alignment: MainAxisAlignment.end, spacing: 4, children: actions),
                    ]),
                  ),
                ]),
              ),
            ),
          )
        : MaterialBanner(
            backgroundColor: color ?? theme.colorScheme.secondaryContainer,
            leading: Icon(icon),
            content: Text(text),
            actions: actions,
          );
    for (final seat in ctrl.mySeats) {
      final reason = _lethalReason(seat);
      final key = 'lethal:$seat';
      if (reason == null) {
        _dismissed.remove(key);
        continue;
      }
      if (_dismissed.contains(key)) continue;
      out.add(notice(Icons.heart_broken_outlined, reason, [
        TextButton(onPressed: () => setState(() => _dismissed.add(key)), child: Text(tr('Ignorar'))),
        FilledButton(
          onPressed: () => ctrl.send(Intent(Ev.defeated, {'seat': seat, 'value': true})),
          child: Text(tr('Marcar derrota')),
        ),
      ]));
    }
    if (!s.started || s.over || ctrl.scripted) return out;
    final deciding = _deciding();
    if (deciding.isNotEmpty && ctrl.mySeats.every((m) => s.players[m]?.kept ?? true)) {
      out.add(notice(
        Icons.hourglass_top_rounded,
        deciding.length == 1
            ? tr('{v} ainda está a decidir a mão inicial.', {'v': deciding.single})
            : tr('Ainda a decidir a mão inicial: {v}.', {'v': deciding.join(', ')}),
        const [],
      ));
    }
    final alive = s.players.values.where((p) => !p.defeated).toList();
    if (s.players.length > 1 && alive.length == 1 && !_dismissed.contains('last')) {
      final w = alive.single;
      out.add(notice(
        Icons.emoji_events_rounded,
        tr('Só resta {v} em jogo.', {'v': w.name}),
        [
          TextButton(onPressed: () => setState(() => _dismissed.add('last')), child: Text(tr('Continuar'))),
          FilledButton(onPressed: () => ctrl.gameOver(w.seat), child: Text(tr('{v} ganhou', {'v': w.name}))),
        ],
        color: GameColors.gold.withOpacity(0.35),
      ));
    } else if (ctrl.isNetwork &&
        alive.length > 1 &&
        ctrl.mySeats.isNotEmpty &&
        ctrl.mySeats.every((m) => s.players[m]?.defeated ?? false) &&
        !_dismissed.contains('out')) {
      // O anfitrião não pode sair: a sala está no telemóvel dele.
      out.add(notice(
        Icons.visibility_outlined,
        widget.hostsRoom
            ? tr('Perdeste. És o anfitrião: o jogo dos outros continua no teu telemóvel, por isso fica na mesa.')
            : tr('Perdeste. Podes ficar a ver o jogo ou sair.'),
        [
          TextButton(onPressed: () => setState(() => _dismissed.add('out')), child: Text(tr('Ver o jogo'))),
          if (!widget.hostsRoom)
            FilledButton(
              onPressed: () async {
                await widget.onLeave?.call();
                if (mounted) Navigator.of(context).pop();
              },
              child: Text(tr('Sair')),
            ),
        ],
      ));
    }
    return out;
  }

  /// Os tokens não vêm com as imagens do deck: vão buscá-las quando aparecem.
  final Set<String> _tokenImagesAsked = {};

  void _fetchTokenImages() {
    final images = ref.read(imagesProvider);
    final refs = <ImageRef>[];
    for (final c in ctrl.state.cards.values) {
      if (!c.isToken || c.oracleId == null) continue;
      final card = ctrl.card(c.oracleId, printId: c.printId);
      if (card == null) continue;
      for (final r in ImageRef.allOf(card)) {
        if (_tokenImagesAsked.add(r.key) && !images.has('small', r.key)) refs.add(r);
      }
    }
    if (refs.isNotEmpty) images.ensureRefs(refs, sizes: const ['small']).ignore();
  }

  /// Passar o turno com mais de 7 cartas na mão: lembra o descarte.
  Future<void> _passTurn() async {
    final seat = ctrl.actor;
    final hand = ctrl.zones(seat).hand.length;
    if (!ctrl.scripted && ctrl.mySeats.contains(seat) && hand > 7) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.back_hand_outlined),
          title: Text(tr('{n} cartas na mão', {'n': hand})),
          content: Text(hand - 7 == 1
              ? tr('No fim do turno a mão tem no máximo 7 cartas: descarta 1.')
              : tr('No fim do turno a mão tem no máximo 7 cartas: descarta {n}.', {'n': hand - 7})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Passar na mesma'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Descartar primeiro'))),
          ],
        ),
      );
      if (go != true) return;
    }
    ctrl.passTurn();
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
    if (!s.started || s.over || s.turn > 1 || ctrl.scripted) return;
    for (final seat in ctrl.mySeats) {
      // ao voltar a um jogo em rede, quem já ficou com a mão não volta a decidir
      if (_mulliganAsked.contains(seat) || ctrl.openingDone.contains(seat) || (s.players[seat]?.kept ?? false)) {
        continue;
      }
      final hand = ctrl.zones(seat).hand;
      if (hand.length < 7 || (ctrl.mulligans[seat] ?? 0) > 0) continue;
      _mulliganAsked.add(seat);
      ctrl.openingDone.add(seat);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _askMulligan(seat);
      });
      return; // uma de cada vez (no hot-seat, a seguinte vem depois)
    }
  }

  /// Em rede, no primeiro turno: quem ainda não ficou com a mão inicial.
  /// (Jogos de versões antigas não mandam o "fiquei": passado o primeiro
  /// turno o aviso desaparece de qualquer forma.)
  List<String> _deciding() {
    final s = ctrl.state;
    if (!ctrl.isNetwork || ctrl.round > 1 || s.players.length < 2) return const [];
    return [
      for (final p in s.players.values)
        if (!p.kept && !p.defeated) p.name
    ];
  }

  /// O campo em vista; com [all] (tablet), por cima, os campos dos outros
  /// em tiras: vê-se a mesa toda sem trocar de vista. Tocar no nome de uma
  /// tira troca-a com o campo grande.
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
            final theme = Theme.of(ctx);
            final hand = ctrl.zones(seat).hand;
            final next = free ? count : count + 1;
            // Um momento só da mesa: ecrã inteiro, escuro, as cartas grandes.
            return Dialog.fullscreen(
              backgroundColor: const Color(0xFF0E1116),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(children: [
                    Text(
                      count == 0
                          ? tr('Mulligan').toUpperCase()
                          : tr('Mulligan {count}', {'count': count}).toUpperCase(),
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: theme.colorScheme.primary, letterSpacing: 2, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (ctrl.mySeats.length > 1 ? tr('Mão inicial de {name}', {'name': name}) : tr('A tua mão inicial'))
                          .toUpperCase(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                    if (ctrl.isNetwork && ctrl.state.players.length > 1) ...[
                      const SizedBox(height: 10),
                      Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                        for (final (i, p)
                            in (ctrl.state.players.values.toList()..sort((a, b) => a.seat.compareTo(b.seat))).indexed)
                          if (p.seat != seat) _MulliganChip(player: p, color: GameColors.player(i)),
                      ]),
                    ],
                    const SizedBox(height: 16),
                    Expanded(
                      child: LayoutBuilder(builder: (context, box) {
                        // As colunas que deixam as cartas maiores sem passar da altura.
                        var best = (cols: hand.length, w: 0.0);
                        for (var cols = 1; cols <= hand.length; cols++) {
                          final rows = (hand.length / cols).ceil();
                          final byW = (box.maxWidth - (cols - 1) * 8) / cols;
                          final byH = ((box.maxHeight - (rows - 1) * 8) / rows) * cardAspect;
                          final w = byW < byH ? byW : byH;
                          if (w > best.w) best = (cols: cols, w: w);
                        }
                        return Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final pc in hand)
                                SizedBox(
                                  width: best.w,
                                  child: switch (ctrl.card(pc.oracleId, printId: pc.printId)) {
                                    final c? => CardImage(c, preferNormal: true),
                                    null => const CardBack(),
                                  },
                                ),
                            ],
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white38),
                              minimumSize: const Size.fromHeight(52)),
                          onPressed: hand.length <= 1 ? null : () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(next == 0 ? tr('Mulligan (grátis)') : tr('Mulligan')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: const Icon(Icons.check_rounded),
                          label: Text(tr('Manter')),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      toBottom > 0
                          ? tr('Ao manter, pões {toBottom} no fundo do grimório.', {'toBottom': toBottom})
                          : next == 0
                              ? tr('O primeiro mulligan é grátis: voltas a comprar 7 e não pões nenhuma no fundo.')
                              : tr('Com mulligan, baralhas a mão e compras 7 de novo; ao manter, pões {n} no fundo.',
                                  {'n': next}),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      );
      if (!mounted || keep == null) return;
      ctrl.actAs(seat);
      if (keep) {
        if (toBottom > 0) await showBottomPicker(context, ctrl, toBottom);
        // os outros ficam a saber que já decidi
        ctrl.actAs(seat);
        ctrl.keepHand();
        break;
      }
      ctrl.mulligan();
      // Em rede a nova mão chega pelo anfitrião: espera um instante.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    _maybeAskMulligan();
  }

  Future<bool> _confirmLeave() async {
    if (widget.confirmLeave case final ask?) return ask(context);
    if (!ref.read(settingsProvider).confirmLeave) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sair da mesa?')),
        content: Text(ctrl.isNetwork ? tr('Podes voltar a entrar depois.') : tr('O playtest termina.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Ficar'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sair'))),
        ],
      ),
    );
    return ok == true;
  }

  /// Escolher o vencedor; o fim do jogo chega a todos os dispositivos.
  Future<void> _finishGame() async {
    final players = ctrl.state.players.values.toList()
      ..sort((a, b) => (a.defeated ? 1 : 0).compareTo(b.defeated ? 1 : 0));
    final winner = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Quem ganhou?')),
        children: [
          for (final p in players)
            SimpleDialogOption(
              onPressed: p.defeated ? null : () => Navigator.pop(ctx, p.seat),
              child: Text(
                  [
                    ctrl.mySeats.contains(p.seat) && ctrl.isNetwork ? tr('{v} (tu)', {'v': p.name}) : p.name,
                    if (p.defeated) tr('perdeu'),
                  ].join(' · '),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: p.defeated ? null : FontWeight.w600,
                      color: p.defeated ? Theme.of(ctx).disabledColor : null)),
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

  /// Cada dispositivo guarda a partida no seu histórico e mostra o resultado.
  Future<void> _onGameOver() async {
    if (!mounted) return;
    final s = ctrl.state;
    ref.read(deckStoreProvider).saveGame(ctrl.record(winnerSeat: s.winner));
    final winner = s.winner == null ? null : s.players[s.winner];
    final iWon = s.winner != null && ctrl.mySeats.contains(s.winner) && ctrl.mySeats.length == 1;
    final next = widget.afterGame?.call();
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.emoji_events_rounded, color: winner == null ? null : GameColors.gold, size: 40),
        title: Text(winner == null
            ? tr('Jogo terminado')
            : iWon
                ? tr('Ganhaste!')
                : tr('{v} ganhou', {'v': winner.name})),
        content: Text(widget.matchStatus != null
            ? tr('{m} · guardado no histórico.', {'m': widget.matchStatus!()})
            : tr('Ronda {round} · guardado no histórico.', {'round': ctrl.round})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'view'), child: Text(tr('Ver a mesa'))),
          if (next != null && next.isNotEmpty) ...[
            for (final (i, a) in next.indexed)
              if (i < next.length - 1)
                TextButton(onPressed: () => Navigator.pop(ctx, 'next$i'), child: Text(a.label))
              else
                FilledButton(onPressed: () => Navigator.pop(ctx, 'next$i'), child: Text(a.label)),
          ] else if (!ctrl.isNetwork)
            FilledButton(onPressed: () => Navigator.pop(ctx, 'close'), child: Text(tr('Fechar')))
          else if (widget.onNewGame != null)
            FilledButton(onPressed: () => Navigator.pop(ctx, 'again'), child: Text(tr('Nova partida'))),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'close':
        Navigator.of(context).pop();
      case 'again':
        widget.onNewGame?.call();
      case final String a when a.startsWith('next'):
        next?[int.parse(a.substring(4))].onPressed();
    }
  }

  /// "Cada oponente perde X" (ou ganha) numa só ação e numa linha do registo.
  Future<void> _lifeEachOpponent() async {
    final me = ctrl.actor;
    final foes = [
      for (final p in ctrl.state.players.values)
        if (p.seat != me && !p.defeated) p.seat
    ];
    if (foes.isEmpty) return;
    var n = 1;
    var lose = true;
    final delta = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Vida de cada oponente')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(tr('Perde'))),
                ButtonSegment(value: false, label: Text(tr('Ganha'))),
              ],
              selected: {lose},
              onSelectionChanged: (v) => set(() => lose = v.first),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton.filledTonal(onPressed: n > 1 ? () => set(() => n--) : null, icon: const Icon(Icons.remove)),
              SizedBox(
                width: 64,
                child: Text('$n', textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.headlineMedium),
              ),
              IconButton.filledTonal(onPressed: () => set(() => n++), icon: const Icon(Icons.add)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, lose ? -n : n), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (delta == null) return;
    ctrl.send(Intent(Ev.lifeEach, {'seats': foes, 'delta': delta}));
  }

  // A visita à mesa: as partes do ecrã de que fala.
  final _kPlayers = GlobalKey(),
      _kField = GlobalKey(),
      _kZones = GlobalKey(),
      _kHand = GlobalKey(),
      _kPass = GlobalKey();
  bool _touring = false;

  /// Primeiro jogo: depois da mão inicial, mostra a visita (uma vez).
  void _maybeTour() {
    if (_touring || !widget.tour || ref.read(settingsProvider).tableTourDone) return;
    if (!ctrl.mySeats.every(ctrl.openingDone.contains)) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) setState(() => _touring = true);
    });
  }

  List<TourStep> get _tourSteps => [
        TourStep(
            _kPlayers,
            tr('Os jogadores'),
            // o coração só está na barra quando há largura (senão vai para o menu)
            MediaQuery.sizeOf(context).width < 480
                ? tr(
                    'A vida e as cartas na mão de cada um. Toca num jogador para ver o campo dele. As vidas em grande estão no menu ⋮.')
                : tr(
                    'A vida e as cartas na mão de cada um. Toca num jogador para ver o campo dele. O coração em cima abre as vidas em grande.')),
        TourStep(_kField, tr('O campo'),
            tr('Toca numa carta para ver o que podes fazer com ela. Toca duas vezes para a virar (tap). Arrasta para a mudar de sítio.')),
        TourStep(_kZones, tr('As zonas'),
            tr('Grimório, cemitério, exílio e comando. Toca no grimório para comprar, baralhar, fazer scry e mais.')),
        TourStep(_kHand, tr('A tua mão'),
            tr('Toca numa carta para a jogar, ou arrasta-a para o campo. O botão ao lado mostra a mão toda, por tipo.')),
        TourStep(_kPass, tr('Passar o turno'),
            tr('Quando acabares, passa o turno aqui. Enganaste-te? A seta em cima desfaz o teu último passo.')),
      ];

  /// Desfaz e diz o que desfez (o registo pode juntar vários passos numa linha).
  void _undo() {
    final what = ctrl.undoLabel;
    ctrl.undo();
    if (what == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(tr('Desfeito: {v}', {'v': what})),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
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
                ListTile(
                  leading: const Icon(Icons.favorite_border_rounded),
                  title: Text(tr('Vidas')),
                  subtitle: Text(tr('Jogo em curso há {n} min', {'n': ctrl.elapsed.inMinutes})),
                  onTap: () => run(() => pushTablePage<void>(context, LifeScreen(ctrl: ctrl))),
                ),
                SwitchListTile(
                  title: Text(tr('Compra automática no início do turno')),
                  value: ctrl.autoDraw,
                  onChanged: (v) => set(() => ctrl.autoDraw = v),
                ),
                ListTile(
                  leading: const Icon(Icons.bolt),
                  title: Text(tr('Storm neste turno: {storm}', {'storm': ctrl.state.storm})),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        onPressed: ctrl.state.storm > 0 ? () => ctrl.storm(-1) : null,
                        icon: const Icon(Icons.remove_circle_outline)),
                    IconButton(onPressed: () => ctrl.storm(1), icon: const Icon(Icons.add_circle_outline)),
                  ]),
                ),
                ListTile(
                  leading: Icon(ctrl.state.dayNight == 'night' ? Icons.nightlight_round : Icons.wb_sunny_outlined),
                  title: Text(tr('Dia / noite')),
                  trailing: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      const ButtonSegment(value: '-', label: Text('—')),
                      ButtonSegment(value: 'day', label: Text(tr('Dia'))),
                      ButtonSegment(value: 'night', label: Text(tr('Noite'))),
                    ],
                    selected: {ctrl.state.dayNight ?? '-'},
                    onSelectionChanged: (v) => ctrl.dayNight(v.first == '-' ? null : v.first),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.emoji_events_outlined),
                  title: Text(tr('Terminar jogo')),
                  subtitle: Text(tr('Escolhe o vencedor; fica no histórico de todos')),
                  onTap: () => run(_finishGame),
                ),
                if (ctrl.state.players.length > 1)
                  ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: Text(tr('Vida de cada oponente…')),
                    subtitle: Text(tr('Ex.: cada oponente perde 2')),
                    onTap: () => run(_lifeEachOpponent),
                  ),
                ListTile(
                  leading: const Icon(Icons.toll_outlined),
                  title: Text(tr('Criar token')),
                  onTap: () => run(() => showTokenSheet(context, ctrl)),
                ),
                ListTile(
                  leading: const Icon(Icons.gps_fixed, color: targetGlow),
                  title: Text(tr('Apontar para… (carta ou jogador)')),
                  onTap: () => run(() => showTargetPicker(context, ctrl)),
                ),
                ListTile(
                  leading: const Icon(Icons.undo),
                  title: Text(tr('Desvirar tudo')),
                  onTap: () => run(() => ctrl.send(Intent(Ev.untapAll, {'seat': ctrl.actor}))),
                ),
                ListTile(
                  leading: const Icon(Icons.casino_outlined),
                  title: Text(tr('Lançar d6')),
                  onTap: () => run(() => ctrl.rollDie(6)),
                ),
                ListTile(
                  leading: const Icon(Icons.casino),
                  title: Text(tr('Lançar d20')),
                  onTap: () => run(() => ctrl.rollDie(20)),
                ),
                ListTile(
                  leading: const Icon(Icons.toll),
                  title: Text(tr('Lançar moeda')),
                  onTap: () => run(ctrl.flipCoin),
                ),
                ListTile(
                  leading: const Icon(Icons.shuffle_on_outlined),
                  title: Text(tr('Escolher jogador ao acaso')),
                  onTap: () => run(ctrl.randomPlayer),
                ),
                ListTile(
                  leading: const Icon(Icons.clear_all),
                  title: Text(tr('Limpar os meus alvos e o destaque')),
                  onTap: () => run(() {
                    ctrl.send(const Intent(Ev.arrow, {}));
                    ctrl.highlight(null);
                  }),
                ),
                ListTile(
                  leading: const Icon(Icons.visibility),
                  title: Text(tr('Revelar a minha mão a todos')),
                  onTap: () => run(() {
                    final hand = ctrl.zones(ctrl.actor).hand;
                    if (hand.isNotEmpty) {
                      ctrl.send(
                          ctrl.table.revealHidden(ctrl.actor, Zone.hand, [for (final c in hand) c.pid], what: 'a mão'));
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
          final narrowBar = MediaQuery.sizeOf(context).width < 480;
          // A mesa é densa: com a letra do sistema muito grande, os cartões dos
          // jogadores e as zonas deixavam de caber. Os menus e diálogos (fora
          // deste MediaQuery) continuam com o tamanho escolhido.
          _maybeTour();
          return MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.15,
              child: Stack(children: [
                Scaffold(
                  appBar: AppBar(
                    toolbarHeight: layout.short ? 44 : 48,
                    titleSpacing: 0,
                    title: Text(
                      // Em Commander conta-se por rondas ("o meu 3.º turno"), não pelo
                      // turno de toda a gente.
                      s.over
                          ? tr('Jogo terminado')
                          : widget.matchStatus != null
                              ? tr('{m} · {v}',
                                  {'m': widget.matchStatus!(), 'v': myTurn ? tr('o teu turno') : active?.name ?? ''})
                              : tr('Ronda {round} · {v}',
                                  {'round': ctrl.round, 'v': myTurn ? tr('o teu turno') : active?.name ?? ''}),
                      // Num telemóvel estreito o botão da fase tira espaço: duas linhas.
                      style: narrowBar ? theme.textTheme.titleSmall : theme.textTheme.titleMedium,
                      maxLines: narrowBar ? 2 : 1,
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
                              color: s.dayNight == 'night' ? Colors.indigo.shade200 : GameColors.gold),
                        ),
                      ActionChip(
                        label: Text(phaseLabel, style: const TextStyle(fontSize: 12)),
                        onPressed: () {
                          final i = _phases.indexWhere((p) => p.$1 == s.phase);
                          ctrl.send(Intent(Ev.setPhase, {'phase': _phases[(i + 1) % _phases.length].$1}));
                        },
                      ),
                      if (!narrowBar)
                        IconButton(
                          tooltip: tr('Vidas'),
                          onPressed: () => pushTablePage<void>(context, LifeScreen(ctrl: ctrl)),
                          icon: const Icon(Icons.favorite_border_rounded),
                        ),
                      IconButton(
                        // diz o que vai desfazer (manter premido mostra)
                        tooltip: ctrl.undoLabel == null ? tr('Desfazer') : tr('Desfazer: {v}', {'v': ctrl.undoLabel}),
                        onPressed: ctrl.canUndo ? _undo : null,
                        icon: const Icon(Icons.undo),
                      ),
                      IconButton(
                        tooltip: tr('Registo'),
                        onPressed: () => showLogSheet(context, ctrl),
                        icon: const Icon(Icons.receipt_long),
                      ),
                      IconButton(tooltip: tr('Mais'), onPressed: _menu, icon: const Icon(Icons.more_vert)),
                    ],
                  ),
                  body: Stack(children: [
                    LayoutBuilder(builder: (context, box) {
                      final lastLog = s.log.isEmpty ? '' : ctrl.logText(s.log.last);
                      if (!layout.wide) {
                        // Em telemóveis pequenos a mão, as zonas e os jogadores
                        // encolhem, para o campo não ficar reduzido a uma tira.
                        final tight = box.maxHeight < 600;
                        // tablet ao alto: os jogadores em cartões grandes
                        final all = box.maxWidth >= 600 && box.maxHeight >= 900;
                        return Column(children: [
                          if (widget.banner != null) widget.banner!,
                          ..._notices(theme),
                          KeyedSubtree(key: _kPlayers, child: _PlayersStrip(ctrl: ctrl, compact: tight, big: all)),
                          Expanded(child: KeyedSubtree(key: _kField, child: TableBattlefield(ctrl: ctrl))),
                          KeyedSubtree(key: _kZones, child: TableZonesRow(ctrl: ctrl, pileWidth: tight ? 34 : 44)),
                          KeyedSubtree(
                              key: _kHand,
                              child: TableHand(ctrl: ctrl, height: (box.maxHeight * 0.2).clamp(92.0, 136.0))),
                          KeyedSubtree(key: _kPass, child: _BottomBar(ctrl: ctrl, lastLog: lastLog, onPass: _passTurn)),
                        ]);
                      }
                      // Ecrã largo: o campo fica com a altura toda; zonas e "Passar
                      // turno" passam para uma coluna à direita. Num telemóvel deitado
                      // (pouca altura) a mão e a coluna encolhem.
                      // Tablet deitado (há altura): jogadores com
                      // a arte do comandante, mão maior e o registo na coluna da direita.
                      final roomy = !layout.short && box.maxHeight >= 640;
                      final handH = (box.maxHeight * (roomy ? 0.26 : 0.24)).clamp(84.0, roomy ? 200.0 : 168.0);
                      final panelW = layout.short
                          ? 96.0
                          : roomy
                              ? 236.0
                              : 128.0;
                      return Column(children: [
                        if (widget.banner != null) widget.banner!,
                        ..._notices(theme),
                        Expanded(
                          child: Row(children: [
                            Expanded(
                              child: Column(children: [
                                KeyedSubtree(
                                    key: _kPlayers,
                                    child: _PlayersStrip(ctrl: ctrl, compact: layout.short, big: roomy)),
                                Expanded(child: KeyedSubtree(key: _kField, child: TableBattlefield(ctrl: ctrl))),
                                // Num dobrável aberto a mão ficava por baixo da barra de gestos.
                                SafeArea(
                                  top: false,
                                  right: false,
                                  child: KeyedSubtree(key: _kHand, child: TableHand(ctrl: ctrl, height: handH)),
                                ),
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
                                  if (roomy) ...[
                                    // zonas em grelha (2 por linha) e, por baixo, as últimas jogadas
                                    Flexible(
                                      child: SingleChildScrollView(
                                        child: KeyedSubtree(
                                            key: _kZones,
                                            child:
                                                TableZonesRow(ctrl: ctrl, vertical: true, grid: true, pileWidth: 84)),
                                      ),
                                    ),
                                    const Divider(height: 1),
                                    Expanded(child: _LogPanel(ctrl: ctrl)),
                                  ] else ...[
                                    Expanded(
                                      child: SingleChildScrollView(
                                        child: KeyedSubtree(
                                            key: _kZones,
                                            child: TableZonesRow(
                                                ctrl: ctrl, vertical: true, pileWidth: layout.short ? 42 : 72)),
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
                                  ],
                                  Padding(
                                    key: _kPass,
                                    padding: const EdgeInsets.all(6),
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        minimumSize: Size.fromHeight(layout.short ? 44 : 64),
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                      ),
                                      onPressed:
                                          ctrl.mySeats.contains(s.activeSeat) || !ctrl.isNetwork ? _passTurn : null,
                                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                                        const Icon(Icons.skip_next),
                                        if (!layout.short) Text(tr('Passar turno'), textAlign: TextAlign.center),
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
                ),
                if (_touring)
                  Positioned.fill(
                    child: TableTour(
                      steps: _tourSteps,
                      onDone: () {
                        ref.read(settingsProvider).tableTourDone = true;
                        setState(() => _touring = false);
                      },
                    ),
                  ),
              ]));
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
  const _PlayersStrip({required this.ctrl, this.compact = false, this.big = false});
  final GameController ctrl;

  /// Telemóvel deitado: menos altura.
  final bool compact;

  /// Tablet: cartões grandes, com a arte do comandante e a vida em grande.
  final bool big;

  @override
  Widget build(BuildContext context) {
    final s = ctrl.state;
    final seats = s.players.keys.toList()..sort();
    final theme = Theme.of(context);
    // Num telemóvel com 3 ou mais jogadores, os cartões dividem a largura
    // (antes era preciso deslizar para ver a vida do último).
    final width = MediaQuery.sizeOf(context).width;
    final split = seats.length >= 3 && width / seats.length < 150;
    if (big && width / seats.length >= 170) {
      return SizedBox(
        height: 80,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 2, 6),
          child: Row(children: [
            for (final seat in seats)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _BigPlayerChip(ctrl: ctrl, seat: seat, color: GameColors.player(seats.indexOf(seat))),
                ),
              ),
          ]),
        ),
      );
    }
    final chips = [
      for (final seat in seats)
        Builder(builder: (context) {
          final p = s.players[seat]!;
          final isActive = s.activeSeat == seat;
          final viewing = ctrl.viewSeat == seat;
          final maxCmd = p.commanderDamage.values.fold(0, (m, v) => v > m ? v : m);
          final poison = p.counters[PlayerCounter.poison] ?? 0;
          final targeted = s.targets.any((t) => t.seat == seat);
          // a mesma linguagem da mesa do bot: uma cor por lugar, numa faixa em
          // cima; o ativo com o contorno nessa cor, o que está em vista tingido
          final color = GameColors.player(seats.indexOf(seat));
          final bg = viewing
              ? Color.alphaBlend(color.withOpacity(0.22), theme.colorScheme.surface)
              : theme.colorScheme.surface;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              // No tutorial um toque mostra o campo e a folha do jogador.
              onTap: () {
                if (!viewing) ctrl.setView(seat);
                if (viewing || ctrl.scripted) showPlayerSheet(context, ctrl, seat);
              },
              onLongPress: () => showPlayerSheet(context, ctrl, seat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: split ? const EdgeInsets.fromLTRB(7, 6, 5, 2) : const EdgeInsets.fromLTRB(10, 7, 10, 3),
                decoration: BoxDecoration(
                  // a faixa de cor em cima faz parte do fundo (um gradiente de paragem
                  // seca): numa lista horizontal não há largura para uma faixa à parte
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.07, 0.07, 1],
                    colors: [color, color, bg, bg],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: targeted
                        ? targetGlow
                        : isActive
                            ? color
                            : theme.colorScheme.outline,
                    width: isActive || targeted ? 2.5 : 1,
                  ),
                  boxShadow: targeted
                      ? [BoxShadow(color: targetGlow.withOpacity(0.8), blurRadius: 12, spreadRadius: 1)]
                      : null,
                ),
                // Com letra grande, o cartão encolhe em vez de transbordar.
                child: split
                    ? _SplitChip(
                        name: p.name,
                        life: p.life,
                        hand: p.handCount,
                        defeated: p.defeated,
                        offline: ctrl.offline.contains(seat),
                        targeted: targeted,
                        monarch: s.monarch == seat,
                        cmd: maxCmd,
                        poison: poison,
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
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
                                  const Icon(Icons.workspace_premium, size: 14, color: GameColors.gold),
                                if (s.initiative == seat) const Icon(Icons.flag, size: 14, color: Colors.teal),
                                if (ctrl.offline.contains(seat))
                                  Padding(
                                    padding: const EdgeInsets.only(right: 3),
                                    child: Tooltip(
                                        message: tr('Sem ligação'),
                                        child: const Icon(Icons.wifi_off, size: 14, color: EdhColors.bad)),
                                  ),
                                Text(p.name,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(decoration: p.defeated ? TextDecoration.lineThrough : null)),
                              ]),
                              // Cartas na mão e no grimório.
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.back_hand_outlined, size: 13, color: theme.colorScheme.onSurfaceVariant),
                                Text(' ${p.handCount}   ', style: theme.textTheme.labelSmall),
                                Icon(Icons.layers_outlined, size: 13, color: theme.colorScheme.onSurfaceVariant),
                                Text(' ${p.libraryCount}', style: theme.textTheme.labelSmall),
                              ]),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Text('${p.life}',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: p.life <= 0 || p.defeated ? EdhColors.bad : null)),
                          LifeDelta(life: p.life, fontSize: 12),
                          if (poison > 0 || maxCmd > 0) ...[
                            const SizedBox(width: 6),
                            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              if (poison > 0)
                                Text('☠$poison', style: const TextStyle(fontSize: 11, color: Colors.green)),
                              if (maxCmd > 0)
                                Text('★$maxCmd',
                                    style:
                                        TextStyle(fontSize: 11, color: maxCmd >= 21 ? EdhColors.bad : GameColors.gold)),
                            ]),
                          ],
                        ]),
                      ),
              ),
            ),
          );
        }),
    ];
    return SizedBox(
      height: compact ? 52 : 64,
      child: split
          ? Padding(
              padding: EdgeInsets.fromLTRB(8, compact ? 3 : 6, 2, compact ? 3 : 6),
              child: Row(children: [for (final c in chips) Expanded(child: c)]),
            )
          : ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 3 : 6),
              children: chips,
            ),
    );
  }
}

/// Cartão de jogador estreito (4 ou mais num telemóvel): nome e vida.
class _SplitChip extends StatelessWidget {
  const _SplitChip({
    required this.name,
    required this.life,
    required this.hand,
    required this.defeated,
    required this.offline,
    required this.targeted,
    required this.monarch,
    required this.cmd,
    required this.poison,
  });
  final String name;
  final int life;
  final int hand;
  final bool defeated;
  final bool offline;
  final bool targeted;
  final bool monarch;
  final int cmd;
  final int poison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Encolhe em vez de transbordar (telemóvel pequeno com letra grande).
    return LayoutBuilder(
      builder: (context, box) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: box.maxWidth,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  if (targeted) const Icon(Icons.gps_fixed, color: targetGlow, size: 12),
                  if (offline) const Icon(Icons.wifi_off, size: 12, color: EdhColors.bad),
                  if (monarch) const Icon(Icons.workspace_premium, size: 12, color: GameColors.gold),
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(decoration: defeated ? TextDecoration.lineThrough : null)),
                  ),
                ]),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('$life',
                        style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1,
                            color: life <= 0 || defeated ? EdhColors.bad : null)),
                    const SizedBox(width: 4),
                    if (cmd > 0)
                      Text('★$cmd ',
                          style: TextStyle(fontSize: 11, color: cmd >= 21 ? EdhColors.bad : GameColors.gold)),
                    if (poison > 0) Text('☠$poison ', style: const TextStyle(fontSize: 11, color: Colors.green)),
                    Icon(Icons.back_hand_outlined, size: 11, color: theme.colorScheme.onSurfaceVariant),
                    Text('$hand', style: theme.textTheme.labelSmall),
                  ]),
                ),
              ]),
        ),
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
    var bg = settings.backgroundImage;
    if (settings.commanderBackground) {
      // a ilustração do comandante de quem está em vista (o primeiro, com dois)
      final cmd = s.cards.values.where((c) => c.isCommander && c.owner == seat).firstOrNull;
      final card = cmd == null ? null : ctrl.card(cmd.oracleId, printId: cmd.printId);
      final ref0 = card == null ? null : ImageRef.allOf(card).firstOrNull;
      final art = ref0 == null ? null : ref.watch(imagesProvider).art(ref0);
      if (art != null) bg = FileImage(art);
    }
    // o campo de quem tem a vez fica com o contorno na cor desse lugar
    final active = s.activeSeat == seat && s.players.length > 1;
    final seatColor = GameColors.player((s.players.keys.toList()..sort()).indexOf(seat));

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
          foregroundDecoration: candidates.isNotEmpty
              ? BoxDecoration(border: Border.all(color: theme.colorScheme.primary, width: 3))
              : active
                  ? BoxDecoration(border: Border.all(color: seatColor, width: 3))
                  : null,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
            image: bg == null
                ? null
                : DecorationImage(
                    image: bg,
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(Colors.black.withOpacity(settings.backgroundDim), BlendMode.darken),
                  ),
          ),
          child: Stack(clipBehavior: Clip.hardEdge, children: [
            if (cards.isEmpty && bg == null)
              Center(
                child: Text(tr('Campo de {v}', {'v': s.players[seat]?.name ?? ''}),
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
                    highlighted: s.highlight == c.id || ctrl.coachFocus.contains(c.oracleId),
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
  const TableZonesRow(
      {super.key, required this.ctrl, this.seat, this.vertical = false, this.grid = false, this.pileWidth = 44});
  final GameController ctrl;
  final int? seat;

  /// Em coluna (barra lateral da mesa no tablet).
  final bool vertical;

  /// Em grelha, várias por linha (a coluna larga do tablet).
  final bool grid;
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

    Widget pile(String label, int count, Widget? top, VoidCallback onTap, {VoidCallback? onLong}) => GestureDetector(
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
            // O nome da zona não pode alargar a pilha (com letra grande a fila transbordava).
            SizedBox(
              width: w + 14,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 10)),
              ),
            ),
          ]),
        );

    final commandCards = [
      for (final c in command)
        GestureDetector(
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
                highlighted: ctrl.coachFocus.contains(c.oracleId),
                showTapped: false),
            Text(tr('Comando'), style: const TextStyle(fontSize: 10)),
          ]),
        ),
      // Comandante fora da zona de comando: o lugar fica marcado.
      if (command.isEmpty && s.cards.values.any((c) => c.isCommander && c.owner == seat))
        pile(tr('Comando'), 0, null, () {}),
    ];
    final libraryPile = pile(
      tr('Grimório'),
      p?.libraryCount ?? 0,
      (p?.libraryCount ?? 0) > 0 ? const CardBack() : null,
      mine
          ? () {
              ctrl.actAs(seat);
              // Em rede uma compra por engano vê-se em todos os telemóveis:
              // o toque abre o menu (Comprar 1 é a primeira opção).
              if (ctrl.isNetwork) {
                showLibraryMenu(context, ctrl);
              } else {
                ctrl.draw();
              }
            }
          : () {},
      onLong: mine
          ? () {
              ctrl.actAs(seat);
              showLibraryMenu(context, ctrl);
            }
          : null,
    );
    final gravePile = pile(
      tr('Cemitério'),
      grave.length,
      grave.isEmpty
          ? null
          : TableCardView(
              instance: grave.last,
              card: ctrl.card(grave.last.oracleId, printId: grave.last.printId),
              width: w,
              showTapped: false),
      () => showZoneList(context, ctrl, seat, Zone.graveyard),
    );
    final exilePile = pile(
      tr('Exílio'),
      exile.length,
      exile.isEmpty
          ? null
          : TableCardView(
              instance: exile.last,
              card: ctrl.card(exile.last.oracleId, printId: exile.last.printId),
              width: w,
              showTapped: false),
      () => showZoneList(context, ctrl, seat, Zone.exile),
    );
    final more = !mine
        ? null
        : IconButton(
            tooltip: tr('Grimório'),
            onPressed: () {
              ctrl.actAs(seat);
              showLibraryMenu(context, ctrl);
            },
            icon: const Icon(Icons.more_horiz),
          );

    if (grid) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [...commandCards, libraryPile, gravePile, exilePile, if (more != null) more],
        ),
      );
    }
    return Padding(
      padding: vertical ? const EdgeInsets.fromLTRB(8, 10, 8, 4) : const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: Flex(
          direction: vertical ? Axis.vertical : Axis.horizontal,
          mainAxisSize: vertical ? MainAxisSize.min : MainAxisSize.max,
          children: [
            for (final c in commandCards)
              Padding(
                padding: vertical ? const EdgeInsets.only(bottom: 8) : const EdgeInsets.only(right: 6),
                child: c,
              ),
            if (vertical) const SizedBox(height: 6) else const Spacer(),
            libraryPile,
            gap(),
            gravePile,
            gap(),
            exilePile,
            if (more != null) ...[
              if (!vertical) const SizedBox(width: 4),
              more,
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
              (ctrl.state.players[seat]?.handCount ?? 0) == 1
                  ? tr('Mão de {v}: 1 carta', {'v': ctrl.state.players[seat]?.name})
                  : tr('Mão de {v}: {v2} cartas',
                      {'v': ctrl.state.players[seat]?.name, 'v2': ctrl.state.players[seat]?.handCount ?? 0}),
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
        return mv != 0 ? mv : (ca?.displayName ?? '').compareTo(cb?.displayName ?? '');
      });
    }
    final covered = widget.hidden && !_peek;
    // Linha do custo de mana por cima de cada carta, sempre legível.
    final costH = (widget.height * 0.12).clamp(10.0, 17.0);
    final cardW = (widget.height - 10 - costH) * cardAspect;
    Widget buildCard(BuildContext context, PrivateCard pc) {
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
            covered || card == null
                ? const CardBack()
                : ctrl.coachFocus.contains(pc.oracleId)
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(color: theme.colorScheme.primary, blurRadius: 10, spreadRadius: 3),
                          ],
                        ),
                        child: CardImage(card),
                      )
                    : CardImage(card),
          ]),
        ),
      );
      if (covered) return item;
      // Tocar e manter, e arrastar para o campo.
      return Semantics(
        button: true,
        label: card?.displayName ?? tr('carta'),
        child: LongPressDraggable<PrivateCard>(
          data: pc,
          delay: const Duration(milliseconds: 250),
          onDragStarted: () => ctrl.actAs(seat),
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: cardW * 1.15,
              child: card == null ? const CardBack() : CardImage(card),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: item),
          child: item,
        ),
      );
    }

    final list = hand.isEmpty
        ? Center(child: Text(tr('Mão vazia'), style: theme.textTheme.bodySmall))
        : LayoutBuilder(builder: (context, box) {
            final fits = hand.length * (cardW + 4) + 16 <= box.maxWidth;
            // a rotação empurra as pontas para fora: fica uma margem de cada lado
            final step = hand.length > 1 ? (box.maxWidth - 28 - cardW) / (hand.length - 1) : cardW;
            // Não cabem: em leque, sobrepostas e um pouco rodadas, sem deslizar
            // (com muitas, a sobreposição esconderia demasiado: volta a lista).
            if (fits) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < hand.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        buildCard(context, hand[i]),
                      ],
                    ]),
              );
            }
            if (covered || step < cardW * 0.4) {
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                itemCount: hand.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, i) => buildCard(context, hand[i]),
              );
            }
            final mid = (hand.length - 1) / 2;
            return Stack(clipBehavior: Clip.hardEdge, children: [
              for (var i = 0; i < hand.length; i++)
                Positioned(
                  left: 14 + i * step,
                  // em arco: as das pontas um pouco mais abaixo
                  top: 2 + 4 * ((i - mid) / (mid == 0 ? 1 : mid)) * ((i - mid) / (mid == 0 ? 1 : mid)),
                  child: Transform.rotate(
                    angle: (i - mid) * 0.03,
                    alignment: Alignment.bottomCenter,
                    child: buildCard(context, hand[i]),
                  ),
                ),
            ]);
          });
    return SizedBox(
      height: widget.height,
      child: !widget.hidden
          ? Row(children: [
              Expanded(child: list),
              // a mão toda num ecrã, agrupada por tipo
              if (hand.length > 1)
                IconButton(
                  // o tooltip também é o nome para o leitor de ecrã
                  tooltip: tr('Ver a mão toda'),
                  onPressed: () => pushTablePage<void>(context, HandOverviewScreen(ctrl: ctrl, seat: seat)),
                  icon: const Icon(Icons.grid_view_rounded),
                ),
            ])
          : Row(children: [
              Expanded(child: list),
              IconButton(
                tooltip: _peek ? tr('Esconder a mão') : tr('Ver a mão'),
                onPressed: () => setState(() => _peek = !_peek),
                icon: Icon(_peek ? Icons.visibility_off : Icons.visibility),
              ),
            ]),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.ctrl, required this.lastLog, required this.onPass});
  final GameController ctrl;
  final String lastLog;
  final VoidCallback onPass;

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
            style: FilledButton.styleFrom(minimumSize: const Size(0, EdhSize.buttonCompact)),
            onPressed: myTurn || !ctrl.isNetwork ? onPass : null,
            icon: const Icon(Icons.skip_next),
            label: Text(tr('Passar turno')),
          ),
        ]),
      ),
    );
  }
}

/// No ecrã do mulligan: um adversário e o que fez com a mão inicial.
class _MulliganChip extends StatelessWidget {
  const _MulliganChip({required this.player, required this.color});
  final PlayerState player;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final (text, icon) = p.kept
        ? (tr('ficou com {n}', {'n': p.handCount}), Icons.check_rounded)
        : p.mulligans > 0
            ? (tr('mulligan {n}', {'n': p.mulligans}), Icons.refresh_rounded)
            : (tr('a decidir'), Icons.hourglass_top_rounded);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(p.kept ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.8)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: p.kept ? EdhColors.ok : Colors.white70),
        const SizedBox(width: 4),
        Text('${p.name} · $text', style: const TextStyle(color: Colors.white, fontSize: 12)),
      ]),
    );
  }
}

/// Tablet: um jogador na faixa de cima, com a arte do comandante por trás e a
/// vida em grande.
class _BigPlayerChip extends StatelessWidget {
  const _BigPlayerChip({required this.ctrl, required this.seat, required this.color});
  final GameController ctrl;
  final int seat;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = ctrl.state;
    final p = s.players[seat]!;
    final theme = Theme.of(context);
    final isActive = s.activeSeat == seat;
    final viewing = ctrl.viewSeat == seat;
    final maxCmd = p.commanderDamage.values.fold(0, (m, v) => v > m ? v : m);
    final poison = p.counters[PlayerCounter.poison] ?? 0;
    final targeted = s.targets.any((t) => t.seat == seat);
    final cmd = s.cards.values.where((c) => c.isCommander && c.owner == seat).firstOrNull;
    final card = cmd == null ? null : ctrl.card(cmd.oracleId, printId: cmd.printId);
    const shadow = [Shadow(blurRadius: 4)];
    const dim = TextStyle(color: Colors.white70, fontSize: 12, shadows: shadow);
    return Semantics(
      button: true,
      label: tr('{v}: {life} de vida', {'v': p.name, 'life': p.life}),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          if (!viewing) ctrl.setView(seat);
          if (viewing || ctrl.scripted) showPlayerSheet(context, ctrl, seat);
        },
        onLongPress: () => showPlayerSheet(context, ctrl, seat),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: targeted
                  ? targetGlow
                  : isActive
                      ? color
                      : viewing
                          ? Colors.white70
                          : theme.colorScheme.outline,
              width: isActive || targeted ? 3 : (viewing ? 2 : 1),
            ),
            boxShadow:
                targeted ? [BoxShadow(color: targetGlow.withOpacity(0.8), blurRadius: 12, spreadRadius: 1)] : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ArtBanner.card(
              card,
              credit: false,
              alignment: const Alignment(0, -0.4),
              child: Stack(fit: StackFit.expand, children: [
                // a cor do lugar, numa faixa à esquerda
                Positioned(left: 0, top: 0, bottom: 0, width: 5, child: ColoredBox(color: color)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            if (targeted) const Icon(Icons.gps_fixed, color: targetGlow, size: 16),
                            if (s.monarch == seat)
                              const Icon(Icons.workspace_premium, size: 15, color: GameColors.gold),
                            if (s.initiative == seat) const Icon(Icons.flag, size: 15, color: Colors.teal),
                            if (ctrl.offline.contains(seat))
                              Tooltip(
                                  message: tr('Sem ligação'),
                                  child: const Icon(Icons.wifi_off, size: 15, color: EdhColors.bad)),
                            if (viewing) const Icon(Icons.visibility_outlined, size: 15, color: Colors.white70),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      shadows: shadow,
                                      decoration: p.defeated ? TextDecoration.lineThrough : null)),
                            ),
                          ]),
                          const SizedBox(height: 2),
                          // com 4 num tablet ao alto há pouca largura: encolhe
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.back_hand_outlined, size: 13, color: Colors.white70),
                              Text(' ${p.handCount}   ', style: dim),
                              const Icon(Icons.layers_outlined, size: 13, color: Colors.white70),
                              Text(' ${p.libraryCount}', style: dim),
                            ]),
                          ),
                        ],
                      ),
                    ),
                    if (poison > 0 || maxCmd > 0) ...[
                      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        if (poison > 0)
                          Text('☠$poison',
                              style: const TextStyle(fontSize: 13, color: Colors.lightGreenAccent, shadows: shadow)),
                        if (maxCmd > 0)
                          Text('★$maxCmd',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: maxCmd >= 21 ? EdhColors.bad : GameColors.gold,
                                  shadows: shadow)),
                      ]),
                      const SizedBox(width: 8),
                    ],
                    Text('${p.life}',
                        style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            shadows: shadow,
                            color: p.life <= 0 || p.defeated ? EdhColors.bad : Colors.white)),
                    LifeDelta(life: p.life, fontSize: 12),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tablet: as últimas jogadas na coluna da direita (tocar abre o registo todo).
class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.ctrl});
  final GameController ctrl;

  @override
  Widget build(BuildContext context) {
    final s = ctrl.state;
    final theme = Theme.of(context);
    final seats = s.players.keys.toList()..sort();
    final entries = s.log.reversed.take(30).toList();
    return InkWell(
      onTap: () => showLogSheet(context, ctrl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Row(children: [
            Icon(Icons.receipt_long, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(tr('Registo'), style: theme.textTheme.labelMedium),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(10, 0, 8, 8),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              final idx = seats.indexOf(e.actor);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    margin: const EdgeInsets.only(top: 5, right: 6),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: idx < 0 ? theme.colorScheme.outline : GameColors.player(idx),
                    ),
                  ),
                  Expanded(
                    child: Text(ctrl.logText(e),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: i == 0 ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant)),
                  ),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}
