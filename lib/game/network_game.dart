import 'dart:async';
import 'dart:convert';
import 'dart:collection';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/foundation.dart';
import 'package:mesa_core/mesa_core.dart';
import 'package:mesa_protocol/mesa_protocol.dart';

import '../data/image_service.dart';
import '../data/print_service.dart';
import '../net/host_server.dart';
import '../net/room_client.dart';
import '../net/room_link.dart';
import '../room/room_session.dart';
import 'draft.dart';
import 'game_controller.dart';
import 'match.dart';
import 'resume_store.dart';
import '../l10n/l10n.dart';

/// Eventos do lobby (antes do jogo começar).
abstract final class LobbyEv {
  /// Anfitrião: formato, vida inicial e lugares.
  static const config = 'lobby_config';

  /// Jogador: deck escolhido (só nome, tamanho e legalidade).
  static const deckSelected = 'deck_selected';
  static const ready = 'ready';

  /// Anfitrião: volta todos ao lobby para outra partida.
  static const newGame = 'new_game';

  /// Anfitrião: começa um draft com estas regras (os packs vão em privado).
  static const draftStart = 'draft_start';

  /// Anfitrião: formatos 1 contra 1, as rondas do torneio ([MatchPlan]).
  static const matchStart = 'match_start';

  /// Jogador: quer o próximo jogo do encontro da mesa `tbl`.
  static const nextGame = 'match_next_game';

  /// Anfitrião: passa à ronda seguinte do torneio.
  static const nextRound = 'match_next_round';
}

/// Um jogo de um encontro 1 contra 1: a mesa `tbl` da ronda [round].
class MatchTable {
  MatchTable(this.round, this.a, this.b, this.game, this.first);
  final int round, a, b, game, first;
}

/// Eventos da camada de sala que não são da mesa.
const _roomOnly = {
  MsgType.join,
  MsgType.leave,
  MsgType.playerStatus,
  MsgType.ping,
  MsgType.burst,
  LobbyEv.config,
  LobbyEv.deckSelected,
  LobbyEv.ready,
  LobbyEv.newGame,
  LobbyEv.draftStart,
  LobbyEv.matchStart,
  LobbyEv.nextGame,
  LobbyEv.nextRound,
};

class LobbyPlayer {
  LobbyPlayer(this.seat, this.name, {this.isHost = false});
  final int seat;
  String name;
  final bool isHost;
  bool connected = true;
  String? deckName;
  int deckSize = 0;
  bool deckLegal = false;
  List<String> commanders = const [];
  bool ready = false;

  /// Game Changers no deck (para o bracket, na conversa da regra zero).
  int? gameChangers;

  /// Imagens (pequenas) das cartas do deck deste jogador, com as versões
  /// que ele escolheu.
  List<db.ImageRef> images = const [];
}

/// Transferência de imagens de outro jogador pela rede local.
class ImageTransfer {
  ImageTransfer(this.seat, this.expected);
  final int seat;
  final int expected;
  int received = 0;
  bool get done => received >= expected;
}

/// Tipos das mensagens diretas de imagens.
abstract final class AssetMsg {
  static const request = 'd:img_req';
  static const data = 'd:img_data';
}

/// Tamanho médio de uma imagem pequena (para estimar MB).
const smallImageBytes = 15 * 1024;

/// Uma partida em rede: lobby e depois a mesa, sobre a sala da Fase 0.
///
/// Todos os eventos passam pelo anfitrião, que lhes dá um `seq`. Cada
/// dispositivo aplica-os pela mesma ordem; a mão e o grimório de cada
/// jogador só existem no dispositivo dele.
class NetworkGame extends ChangeNotifier {
  NetworkGame({
    required this.session,
    required this.repo,
    this.prints,
    this.images,
    this.resume,
    this.resumeStore,
    db.Deck? resumeDeck,
  }) {
    if (resume != null) myDeck = resumeDeck;
    _inHistory = true;
    for (final e in session.link.history) {
      _onEvent(e);
    }
    _inHistory = false;
    _sub = session.link.events.listen((e) {
      _onEvent(e);
      notifyListeners();
    });
    _statusSub = session.link.statusChanges.listen((_) => notifyListeners());
    _directSub = session.link.direct.listen(_onDirect);
  }

