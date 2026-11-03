import 'dart:async';

import 'package:card_db/card_db.dart' hide Card;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/theme.dart';
import '../data/bracket.dart';
import '../data/providers.dart';
import '../data/settings.dart';
import '../game/draft.dart';
import '../game/match.dart';
import '../game/network_game.dart';
import '../game/resume_store.dart';
import '../net/host_server.dart';
import '../net/network_util.dart';
import '../net/room_client.dart';
import '../net/room_link.dart';
import '../room/room_session.dart';
import 'limited/draft_screen.dart';
import 'room_screen.dart';
import 'table/sideboard_sheet.dart';
import 'table/table_screen.dart';
import 'widgets/responsive.dart';
import '../l10n/l10n.dart';

/// Lobby de uma sala: cada jogador escolhe o deck e fica pronto; o
/// anfitrião começa o jogo. Depois mostra a mesa.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, required this.session, this.format, this.life, this.resume});

  final RoomSession session;

  /// A voltar a um jogo depois de a app fechar.
  final ResumeInfo? resume;

  /// Valores iniciais escolhidos pelo anfitrião ao criar a sala.
  final String? format;
  final int? life;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  late final NetworkGame _game = NetworkGame(
    session: widget.session,
    repo: ref.read(cardRepoProvider)!,
    prints: ref.read(printsProvider),
    images: ref.read(imagesProvider),
    resume: widget.resume,
    resumeStore: ref.read(resumeProvider),
    resumeDeck: widget.resume?.deckId == null
        ? null
        : ref.read(decksProvider).decks.where((d) => d.id == widget.resume!.deckId).firstOrNull,
  );
  bool _closing = false;
  bool _tableShown = false;

  /// A mesa fecha porque o anfitrião começou outra partida: o lobby fica.
  bool _backToLobby = false;

  /// Sem ligação, vê se o problema é o próprio telemóvel (Wi-Fi desligado,
  /// modo avião): aí não adianta esperar pelo anfitrião.
  final _offline = ValueNotifier(false);
  Timer? _netCheck;

  void _watchNetwork() {
    if (_game.link.status != LinkStatus.reconnecting) {
      _netCheck?.cancel();
      _netCheck = null;
      _offline.value = false;
      return;
    }
    _netCheck ??= Timer.periodic(const Duration(seconds: 2), (_) async {
      final off = !await hasLocalNetwork();
      if (mounted) _offline.value = off;
    });
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    if (widget.session.isHost && widget.format != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _game.configure(format: widget.format!, life: widget.life ?? 40));
    }
    _game.addListener(_maybeShowTable);
    _game.addListener(_maybeShowDraft);
    _game.addListener(_maybeClosed);
    _game.addListener(_watchNetwork);
    // A voltar a um jogo: a mesa já existe (o registo foi repetido) e abre logo.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTable());
  }

  void _maybeShowTable() {
    final g = _game.game;
    if (g == null && _tableShown && mounted) {
      // Nova partida: todos voltam ao lobby para escolher deck e ficar prontos.
      _tableShown = false;
      _backToLobby = true;
      Navigator.of(context).popUntil((r) => r.settings.name == _lobbyRoute || r.isFirst);
      return;
    }
    if (g == null || _tableShown || !mounted) return;
    if (!g.state.players.containsKey(_game.mySeat)) {
      // Fiquei de fora (não estava pronto): vejo como espectador.
      g.viewSeat = g.state.activeSeat;
    }
    _tableShown = true;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
      builder: (_) => ListenableBuilder(
        listenable: Listenable.merge([_game, _offline]),
        builder: (context, _) => TableScreen(
          ctrl: g,
          banner: switch (_game.link.status) {
            LinkStatus.reconnecting => MaterialBanner(
                content: Text(_lostText),
                leading: const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                actions: [TextButton(onPressed: _leaveFromTable, child: Text(tr('Sair')))],
              ),
            LinkStatus.closed when !_closing => MaterialBanner(
                content: Text(_closedReason),
                leading: const Icon(Icons.link_off),
                actions: [TextButton(onPressed: _leaveFromTable, child: Text(tr('Sair')))],
              ),
            _ => null,
          },
          onLeave: _leaveRoom,
          confirmLeave: _confirmLeaveTable,
          hostsRoom: _game.isHost,
          onNewGame: _game.isHost && _game.tournament == null ? _game.newGame : null,
          matchStatus: _game.tournament == null ? null : _matchStatus,
          afterGame: _game.tournament == null ? null : _afterGame,
        ),
      ),
    ))
        .then((_) {
      if (_backToLobby) {
        _backToLobby = false;
        return;
      }
      // Quem sai da mesa sai da sala: não fica num lobby sem ligação. Se o
      // lobby já saiu (Sair com a sala fechada volta ao início), não se tira
      // mais nada: era o ecrã inicial e a app ficava preta.
      if (mounted && (ModalRoute.of(context)?.isActive ?? false)) Navigator.of(context).pop();
    });
  }

  /// Encontro 1 contra 1: "Jogo 2 · 1–0" (as minhas vitórias primeiro).
  String _matchStatus() {
    final info = _game.myTableInfo;
    final m = info == null ? null : _game.tournament?.matchOf(info.round, _game.mySeat);
    if (info == null || m == null) return '';
    final me = _game.mySeat;
    return tr('Jogo {g} · {w}–{l}', {'g': info.game, 'w': m.wins(me), 'l': m.wins(m.other(me))});
  }

  /// No fim de cada jogo: o seguinte do encontro (antes, se houver
  /// sideboard, pode-se trocar cartas), ou voltar à sala.
  List<({String label, VoidCallback onPressed})> _afterGame() {
    final info = _game.myTableInfo;
    final m = info == null ? null : _game.tournament?.matchOf(info.round, _game.mySeat);
    if (m == null || m.done) return [(label: tr('Voltar à sala'), onPressed: _game.backToRoom)];
    return [
      if ((_game.myDeck?.count(Board.side) ?? 0) > 0) (label: tr('Sideboard'), onPressed: _sideboard),
      (label: tr('Jogo seguinte'), onPressed: _game.requestNextGame),
    ];
  }

  Future<void> _sideboard() async {
    final deck = _game.myDeck;
    if (deck == null || !mounted) return;
    _game.sideboard(await showSideboardSheet(context, deck, _game.repo));
    _game.requestNextGame();
  }

  /// A meio de um jogo, um cliente que sai só desliga: o lugar e a mão ficam
  /// guardados e volta em Jogar → Voltar ao jogo. Depois do fim (ou já
  /// derrotado) sai de vez.
  bool get _midGame {
    final g = _game.game;
    final me = g?.state.players[_game.mySeat];
    final l = _game.link;
    if (l is RoomClient && (l.kicked || l.hostClosed)) return false;
    return g != null && !g.state.over && me != null && !me.defeated;
  }

  Future<bool> _confirmLeaveTable(BuildContext context) async {
    // Sem ligação não há nada a perder.
    if (_game.link.status == LinkStatus.closed) return true;
    final host = _game.isHost && _game.game != null && !_game.game!.state.over;
    if (!host && !_midGame && !ref.read(settingsProvider).confirmLeave) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(host ? tr('Fechar a sala?') : tr('Sair da mesa?')),
        content: Text(host
            ? tr('És o anfitrião: se saíres, o jogo acaba para todos.')
            : _midGame
                ? tr('O teu lugar e a tua mão ficam guardados. Voltas em Jogar → Voltar ao jogo.')
                : tr('Sais da sala.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Ficar'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(host ? tr('Acabar o jogo') : tr('Sair'))),
        ],
      ),
    );
    return ok == true;
  }

  /// Tirado da sala, ou a sala fechou, com o lobby à vista: não há nada a
  /// fazer aqui, por isso volta-se ao ecrã de jogar com o motivo.
  void _maybeClosed() {
    final l = _game.link;
    if (_closing || _tableShown || !mounted || l.status != LinkStatus.closed) return;
    if (l is! RoomClient || !(l.kicked || l.hostClosed)) return;
    _closing = true;
    _game.forgetResume();
    final reason = _closedReason;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(reason)));
  }

  static const _lobbyRoute = 'lobby';
  DraftClient? _draftShown;

  /// Quando o anfitrião começa um draft, abre o ecrã do draft a quem joga.
  void _maybeShowDraft() {
    final client = _game.draftClient;
    if (client == null || identical(client, _draftShown) || !mounted) return;
    _draftShown = client;
    _openDraft();
  }

  void _openDraft() {
    final client = _game.draftClient;
    if (client == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DraftScreen(
        client: client,
        // O deck montado no fim do draft fica logo escolhido.
        onDeck: (deck) {
          if (mounted && !(_game.me?.ready ?? false)) _useDeck(deck);
        },
      ),
    ));
  }

  String get _closedReason {
    final l = _game.link;
    if (l is RoomClient && l.hostClosed) return tr('O anfitrião fechou a sala.');
    if (l is RoomClient && l.kicked) return tr('O anfitrião tirou-te da sala.');
    return tr('A ligação à sala terminou.');
  }

  /// Os comandantes chegam com o nome Oracle; mostram-se nas cartas deste telemóvel.
  String _localName(String name) => _game.repo.findByName(name)?.displayName ?? name;

  /// "Ligação perdida": diz de quem se está à espera (é o anfitrião quem liga
  /// todos; se ele cair, ninguém joga).
  String get _lostText {
    if (_offline.value) return tr('Este telemóvel está sem rede. Liga o Wi-Fi: o jogo volta sozinho.');
    final host = _game.players.values.where((p) => p.isHost).firstOrNull;
    return host == null
        ? tr('Ligação perdida. A voltar a ligar…')
        : tr('Sem ligação ao anfitrião ({v}). A tentar voltar a ligar…', {'v': host.name});
  }

  /// Começar com quem está pronto: quem não está fica de fora, por isso pergunta.
  Future<void> _start() async {
    final g = _game;
    final out = [
      for (final p in g.players.values)
        if (p.connected && !p.ready) p.seat == g.mySeat ? tr('tu') : p.name
    ];
    if (out.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Começar sem todos?')),
          content: Text(out.length == 1
              ? tr('{v} ainda não confirmou e fica de fora deste jogo.', {'v': out.single})
              : tr('{v} ainda não confirmaram e ficam de fora deste jogo.', {'v': out.join(', ')})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Esperar'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Começar'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    // Modern, Limited…: 1 contra 1, em encontros; o Commander junta todos.
    if (g.oneVsOne) {
      g.startMatches();
    } else {
      g.start();
    }
  }

  /// Anfitrião: tirar um jogador da sala (quem saiu e deixou o lugar preso).
  Future<void> _kick(LobbyPlayer p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Tirar {v} da sala?', {'v': p.name})),
        content: Text(tr('O lugar fica livre. Pode voltar a entrar como um jogador novo.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Tirar da sala'))),
        ],
      ),
    );
    final link = _game.link;
    if (ok == true && link is HostServer) link.kick(p.seat);
  }

  /// Sai da mesa e da sala (ligação perdida ou sala fechada).
  Future<void> _leaveFromTable() async {
    await _leaveRoom();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _leaveRoom() async {
    if (_closing) return;
    final keepSeat = !_game.isHost && _midGame;
    _closing = true;
    if (!keepSeat) _game.forgetResume();
    await widget.session.close(keepSeat: keepSeat);
  }

  @override
  void dispose() {
    _game.removeListener(_maybeShowTable);
    _game.removeListener(_maybeShowDraft);
    _game.removeListener(_maybeClosed);
    _game.removeListener(_watchNetwork);
    _netCheck?.cancel();
    _offline.dispose();
    _game.dispose();
    WakelockPlus.disable();
    if (!_closing) widget.session.close();
    super.dispose();
  }

  Future<void> _pickDeck() async {
    final format = GameFormat.byId(_game.format);
    // Os decks do formato da sala primeiro; os outros ficam no fim.
    final all = ref.read(decksProvider).decks;
    final decks = [...all.where((d) => d.format == format.id), ...all.where((d) => d.format != format.id)];
    final chosen = await showModalBottomSheet<Deck>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(tr('Escolher deck ({v})', {'v': format.label}), style: Theme.of(ctx).textTheme.titleMedium),
          ),
          if (decks.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr('Ainda não tens decks.'))),
          for (final d in decks)
            ListTile(
              title: Text(d.name),
              subtitle: Text(tr('{v} · {playableCount} cartas',
                  {'v': GameFormat.byId(d.format).label, 'playableCount': d.playableCount})),
              onTap: () => Navigator.pop(ctx, d),
            ),
        ]),
      ),
    );
    if (chosen == null) return;
    _useDeck(chosen);
  }

  /// Escolhe este deck para a partida (avisa se não cumpre o formato).
  void _useDeck(Deck chosen) {
    final repo = ref.read(cardRepoProvider)!;
    final format = GameFormat.byId(_game.format);
    final cards = repo.getMany(chosen.entries.map((e) => e.oracleId));
    final issues = validateDeck(chosen, format, cards, repo.legalityIn(format.legalityKey ?? '', cards.keys));
    final legal = issues.where((i) => i.level == IssueLevel.error).isEmpty;
    // Com internet, as imagens do meu deck vêm já (antes, só ao abrir o deck).
    final prints = ref.read(printsProvider);
    ref
        .read(imagesProvider)
        .ensureRefs(cards.values.expand((c) => ImageRef.allOf(prints.resolve(c))), sizes: const ['small']).ignore();
    _game.selectDeck(
      chosen,
      legal: legal,
      commanderNames: [
        for (final e in chosen.inBoard(Board.command))
          cards[e.oracleId]?.name ?? '?', // Oracle: cada um mostra na sua língua
      ],
      gameChangers: format.hasCommandZone ? BracketEstimate.of(chosen, cards).count : null,
    );
    if (!legal && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(issues.length == 1
            ? tr('O deck tem 1 aviso para {v}. Podes jogar na mesma.', {'v': format.label})
            : tr('O deck tem {n} avisos para {v}. Podes jogar na mesma.', {'n': issues.length, 'v': format.label})),
      ));
    }
  }

  Future<void> _configure() async {
    var format = _game.format;
    var life = _game.startingLife;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Regras da sala')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: format,
              decoration: InputDecoration(labelText: tr('Formato')),
              items: [for (final f in GameFormat.all) DropdownMenuItem(value: f.id, child: Text(f.label))],
              onChanged: (v) => set(() {
                format = v ?? format;
                life = GameFormat.byId(format).startingLife;
              }),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Text(tr('Vida inicial')),
              const Spacer(),
              IconButton(onPressed: life > 1 ? () => set(() => life--) : null, icon: const Icon(Icons.remove)),
              Text('$life', style: Theme.of(ctx).textTheme.titleMedium),
              IconButton(onPressed: () => set(() => life++), icon: const Icon(Icons.add)),
            ]),
            // numa só linha, mesmo em ecrãs pequenos (os chips partiam o 40 para baixo)
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: [
                  for (final v in const [20, 25, 30, 40]) ButtonSegment(value: v, label: Text('$v'))
                ],
                selected: {
                  if (const [20, 25, 30, 40].contains(life)) life
                },
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  if (s.isNotEmpty) set(() => life = s.first);
                },
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
            TextButton(
              onPressed: () {
                _game.configure(format: format, life: life);
                Navigator.pop(ctx);
              },
              child: Text(tr('Guardar')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(widget.session.isHost ? tr('Fechar a sala?') : tr('Sair da sala?')),
            content: widget.session.isHost ? Text(tr('Os outros jogadores saem também.')) : null,
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Ficar'))),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sair'))),
            ],
          ),
        );
        if (ok == true) {
          await _leaveRoom();
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([_game, _offline]),
        builder: (context, _) {
          final theme = Theme.of(context);
          final g = _game;
          final format = GameFormat.byId(g.format);
          final me = g.me;
          final status = g.link.status;
          final narrow = MediaQuery.sizeOf(context).width < 440;
          final dense = narrow && g.players.length >= 4;
          final missingSeats = [
            for (final p in g.players.values)
              if (g.missingFrom(p.seat).isNotEmpty) p.seat
          ];
          return Scaffold(
            appBar: AppBar(
              title: Text(widget.session.roomName, overflow: TextOverflow.ellipsis),
              actions: [
                if (widget.session.isHost)
                  IconButton(
                    tooltip: tr('QR code'),
                    icon: const Icon(Icons.qr_code_2),
                    onPressed: () => showRoomQr(context, widget.session),
                  ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'kick') {
                      final others = g.players.values.where((p) => p.seat != g.mySeat).toList();
                      final who = await showDialog<LobbyPlayer>(
                        context: context,
                        builder: (ctx) => SimpleDialog(
                          title: Text(tr('Tirar da sala')),
                          children: [
                            for (final p in others)
                              SimpleDialogOption(
                                onPressed: () => Navigator.pop(ctx, p),
                                child: Text(p.name, style: const TextStyle(fontSize: 16)),
                              ),
                          ],
                        ),
                      );
                      if (who != null) await _kick(who);
                      return;
                    }
                    if (v == 'diag' && context.mounted) {
                      Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => RoomScreen(session: widget.session, diagnostics: true),
                      ));
                    }
                  },
                  itemBuilder: (_) => [
                    if (g.isHost && g.players.length > 1)
                      PopupMenuItem(value: 'kick', child: Text(tr('Tirar um jogador da sala…'))),
                    PopupMenuItem(value: 'diag', child: Text(tr('Diagnóstico de rede'))),
                  ],
                ),
              ],
            ),
            // O que se faz a seguir fica sempre à vista, mesmo com a lista
            // de jogadores a pedir scroll num ecrã pequeno.
            bottomNavigationBar: me == null && !g.isHost
                ? null
                : BottomActions(children: [
                    if (g.tournament case final t? when g.isHost)
                      if (t.finished)
                        FilledButton.icon(
                          onPressed: g.newGame,
                          icon: const Icon(Icons.replay),
                          label: Text(tr('Nova partida')),
                        )
                      else if (t.roundDone(t.round))
                        FilledButton.icon(
                          onPressed: g.startNextRound,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(tr('Começar a ronda {n}', {'n': t.round + 2})),
                        )
                      else
                        FilledButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.hourglass_empty_rounded),
                          label: Text(tr('À espera dos encontros')),
                        ),
                    if (me != null && g.tournament == null)
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: me.ready ? null : _pickDeck,
                            child: Text(g.myDeck == null ? tr('Escolher deck') : g.myDeck!.name,
                                maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: g.myDeck == null ? null : () => g.setReady(!me.ready),
                            child: Text(me.ready ? tr('Espera, ainda não') : tr('Tudo pronto'),
                                textAlign: TextAlign.center),
                          ),
                        ),
                      ]),
                    if (g.isHost && g.tournament == null) ...[
                      FilledButton.icon(
                        onPressed: g.oneVsOne
                            ? (g.players.values.where((p) => p.ready).length >= 2 ? _start : null)
                            : (g.players.values.any((p) => p.ready) ? _start : null),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(g.oneVsOne
                            ? tr('Começar encontros (melhor de 3)')
                            : g.allReady
                                ? tr('Começar jogo')
                                : tr('Começar (só com quem está pronto)')),
                      ),
                    ],
                  ]),
            body: MaxWidth(
                child: ListView(padding: const EdgeInsets.all(16), children: [
              if (status == LinkStatus.reconnecting)
                Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(leading: const CircularProgressIndicator(), title: Text(_lostText))),
              if (status == LinkStatus.closed && !_closing)
                Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(leading: const Icon(Icons.link_off), title: Text(_closedReason))),
              if (g.tournament case final t?) ...[
                _TournamentCard(game: g, tournament: t),
                const SizedBox(height: 8),
              ],
              Card(
                child: ListTile(
                  leading: Icon(Icons.rule, color: theme.colorScheme.primary),
                  title: Text(tr('{v} · vida {startingLife}', {'v': format.label, 'startingLife': g.startingLife})),
                  subtitle: Text([
                    g.players.length == 1
                        ? tr('1 jogador na sala')
                        : tr('{n} jogadores na sala', {'n': g.players.length}),
                    // Só o Commander junta todos na mesma mesa.
                    if (g.oneVsOne) tr('1 contra 1, à melhor de 3; todos jogam com todos'),
                  ].join('\n')),
                  trailing: g.isHost && g.tournament == null ? const Icon(Icons.edit) : null,
                  // a meio dos encontros o formato e a vida não mudam
                  onTap: g.isHost && g.tournament == null ? _configure : null,
                ),
              ),
              const SizedBox(height: 16),
              Text(tr('Jogadores'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final p in g.players.values)
                Card(
                  margin: EdgeInsets.only(bottom: dense ? 6 : 8),
                  child: ListTile(
                    dense: dense,
                    visualDensity: dense ? VisualDensity.compact : null,
                    onLongPress: g.isHost && p.seat != g.mySeat ? () => _kick(p) : null,
                    leading: Icon(
                      p.isHost ? Icons.star_rounded : Icons.person,
                      color: p.connected ? EdhColors.ok : EdhColors.bad,
                    ),
                    title: Text(p.seat == g.mySeat ? tr('{v} (tu)', {'v': p.name}) : p.name),
                    subtitle: Text(p.deckName == null
                        ? tr('Ainda sem deck')
                        : tr('{deckName} · {deckSize} cartas{v}{v2}{v3}', {
                            'deckName': p.deckName,
                            'deckSize': p.deckSize,
                            'v': p.commanders.isEmpty ? '' : ' · ${p.commanders.map(_localName).join(' + ')}',
                            'v2': p.gameChangers == null
                                ? ''
                                : ' · ${BracketEstimate(List.filled(p.gameChangers!, '')).short}',
                            'v3': p.deckLegal ? '' : tr(' · com avisos')
                          })),
                    // Ecrã estreito: a palavra fica por baixo do ícone (só o ícone não se percebe).
                    trailing: narrow
                        ? Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(p.ready ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded,
                                size: 20, color: p.ready ? EdhColors.ok : theme.colorScheme.onSurfaceVariant),
                            Text(p.ready ? tr('Pronto') : tr('A escolher'),
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: p.ready ? EdhColors.ok : theme.colorScheme.onSurfaceVariant)),
                          ])
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(p.ready ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded,
                                size: 18, color: p.ready ? EdhColors.ok : theme.colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(p.ready ? tr('Pronto') : tr('A escolher'),
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(color: p.ready ? EdhColors.ok : theme.colorScheme.onSurfaceVariant)),
                          ]),
                  ),
                ),
              if (missingSeats.length > 1 && g.downloadingFrom == null && g.transfer == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    onPressed: () async {
                      for (final seat in missingSeats) {
                        await g.downloadMissing(seat);
                      }
                    },
                    icon: const Icon(Icons.download),
                    label: Text(tr('Descarregar todas as imagens (~{v} MB)', {
                      'v': (g.missingTotal * smallImageBytes / 1024 / 1024).toStringAsFixed(1),
                    })),
                  ),
                ),
              for (final p in g.players.values)
                if (g.missingFrom(p.seat) case final missing when missing.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: theme.colorScheme.primaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.image_outlined),
                      title: Text(missing.length == 1
                          ? tr('{v} tem 1 imagem que não tens', {'v': p.name})
                          : tr('{v} tem {n} imagens que não tens', {'v': p.name, 'n': missing.length})),
                      subtitle: Text(g.transfer?.seat == p.seat
                          ? tr('A receber do dispositivo de {v}… {received}/{expected}',
                              {'v': p.name, 'received': g.transfer!.received, 'expected': g.transfer!.expected})
                          : tr('~{v} MB · da internet ou, sem rede, do telemóvel de {v2}', {
                              'v': (missing.length * smallImageBytes / 1024 / 1024).toStringAsFixed(1),
                              'v2': p.name
                            })),
                      trailing: g.downloadingFrom == p.seat || g.transfer?.seat == p.seat
                          ? SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  value: g.transfer?.seat == p.seat && g.transfer!.expected > 0
                                      ? g.transfer!.received / g.transfer!.expected
                                      : null))
                          : FilledButton(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, EdhSize.buttonCompact)),
                              onPressed: () => g.downloadMissing(p.seat),
                              child: Text(tr('Descarregar')),
                            ),
                    ),
                  ),
              if (g.draftClient != null) ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _openDraft,
                  icon: const Icon(Icons.style),
                  label: Text(g.draftClient!.finished ? tr('Ver o draft (terminado)') : tr('Voltar ao draft')),
                ),
              ],
              // a meio dos encontros não se começa outro draft
              if (g.isHost && (g.tournament?.finished ?? true)) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => showDraftSetup(context, ref, g),
                  icon: const Icon(Icons.card_giftcard),
                  label: Text(g.draft == null ? tr('Fazer um draft') : tr('Novo draft')),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                tr('Cada um joga com o seu telemóvel. A mão e o grimório de cada jogador nunca saem do telemóvel dele.'),
                style: theme.textTheme.bodySmall,
              ),
            ])),
          );
        },
      ),
    );
  }
}

