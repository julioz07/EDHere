import 'dart:convert';
import 'dart:math';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/foundation.dart';
import 'package:mesa_core/mesa_core.dart';

/// Jogador a sentar à mesa num playtest local.
class SeatSetup {
  const SeatSetup({required this.seat, required this.name, required this.deck});
  final int seat;
  final String name;
  final db.Deck deck;
}

/// Liga o núcleo de jogo à interface. Num playtest todos os eventos são
/// aplicados logo; em rede passam primeiro pelo anfitrião (ver
/// `NetworkGame`), mas a interface é a mesma.
class GameController extends ChangeNotifier {
  GameController({
    required this.table,
    required this.repo,
    required this.mySeats,
    required this.viewSeat,
    this.isNetwork = false,
    Map<int, db.Deck>? decks,
  }) : decks = decks ?? {};

  /// Cria um playtest local (goldfish com 1 deck, hot-seat com vários).
  factory GameController.playtest({
    required db.CardRepository repo,
    required db.GameFormat format,
    required List<SeatSetup> seats,
    bool randomFirst = false,
    db.Card Function(db.Card base, String? printId)? resolvePrint,
    String? Function(String oracleId, String? deckPrintId)? effectivePrint,
  }) {
    final table = Table(format: format.id, localSeats: {for (final s in seats) s.seat});
    final c = GameController(
      table: table,
      repo: repo,
      mySeats: {for (final s in seats) s.seat},
      viewSeat: seats.first.seat,
      decks: {for (final s in seats) s.seat: s.deck},
    )
      ..resolvePrint = resolvePrint
      ..effectivePrint = effectivePrint;
    final life =
        seats.length > 2 && format.multiplayerLife != null ? format.multiplayerLife! : format.startingLife;
    for (final s in seats) {
      c.sendAs(s.seat, Intent(Ev.joinTable, {'seat': s.seat, 'name': s.name, 'life': life}));
    }
    for (final s in seats) {
      c.sendAs(s.seat, c.deckIntent(s.seat, s.deck));
    }
    final first = randomFirst ? seats[Random().nextInt(seats.length)].seat : seats.first.seat;
    c.sendAs(first, Intent(Ev.startGame, {'first': first}));
    for (final s in seats) {
      c.sendAs(s.seat, table.draw(s.seat, 7));
    }
    c.viewSeat = first;
    return c;
  }

  /// Volta a um jogo solo gravado com [saveJson]. [decks] são os decks de
  /// cada lugar (para o histórico e os tokens), se ainda existirem.
  factory GameController.restore({
    required db.CardRepository repo,
    required Map<String, dynamic> json,
    required Map<int, db.Deck> decks,
    db.Card Function(db.Card base, String? printId)? resolvePrint,
    String? Function(String oracleId, String? deckPrintId)? effectivePrint,
  }) {
    final seats = {for (final s in (json['seats'] as List).cast<num>()) s.toInt()};
    final table = Table(format: (json['table']['state'] as Map)['format'] as String, localSeats: seats)
      ..restoreAll((json['table'] as Map).cast<String, dynamic>());
    final c = GameController(
      table: table,
      repo: repo,
      mySeats: seats,
      viewSeat: (json['view'] as num?)?.toInt() ?? seats.first,
      decks: decks,
    )
      ..resolvePrint = resolvePrint
      ..effectivePrint = effectivePrint
      ..autoDraw = json['auto'] == true
      ..elapsedBefore = Duration(seconds: (json['elapsed'] as num?)?.toInt() ?? 0)
      .._seq = (json['seq'] as num?)?.toInt() ?? table.state.seq;
    for (final MapEntry(:key, :value) in (json['mull'] as Map? ?? const {}).entries) {
      c.mulligans[int.parse(key as String)] = (value as num).toInt();
    }
    c.openingDone.addAll((json['opening'] as List? ?? const []).cast<num>().map((n) => n.toInt()));
    return c;
  }

  /// Tudo o que é preciso para continuar este jogo mais tarde (só local).
  Map<String, dynamic> saveJson() => {
        'table': table.saveAll(),
        'seq': _seq,
        'seats': mySeats.toList(),
        'view': viewSeat,
        'auto': autoDraw,
        'mull': {for (final e in mulligans.entries) '${e.key}': e.value},
        'opening': openingDone.toList(),
        'elapsed': (elapsedBefore + DateTime.now().difference(startedAt)).inSeconds,
      };

  final Table table;
  final db.CardRepository repo;

  /// Lugares que este dispositivo controla.
  final Set<int> mySeats;