  final RoomSession session;
  final db.CardRepository repo;

  /// Versões e imagens (para mostrar as artes escolhidas e partilhá-las).
  final PrintService? prints;
  final ImageService? images;

  /// Ao voltar a um jogo depois de a app fechar: o que ficou guardado.
  final ResumeInfo? resume;
  final ResumeStore? resumeStore;
  bool _restored = false;

  /// Os eventos até [ResumeInfo.seq] já foram aplicados antes da app fechar:
  /// ao repeti-los não se volta a comprar, a carregar o deck, etc.
  bool _replaying(Envelope e) => resume != null && e.seq <= resume!.seq;
  late final StreamSubscription<Envelope> _sub;
  late final StreamSubscription<LinkStatus> _statusSub;
  late final StreamSubscription<Envelope> _directSub;

  /// Transferência em curso (imagens pedidas a outro dispositivo).
  ImageTransfer? transfer;
  int? downloadingFrom;

  final SplayTreeMap<int, LobbyPlayer> players = SplayTreeMap();
  String format = 'commander';
  int startingLife = 40;
  int maxSeats = 4;

  /// O meu deck escolhido (fica neste dispositivo).
  db.Deck? myDeck;

  /// Criado quando o jogo começa.
  GameController? game;

  /// Draft em curso (ou acabado): as regras, o meu lado e, no anfitrião,
  /// quem o corre.
  DraftConfig? draft;
  DraftClient? draftClient;
  DraftHost? draftHost;

  /// Estou sentado neste draft?
  bool get inDraft => draft?.seats.any((s) => s.seat == mySeat) ?? false;
  bool get started => game != null;

  /// A repetir o histórico da sala (ao entrar ou voltar): o anfitrião não
  /// volta a agir sobre pedidos antigos.
  bool _inHistory = false;

  /// Formatos sem zona de comando jogam-se 1 contra 1, em encontros.
  bool get oneVsOne => !db.GameFormat.byId(format).hasCommandZone;

  /// Torneio em curso (formatos 1 contra 1) e os jogos de cada mesa.
  Tournament? tournament;
  final Map<int, MatchTable> tables = {};

  /// A mesa em que estou sentado agora (null no Commander: há só uma).
  int? myTable;
  int _tblSeq = 0;

  MatchTable? get myTableInfo => tables[myTable];

  /// O meu encontro na ronda atual (null com folga ou sem torneio).
  MatchResult? get myMatch => tournament?.matchOf(tournament!.round, mySeat);

  RoomLink get link => session.link;
  int get mySeat => link.mySeat;
  bool get isHost => session.isHost;
  LobbyPlayer? get me => players[mySeat];

  bool get allReady => players.values.where((p) => p.connected).every((p) => p.ready) && players.isNotEmpty;