/// Encontros 1 contra 1: a ronda em curso, quem joga com quem e a classificação.
class _TournamentCard extends StatelessWidget {
  const _TournamentCard({required this.game, required this.tournament});
  final NetworkGame game;
  final Tournament tournament;

  String _name(int seat) {
    final n = game.players[seat]?.name ?? '?';
    return seat == game.mySeat ? tr('{v} (tu)', {'v': n}) : n;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = tournament;
    final standings = t.standings();
    final byes = t.byes(t.round);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            t.finished
                ? tr('Encontros acabados: {v} ganhou', {'v': _name(standings.first.seat)})
                : tr('Ronda {r} de {n}', {'r': t.round + 1, 'n': t.roundCount}),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (!t.finished) ...[
            const SizedBox(height: 8),
            for (final m in t.results[t.round])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Icon(m.done ? Icons.check_circle_outline : Icons.sports_esports_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tr(
                        '{a} {wa}–{wb} {b}', {'a': _name(m.a), 'wa': m.wins(m.a), 'wb': m.wins(m.b), 'b': _name(m.b)})),
                  ),
                  Text(m.done ? tr('acabou') : tr('a jogar'), style: theme.textTheme.labelMedium),
                ]),
              ),
            for (final s in byes)
              Text(
                s == game.mySeat
                    ? tr('Tens folga nesta ronda: conta como vitória.')
                    : tr('{v} tem folga nesta ronda (conta como vitória).', {'v': _name(s)}),
                style: theme.textTheme.bodySmall,
              ),
          ],
          const SizedBox(height: 12),
          Text(tr('Classificação'), style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          for (final (i, s) in standings.indexed)
            Text(tr('{i}. {v} · {p} · {w}-{l}{d} em encontros', {
              'i': i + 1,
              'v': _name(s.seat),
              'p': s.points == 1 ? tr('1 ponto') : tr('{n} pontos', {'n': s.points}),
              'w': s.matchWins + s.byes,
              'l': s.matchLosses,
              'd': s.matchDraws > 0 ? '-${s.matchDraws}' : '',
            })),
        ]),
      ),
    );
  }
}