  /// Decks dos lugares deste dispositivo (para o histórico).
  final Map<int, db.Deck> decks;
  final DateTime startedAt = DateTime.now();

  /// Tempo jogado antes de gravar (num jogo retomado).
  Duration elapsedBefore = Duration.zero;

  /// Lugares que já decidiram a mão inicial (manter ou mulligan).
  final Set<int> openingDone = {};

  /// Registo da partida para o histórico local.
  db.GameRecord record({int? winnerSeat}) {
    final s = state;
    final players = [
      for (final p in s.players.values)
        db.GamePlayer(
          name: p.name,
          deckName: decks[p.seat]?.name,
          commanders: [
            for (final c in s.cards.values)
              if (c.isCommander && c.owner == p.seat) cardName(c.oracleId),
          ],
          me: mySeats.contains(p.seat),
        ),
    ];
    final winnerLocal = winnerSeat != null && mySeats.contains(winnerSeat);
    return db.GameRecord(
      format: s.format,
      players: players,
      winner: winnerSeat == null ? null : s.players[winnerSeat]?.name,
      myDeckId: (winnerLocal ? decks[winnerSeat] : decks[mySeats.first])?.id,
      myWon: winnerLocal && mySeats.length == 1,
      turns: s.turn,
      duration: elapsedBefore + DateTime.now().difference(startedAt),
      network: isNetwork,
      playedAt: DateTime.now(),
    );
  }

  /// Lugar cujo campo e mão estão no ecrã.
  int viewSeat;
  final bool isNetwork;

  /// Compra automática no início do turno.
  bool autoDraw = false;

  /// Lugares de jogadores que perderam a ligação (só em rede).
  final Set<int> offline = {};

  /// Mulligans feitos por lugar (para saber quantas pôr no fundo).
  final Map<int, int> mulligans = {};
  int _seq = 0;

  /// Para a versão em rede: envia a intenção em vez de a aplicar.
  void Function(int actor, Intent intent)? networkSend;

  /// Jogo com guião (tutorial): a mesa não aplica as preferências de compra
  /// automática nem pergunta pelo mulligan.
  bool scripted = false;

  /// Decide se uma ação pode acontecer (o tutorial só deixa o passo pedido).
  bool Function(int seat, Intent intent)? guard;

  /// Cartas a destacar para o jogador (Oracle IDs): o tutorial mostra onde
  /// tocar, na mão, no campo e na zona de comando.
  Set<String> coachFocus = const {};

  /// Ronda do jogo (cada jogador jogou uma vez), para quem conta "o meu
  /// 2.º turno" em vez dos turnos de todos.
  int get round {
    final n = state.players.length;
    return n == 0 ? state.turn : (state.turn - 1) ~/ n + 1;
  }

  GameState get state => table.state;

  /// O lugar que age: no hot-seat é o que está no ecrã.
  int get actor => mySeats.contains(viewSeat) ? viewSeat : mySeats.first;

  bool get viewingMine => mySeats.contains(viewSeat);

  void send(Intent i) => sendAs(actor, i);

  void sendAs(int seat, Intent i) {
    i = _withEntryCounters(i);
    final send = networkSend;
    if (send != null) {
      send(seat, i);
      return;
    }
    if (guard case final g? when !g(seat, i)) return;
    // Local: aplica já, com o mesmo caminho por JSON da rede.
    final p = jsonDecode(jsonEncode(i.payload)) as Map<String, dynamic>;
    table.apply(++_seq, i.type, seat, p);
    _afterApply(i.type, seat);
    notifyListeners();
  }

  /// Um planeswalker entra em campo com a lealdade impressa na carta.
  Intent _withEntryCounters(Intent i) {
    final p = i.payload;
    if (i.type != Ev.move || p['to'] != Zone.battlefield.id || p['fd'] == true || p.containsKey('ctr')) {
      return i;
    }
    final String? oracle;
    if (p['id'] is num) {
      final c = state.cards[(p['id'] as num).toInt()];
      if (c == null || c.zone == Zone.battlefield) return i;
      oracle = c.oracleId;
    } else {
      oracle = p['o'] as String?;
    }
    final loyalty = int.tryParse(card(oracle)?.loyalty ?? '');
    if (loyalty == null || loyalty <= 0) return i;
    return Intent(i.type, {
      ...p,
      'ctr': {CounterKind.loyalty: loyalty}
    });
  }

  /// Chamado pela versão em rede quando chega um evento ordenado.
  void applyRemote(int seq, String type, int actor, Map<String, dynamic> payload) {
    table.apply(seq, type, actor, payload);
    _afterApply(type, actor);
    notifyListeners();
  }