  void _onEvent(Envelope e) {
    final p = e.payload;
    int seat() => (p['seat'] as num).toInt();
    switch (e.type) {
      case MsgType.join:
        players[seat()] = LobbyPlayer(seat(), p['name'] as String? ?? tr('Jogador'), isHost: p['host'] == true);
      case MsgType.leave:
        players.remove(seat());
      case MsgType.playerStatus:
        players[seat()]?.connected = p['connected'] == true;
        _syncOffline();
      case LobbyEv.config:
        format = p['format'] as String;
        startingLife = (p['life'] as num).toInt();
        maxSeats = (p['seats'] as num?)?.toInt() ?? maxSeats;
        // Mudar o formato obriga a escolher/validar de novo.
        for (final pl in players.values) {
          pl.ready = false;
        }
      case LobbyEv.deckSelected:
        final pl = players[seat()];
        if (pl != null) {
          pl
            ..deckName = p['name'] as String?
            ..deckSize = (p['size'] as num?)?.toInt() ?? 0
            ..deckLegal = p['legal'] == true
            ..commanders = (p['commanders'] as List? ?? const []).cast<String>()
            ..gameChangers = (p['gc'] as num?)?.toInt()
            ..ready = false
            ..images = [
              for (final r in (p['images'] as List? ?? const []).cast<Map<String, dynamic>>())
                db.ImageRef(r['k'] as String, r['s'] as String?, r['n'] as String?),
            ];
        }
        // Guarda as versões que o outro jogador usa, para as mostrar.
        prints?.remember([
          for (final j in (p['prints'] as List? ?? const []).cast<Map<String, dynamic>>()) db.PrintInfo.fromJson(j),
        ]);
      case LobbyEv.ready:
        players[seat()]?.ready = p['value'] == true;
      case LobbyEv.draftStart:
        // Um draft novo começa outra partida: os encontros anteriores ficam para trás.
        tournament = null;
        tables.clear();
        _counted.clear();
        myTable = null;
        game?.dispose();
        game = null;
        draft = DraftConfig.fromJson(p);
        draftClient?.dispose();
        // O lobby mostra o estado do draft (terminado ou não).
        draftClient = inDraft ? (DraftClient(link: link, config: draft!)..addListener(notifyListeners)) : null;
      case LobbyEv.matchStart:
        tournament = Tournament(MatchPlan.fromJson(p));
        tables.clear();
        _counted.clear();
        myTable = null;
      case LobbyEv.nextRound:
        final t = tournament;
        if (t != null && t.round < t.roundCount - 1) t.round++;
      case LobbyEv.nextGame:
        if (isHost && !_inHistory) _startNextGame((p['tbl'] as num).toInt());
      case LobbyEv.newGame:
        tournament = null;
        tables.clear();
        _counted.clear();
        myTable = null;
        game?.dispose();
        game = null;
        _pending.clear();
        _restored = true;
        for (final pl in players.values) {
          pl.ready = false;
        }
        resumeStore?.clear();
    }

    if (_roomOnly.contains(e.type)) return;
    // Encontros 1 contra 1: cada mesa tem os seus eventos; só aplico os da minha.
    final tbl = (p['tbl'] as num?)?.toInt();
    if (tbl != null) {
      // Cada entrada na mesa diz quem lá se senta: a do adversário pode chegar antes da minha.
      final seats = (p['seats'] as List? ?? const []).cast<num>().map((n) => n.toInt());
      if (e.type == Ev.joinTable && seats.contains(mySeat) && tbl != myTable) {
        // Encontro novo (outra ronda): o sideboard do anterior desfaz-se.
        if ((p['round'] as num?)?.toInt() != tables[myTable]?.round) _restoreDeck();
        myTable = tbl;
        game?.dispose();
        game = null;
        _pending.clear();
      }
      if (e.type == Ev.startGame) {
        int i(String k) => (p[k] as num).toInt();
        tables[tbl] = MatchTable(i('round'), i('a'), i('b'), i('game'), i('first'));
      }
      if (e.type == Ev.gameOver) _recordGame(tbl, (p['winner'] as num?)?.toInt());
      if (tbl != myTable) return;
    }
    if (e.type == Ev.startGame && game == null) _createGame();
    final g = game;
    if (g == null) {
      // Eventos de mesa antes do start (join_table) são guardados para
      // aplicar quando o jogo for criado.
      if (e.type == Ev.joinTable) _pending.add(e);
      return;
    }
    g.applyRemote(e.seq, e.type, e.actor, e.payload);
    final r = resume;
    if (r != null && !_restored && e.seq >= r.seq) {
      // Cheguei ao ponto em que a app fechou: repõe a minha mão e grimório.
      final priv = r.private;
      if (priv != null) g.table.importPrivate(mySeat, priv);
      _restored = true;
    }
    if (!_replaying(e)) _afterGameEvent(e);
    _saveResume(e);
  }

  /// Guarda o necessário para voltar a este jogo se a app fechar.
  /// O fim de um jogo conta para o encontro (uma vez por mesa).
  final Set<int> _counted = {};
  void _recordGame(int tbl, int? winner) {
    final info = tables[tbl];
    final m = info == null ? null : tournament?.matchOf(info.round, info.a);
    if (m == null || m.done || !_counted.add(tbl)) return;
    m.games.add(winner);
  }

  void _saveResume(Envelope e) {
    final store = resumeStore;
    final g = game;
    if (store == null || g == null || _replaying(e)) return;
    if (!g.state.players.containsKey(mySeat)) return;
    if (g.state.over || link.status == LinkStatus.closed) {
      store.clear();
      return;
    }
    final private = g.table.localSeats.contains(mySeat) ? g.table.exportPrivate(mySeat) : null;
    switch (link) {
      case RoomClient client when client.token != null:
        store.save(ResumeInfo(
          room: session.roomName,
          hosts: [if (client.connectedHost != null) client.connectedHost!, ...client.hosts],
          port: client.port,
          pin: client.pin,
          token: client.token!,
          seat: mySeat,
          name: client.playerName,
          deckId: myDeck?.id,
          seq: e.seq,
          private: private,
          savedAt: DateTime.now(),
        ));
      // O anfitrião também volta: a sala reabre a partir do diário.
      case HostServer host when host.journalPath != null:
        store.save(ResumeInfo(
          room: session.roomName,
          hosts: const [],
          port: host.port,
          pin: host.pin,
          token: '',
          seat: mySeat,
          name: host.hostName,
          deckId: myDeck?.id,
          seq: e.seq,
          private: private,
          savedAt: DateTime.now(),
          journal: host.journalPath,
        ));
    }
  }

  /// Os lugares desligados aparecem marcados na mesa.
  void _syncOffline() {
    final g = game;
    if (g == null) return;
    g.offline
      ..clear()
      ..addAll([
        for (final p in players.values)
          if (!p.connected) p.seat
      ]);
  }

  final List<Envelope> _pending = [];

  void _createGame() {
    // A voltar a um jogo: até ao ponto guardado vejo-me como os outros me
    // veem; a mão e o grimório são repostos a seguir.
    final restoring = resume?.private != null && !_restored;
    final table = Table(format: format, localSeats: restoring ? {} : {mySeat});
    final g = GameController(
      table: table,
      repo: repo,
      mySeats: {mySeat},
      viewSeat: mySeat,
      isNetwork: true,
      decks: {if (myDeck != null) mySeat: myDeck!},
    );
    g.networkSend = (_, intent) => _submitGame(intent.type, intent.payload);
    final ps = prints;
    if (ps != null) {
      g
        ..resolvePrint = ((c, p) => ps.resolve(c, printId: p))
        ..effectivePrint = ps.effectivePrint;
    }
    for (final e in _pending) {
      g.applyRemote(e.seq, e.type, e.actor, e.payload);
    }
    _pending.clear();
    game = g;
    _syncOffline();
  }

  void _afterGameEvent(Envelope e) {
    final g = game!;
    // Quando o jogo começa, cada um baralha o seu deck; quando o meu deck
    // está carregado, compro a mão inicial.
    if (e.type == Ev.startGame && players.containsKey(mySeat) && myDeck != null) {
      _submitGame(Ev.deckLoaded, g.deckIntent(mySeat, myDeck!).payload);
    }
    if (e.type == Ev.deckLoaded && e.actor == mySeat) {
      final n = g.state.players[mySeat]?.libraryCount ?? 0;
      _submitGame(Ev.draw, g.table.draw(mySeat, n < 7 ? n : 7).payload);
    }
  }

  /// Os eventos de mesa levam a mesa a que pertencem (nos encontros 1 contra 1).
  void _submitGame(String type, Map<String, dynamic> payload) =>
      link.submit(type, {...payload, if (myTable != null) 'tbl': myTable});

  // ---------------------------------------------------------------------
  // Ações do lobby
  // ---------------------------------------------------------------------

  void configure({required String format, required int life, int? seats}) {
    if (!isHost) return;
    link.submit(LobbyEv.config, {'format': format, 'life': life, 'seats': seats ?? maxSeats});
  }

  void selectDeck(db.Deck deck, {required bool legal, required List<String> commanderNames, int? gameChangers}) {
    myDeck = deck;
    // As versões e imagens do deck, para os outros saberem o que lhes falta.
    final usedPrints = <String, db.PrintInfo>{};
    final refs = <String, db.ImageRef>{};
    for (final e in deck.entries.where((e) => e.board == db.Board.main || e.board == db.Board.command)) {
      final base = repo.get(e.oracleId);
      if (base == null) continue;
      final ps = prints;
      final eff = ps?.effectivePrint(e.oracleId, e.printId) ?? e.printId;
      final info = eff == null ? null : ps?.info(eff);
      if (info != null) usedPrints[info.printId] = info;
      final shown = info == null ? base : base.withPrint(info);
      for (final r in db.ImageRef.allOf(shown)) {
        refs[r.key] = r;
      }
    }
    link.submit(LobbyEv.deckSelected, {
      'seat': mySeat,
      'name': deck.name,
      'size': deck.playableCount,
      'legal': legal,
      'commanders': commanderNames,
      if (gameChangers != null) 'gc': gameChangers,
      'prints': [for (final p in usedPrints.values) p.toJson()],
      'images': [
        for (final r in refs.values)
          {'k': r.key, if (r.small != null) 's': r.small, if (r.normal != null) 'n': r.normal},
      ],
    });
    notifyListeners();
  }