  void _afterApply(String type, int actor) {
    if (type == Ev.passTurn) {
      final next = state.activeSeat;
      // Quando chega o meu turno, a mesa volta para o meu campo.
      if (mySeats.contains(next)) viewSeat = next;
      if (autoDraw && mySeats.contains(next)) {
        Future.microtask(() => sendAs(next, table.draw(next, 1)));
      }
    }
  }

  /// No modo tablet, a área onde se toca define quem age (sem redesenhar).
  void actAs(int seat) {
    if (mySeats.contains(seat)) viewSeat = seat;
  }

  void setView(int seat) {
    viewSeat = seat;
    notifyListeners();
  }

  Intent deckIntent(int seat, db.Deck deck) {
    final library = <String>[
      for (final e in deck.entries.where((e) => e.board == db.Board.main))
        for (var i = 0; i < e.qty; i++) e.oracleId,
    ];
    final commanders = [
      for (final e in deck.entries.where((e) => e.board == db.Board.command)) e.oracleId,
    ];
    // Versão de cada carta: a escolhida no deck ou a preferida.
    final prints = <String, String>{
      for (final e in deck.entries)
        if ((effectivePrint?.call(e.oracleId, e.printId) ?? e.printId) case final p?) e.oracleId: p,
    };
    return table.loadDeck(seat, library, commanders, prints: prints);
  }

  // ---------------------------------------------------------------------
  // Atalhos usados pela interface
  // ---------------------------------------------------------------------

  /// Mostra cada carta com a sua versão (impressão).
  db.Card Function(db.Card base, String? printId)? resolvePrint;

  /// Versão efetiva de uma entrada de deck (a do deck ou a preferida).
  String? Function(String oracleId, String? deckPrintId)? effectivePrint;

  db.Card? card(String? oracleId, {String? printId}) {
    final c = oracleId == null ? null : repo.get(oracleId);
    if (c == null) return null;
    final r = resolvePrint;
    return r == null ? c : r(c, printId);
  }

  String cardName(String? oracleId) => card(oracleId)?.name ?? 'carta';

  /// Substitui [[oracleId]] pelos nomes das cartas.
  String logText(LogEntry e) =>
      e.text.replaceAllMapped(RegExp(r'\[\[([^\]]+)\]\]'), (m) => card(m.group(1))?.frontName ?? '?');

  PrivateZones zones(int seat) => table.zonesOf(seat);

  void draw([int n = 1]) => send(table.draw(actor, n));

  /// Terrenos anexados uns aos outros (para poupar espaço): a pilha toda,
  /// com o de cima primeiro. Uma carta que não está numa pilha de terrenos
  /// fica sozinha. Auras e equipamentos não contam: não viram com a criatura.
  List<CardInstance> landStack(CardInstance c) {
    bool land(CardInstance x) => card(x.oracleId)?.isLand ?? false;
    if (!land(c)) return [c];
    final host = c.attachedTo == null ? null : state.cards[c.attachedTo];
    final root = host != null && land(host) ? host : c;
    return [
      root,
      for (final x in state.cards.values)
        if (x.attachedTo == root.id && x.zone == Zone.battlefield && land(x)) x,
    ];
  }

  /// Virar ou desvirar. Num terreno de uma pilha de terrenos anexados, vira a
  /// pilha toda (a não ser com [single]).
  void toggleTap(CardInstance c, {bool single = false}) => send(Intent(Ev.tap, {
        'ids': [
          for (final x in single ? [c] : landStack(c)) x.id
        ],
        'value': !c.tapped
      }));

  void playFromHand(PrivateCard pc,
      {Zone to = Zone.battlefield,
      double? x,
      double? y,
      bool faceDown = false,
      String pos = 'top',
      bool cast = false}) {
    final placed = nextSpot(isLand: card(pc.oracleId)?.isLand ?? false);
    send(table.moveHidden(actor, Zone.hand, pc.pid, to,
        x: x ?? placed.$1, y: y ?? placed.$2, faceDown: faceDown, pos: pos, cast: cast));
  }

  void fromLibrary(PrivateCard pc, Zone to, {String pos = 'top'}) {
    final placed = nextSpot(isLand: card(pc.oracleId)?.isLand ?? false);
    send(table.moveHidden(actor, Zone.library, pc.pid, to, x: placed.$1, y: placed.$2, pos: pos));
  }