  /// Imagens do deck de [seat] que este dispositivo ainda não tem.
  List<db.ImageRef> missingFrom(int seat) {
    final imgs = images;
    final pl = players[seat];
    if (imgs == null || pl == null || seat == mySeat) return const [];
    return [
      for (final r in pl.images)
        if (!imgs.has('small', r.key)) r
    ];
  }

  /// Total em falta de todos os outros jogadores.
  int get missingTotal => [for (final s in players.keys) missingFrom(s).length].fold(0, (a, b) => a + b);

  /// Descarrega o que falta do deck de [seat]: primeiro da internet; o que
  /// não conseguir (sem rede), pede ao dispositivo desse jogador.
  Future<void> downloadMissing(int seat) async {
    final imgs = images;
    if (imgs == null || downloadingFrom != null) return;
    final missing = missingFrom(seat);
    if (missing.isEmpty) return;
    downloadingFrom = seat;
    notifyListeners();
    try {
      final failed = await imgs.ensureRefs(missing, sizes: const ['small']);
      if (failed.isNotEmpty) {
        transfer = ImageTransfer(seat, failed.length);
        link.sendDirect(seat, AssetMsg.request, {
          'size': 'small',
          'keys': [for (final r in failed) r.key],
        });
      }
    } finally {
      downloadingFrom = null;
      notifyListeners();
    }
  }

  Future<void> _onDirect(Envelope e) async {
    final imgs = images;
    if (imgs == null) return;
    switch (e.type) {
      case AssetMsg.request:
        // Outro jogador pede imagens que este dispositivo tem: envia-as uma a uma.
        final size = e.payload['size'] as String? ?? 'small';
        for (final key in (e.payload['keys'] as List).cast<String>().take(400)) {
          final bytes = await imgs.readBytes(size, key);
          link.sendDirect(e.actor, AssetMsg.data, {
            'size': size,
            'key': key,
            if (bytes != null) 'data': base64Encode(bytes),
          });
        }
      case AssetMsg.data:
        final data = e.payload['data'] as String?;
        if (data != null) {
          await imgs.writeBytes(
              e.payload['size'] as String? ?? 'small', e.payload['key'] as String, base64Decode(data));
        }
        final t = transfer;
        if (t != null && t.seat == e.actor) {
          t.received++;
          if (t.done) transfer = null;
        }
        notifyListeners();
    }
  }

  /// Anfitrião: começa um draft. Os packs são gerados aqui e só cada
  /// jogador vê o seu.
  void startDraft(DraftConfig config, List<List<List<DraftCard>>> packs) {
    if (!isHost) return;
    draftHost?.dispose();
    draftHost = DraftHost(
      link: link,
      config: config,
      packs: packs,
      colorsOf: (o) => repo.get(o)?.colorMask ?? 0,
      valueOf: (o) => switch (repo.get(o)) { final c? => db.CardRoles.limitedValue(c), _ => 0.0 },
    )..start();
    // Os decks de draft jogam-se em Limited (40 cartas, vida 20), ou em
    // Commander draft (60 cartas com comandante, vida 40).
    if (config.commander) {
      configure(format: 'commanderdraft', life: 40);
    } else {
      configure(format: 'limited', life: 20);
    }
    link.submit(LobbyEv.draftStart, config.toJson());
  }

  // ---------------------------------------------------------------------
  // Encontros 1 contra 1
  // ---------------------------------------------------------------------

  /// Anfitrião: quem está pronto entra num torneio todos-contra-todos, cada
  /// encontro à melhor de 3. Com 2 pessoas é um só encontro.
  void startMatches() {
    if (!isHost || tournament != null) return;
    final seated = [
      for (final p in players.values)
        if (p.connected && p.ready) p.seat
    ];
    if (seated.length < 2) return;
    final plan = MatchPlan.roundRobin(seated);
    link.submit(LobbyEv.matchStart, plan.toJson());
    _startRound(plan, 0);
  }