  void moveCard(CardInstance c, Zone to, {double? x, double? y, String pos = 'top'}) {
    if (to == Zone.battlefield && x == null) {
      final placed = nextSpot(isLand: card(c.oracleId)?.isLand ?? false);
      x = placed.$1;
      y = placed.$2;
    }
    send(table.movePublic(c.id, to, x: x, y: y, pos: pos));
  }

  /// Primeiro lugar livre numa grelha de 6 colunas: terrenos em baixo, o
  /// resto em cima, como numa mesa real.
  (double, double) nextSpot({bool isLand = false, int? seat}) {
    final who = seat ?? actor;
    final taken = state.cards.values
        .where((c) => c.zone == Zone.battlefield && c.controller == who && c.attachedTo == null)
        .map((c) => (c.x, c.y))
        .toList();
    bool free(double x, double y) => !taken.any((t) => (t.$1 - x).abs() < 0.1 && (t.$2 - y).abs() < 0.15);
    final rows = isLand ? const [1.0, 0.68] : const [0.0, 0.34, 0.5, 0.17];
    for (final y in rows) {
      for (var col = 0; col < 6; col++) {
        final x = col * 0.2;
        if (free(x, y)) return (x, y);
      }
    }
    // Tudo ocupado: empilha ligeiramente desviado.
    return (0.1 + (taken.length % 8) * 0.1, isLand ? 0.9 : 0.1);
  }

  void setPosition(CardInstance c, double x, double y) =>
      send(Intent(Ev.position, {'id': c.id, 'x': x.clamp(0.0, 1.0), 'y': y.clamp(0.0, 1.0)}));

  void counter(CardInstance c, String kind, int delta) =>
      send(Intent(Ev.counter, {'id': c.id, 'kind': kind, 'delta': delta}));

  /// Usa uma habilidade de lealdade: soma (ou tira) o custo à lealdade.
  void loyaltyAbility(CardInstance c, String cost, int delta) =>
      send(Intent(Ev.counter, {'id': c.id, 'kind': CounterKind.loyalty, 'delta': delta, 'ability': cost}));

  void life(int seat, int delta) => send(Intent(Ev.life, {'seat': seat, 'delta': delta}));

  void commanderDamage(int victim, int cmdId, int delta) =>
      send(Intent(Ev.commanderDamage, {'seat': victim, 'cmdId': cmdId, 'delta': delta}));

  void playerCounter(int seat, String kind, int delta) =>
      send(Intent(Ev.playerCounter, {'seat': seat, 'kind': kind, 'delta': delta}));

  void passTurn() => send(const Intent(Ev.passTurn, {}));

  void undo() {
    if (table.canUndo(actor)) send(table.undo());
  }

  bool get canUndo => table.canUndo(actor);

  void mulligan() {
    mulligans[actor] = (mulligans[actor] ?? 0) + 1;
    send(table.mulligan(actor));
  }

  void rollDie(int sides) => send(Intent(Ev.rollDie, {'sides': sides, 'value': 1 + Random().nextInt(sides)}));

  void flipCoin() => send(Intent(Ev.flipCoin, {'heads': Random().nextBool()}));

  void randomPlayer() {
    final seats = state.players.values.where((p) => !p.defeated).map((p) => p.seat).toList();
    send(Intent(Ev.randomPlayer, {'seat': seats[Random().nextInt(seats.length)]}));
  }

  void highlight(CardInstance? c) => send(Intent(Ev.highlight, {'id': c?.id}));

  /// Separa [n] tokens de uma pilha numa pilha nova, ao lado (para atacar
  /// só com alguns, por exemplo).
  void splitStack(CardInstance c, int n) {
    if (!c.isToken || n <= 0 || n >= c.stackQty) return;
    send(Intent(Ev.tokenQty, {'id': c.id, 'qty': c.stackQty - n}));
    send(table.createToken(actor,
        oracleId: c.oracleId,
        name: c.tokenName,
        pt: c.tokenPt,
        printId: c.printId,
        qty: n,
        x: (c.x + 0.12).clamp(0.0, 1.0),
        y: c.y));
  }

  void storm(int delta) => send(Intent(Ev.storm, {'delta': delta}));

  void dayNight(String? value) => send(Intent(Ev.dayNight, {'value': value}));

  /// Fim do jogo: todos os dispositivos guardam a partida no histórico.
  void gameOver(int? winner) => send(Intent(Ev.gameOver, {'winner': winner}));

  /// Tokens que as cartas do deck de [seat] criam.
  List<db.Card> deckTokens(int seat) {
    final deck = decks[seat];
    if (deck == null) return const [];
    final cards = repo.getMany(deck.entries.map((e) => e.oracleId)).values;
    return repo.tokensFor(cards);
  }
}