  void _startRound(MatchPlan plan, int round) {
    final coin = DateTime.now().microsecondsSinceEpoch;
    var i = 0;
    for (final (a, b) in plan.rounds[round]) {
      _startTable(round, a, b, 1, (coin >> i++).isEven ? a : b);
    }
  }

  void _startTable(int round, int a, int b, int gameNo, int first) {
    final tbl = _tblSeq = [_tblSeq, ...tables.keys].fold(0, (m, k) => k > m ? k : m) + 1;
    for (final s in [a, b]) {
      link.submit(Ev.joinTable, {
        'seat': s,
        'name': players[s]?.name ?? '?',
        'life': startingLife,
        'tbl': tbl,
        'seats': [a, b],
        'round': round,
      });
    }
    link.submit(Ev.startGame, {'first': first, 'tbl': tbl, 'round': round, 'a': a, 'b': b, 'game': gameNo});
  }

  /// Anfitrião: o jogo seguinte do encontro da mesa [tbl]. Começa quem
  /// perdeu o anterior (num empate, quem não começou).
  void _startNextGame(int tbl) {
    final info = tables[tbl];
    final m = info == null ? null : tournament?.matchOf(info.round, info.a);
    if (info == null || m == null || m.done || m.games.length < info.game) return;
    // Já começou (os dois pediram).
    if (tables.values.any((t) => t.round == info.round && t.a == info.a && t.game > info.game)) return;
    final w = m.games.last;
    final first = w == null ? (info.first == info.a ? info.b : info.a) : m.other(w);
    _startTable(info.round, info.a, info.b, info.game + 1, first);
  }

  /// Jogador: acabou o jogo da minha mesa, quero o seguinte do encontro.
  void requestNextGame() {
    final tbl = myTable;
    if (tbl != null) link.submit(LobbyEv.nextGame, {'tbl': tbl});
  }

  /// Anfitrião: todos os encontros da ronda acabaram; começa a seguinte.
  void startNextRound() {
    final t = tournament;
    if (!isHost || t == null || !t.roundDone(t.round) || t.round >= t.roundCount - 1) return;
    link.submit(LobbyEv.nextRound, {});
    _startRound(t.plan, t.round + 1);
  }

  /// O deck como estava antes do sideboard deste encontro.
  db.Deck? _deckBeforeSide;

  /// Entre jogos do encontro: o deck com as trocas do sideboard (só para este encontro).
  void sideboard(db.Deck deck) {
    _deckBeforeSide ??= myDeck;
    myDeck = deck;
  }

  void _restoreDeck() {
    if (_deckBeforeSide case final d?) myDeck = d;
    _deckBeforeSide = null;
  }

  /// O meu encontro acabou: deixo a mesa e volto à sala (onde está a classificação).
  void backToRoom() {
    _restoreDeck();
    game?.dispose();
    game = null;
    notifyListeners();
  }

  /// Anfitrião: volta todos ao lobby para outra partida.
  void newGame() {
    if (isHost) link.submit(LobbyEv.newGame, {});
  }

  /// Sair de vez: deixa de haver jogo a que voltar.
  void forgetResume() => resumeStore?.clear();

  void setReady(bool value) {
    if (myDeck == null) return;
    link.submit(LobbyEv.ready, {'seat': mySeat, 'value': value});
  }

  /// Anfitrião: senta os jogadores e começa.
  void start({bool randomFirst = true}) {
    if (!isHost || started) return;
    final host = link as HostServer;
    final seated = players.values.where((p) => p.connected && p.ready).toList();
    for (final p in seated) {
      host.submit(Ev.joinTable, {'seat': p.seat, 'name': p.name, 'life': startingLife});
    }
    final first = randomFirst ? seated[DateTime.now().microsecondsSinceEpoch % seated.length].seat : seated.first.seat;
    host.submit(Ev.startGame, {'first': first});
  }

  @override
  void dispose() {
    _sub.cancel();
    _statusSub.cancel();
    _directSub.cancel();
    game?.dispose();
    draftClient?.dispose();
    draftHost?.dispose();
    super.dispose();
  }
}
