import 'i18n.dart';

/// Zonas da mesa. Grimório e mão são ocultas: vivem só no dispositivo do dono.
enum Zone {
  library('library', 'Grimório', hidden: true),
  hand('hand', 'Mão', hidden: true),
  battlefield('battlefield', 'Campo'),
  graveyard('graveyard', 'Cemitério'),
  exile('exile', 'Exílio'),
  command('command', 'Zona de comando');

  const Zone(this.id, this._label, {this.hidden = false});
  final String id;
  final String _label;
  final bool hidden;

  /// O nome da zona na língua da app.
  String get label => mesaTr(_label);

  static Zone byId(String id) => values.firstWhere((z) => z.id == id);
}

/// Contadores de jogador além da vida.
abstract final class PlayerCounter {
  static const poison = 'poison';
  static const energy = 'energy';
  static const experience = 'experience';
  static const rad = 'rad';
  static const tickets = 'tickets';

  /// City's Blessing (1 = tem; não se perde).
  static const blessing = 'blessing';
}

/// Uma carta numa zona pública. O `id` é único na partida; o dono gera-o
/// (seat * 1 000 000 + contador) para não precisar de coordenação.
class CardInstance {
  CardInstance({
    required this.id,
    required this.oracleId,
    required this.owner,
    required this.controller,
    required this.zone,
    this.tapped = false,
    this.faceDown = false,
    this.faceIndex = 0,
    Map<String, int>? counters,
    this.attachedTo,
    this.x = 0.5,
    this.y = 0.5,
    this.stackQty = 1,
    this.isToken = false,
    this.isCommander = false,
    this.tokenName,
    this.tokenPt,
    this.order = 0,
    this.printId,
  }) : counters = counters ?? {};

  final int id;

  /// Carta da base; null num token personalizado sem carta.
  final String? oracleId;
  final int owner;
  int controller;
  Zone zone;
  bool tapped;
  bool faceDown;
  int faceIndex;
  final Map<String, int> counters;
  int? attachedTo;

  /// Posição no campo, de 0 a 1 em cada eixo.
  double x;
  double y;

  /// Tokens iguais empilhados mostram uma quantidade.
  int stackQty;
  final bool isToken;
  final bool isCommander;
  final String? tokenName;
  final String? tokenPt;

  /// Ordem dentro de cemitério, exílio e zona de comando (maior = topo).
  int order;

  /// Impressão (versão) escolhida pelo dono; null = a por defeito.
  final String? printId;

  CardInstance clone() => CardInstance(
        id: id,
        oracleId: oracleId,
        owner: owner,
        controller: controller,
        zone: zone,
        tapped: tapped,
        faceDown: faceDown,
        faceIndex: faceIndex,
        counters: Map.of(counters),
        attachedTo: attachedTo,
        x: x,
        y: y,
        stackQty: stackQty,
        isToken: isToken,
        isCommander: isCommander,
        tokenName: tokenName,
        tokenPt: tokenPt,
        order: order,
        printId: printId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'o': oracleId,
        'ow': owner,
        'c': controller,
        'z': zone.id,
        if (tapped) 't': 1,
        if (faceDown) 'fd': 1,
        if (faceIndex != 0) 'fi': faceIndex,
        if (counters.isNotEmpty) 'cn': counters,
        if (attachedTo != null) 'at': attachedTo,
        'x': x,
        'y': y,
        if (stackQty != 1) 'q': stackQty,
        if (isToken) 'tk': 1,
        if (isCommander) 'cmd': 1,
        if (tokenName != null) 'tn': tokenName,
        if (tokenPt != null) 'tp': tokenPt,
        'or': order,
        if (printId != null) 'p': printId,
      };

  static CardInstance fromJson(Map<String, dynamic> j) => CardInstance(
        id: j['id'] as int,
        oracleId: j['o'] as String?,
        owner: j['ow'] as int,
        controller: j['c'] as int,
        zone: Zone.byId(j['z'] as String),
        tapped: j['t'] == 1,
        faceDown: j['fd'] == 1,
        faceIndex: (j['fi'] as int?) ?? 0,
        counters: (j['cn'] as Map?)?.map((k, v) => MapEntry(k as String, (v as num).toInt())),
        attachedTo: j['at'] as int?,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        stackQty: (j['q'] as int?) ?? 1,
        isToken: j['tk'] == 1,
        isCommander: j['cmd'] == 1,
        tokenName: j['tn'] as String?,
        tokenPt: j['tp'] as String?,
        order: (j['or'] as int?) ?? 0,
        printId: j['p'] as String?,
      );
}

class PlayerState {
  PlayerState({
    required this.seat,
    required this.name,
    required this.life,
    Map<int, int>? commanderDamage,
    Map<int, int>? commanderCasts,
    Map<String, int>? counters,
    this.handCount = 0,
    this.libraryCount = 0,
    this.defeated = false,
  })  : commanderDamage = commanderDamage ?? {},
        commanderCasts = commanderCasts ?? {},
        counters = counters ?? {};

  final int seat;
  String name;
  int life;

  /// Dano sofrido por comandante adversário (id da instância -> dano).
  final Map<int, int> commanderDamage;

  /// Vezes que cada um dos meus comandantes saiu da zona de comando.
  final Map<int, int> commanderCasts;
  final Map<String, int> counters;
  int handCount;
  int libraryCount;
  bool defeated;

  int commanderTax(int commanderId) => 2 * (commanderCasts[commanderId] ?? 0);

  PlayerState clone() => PlayerState(
        seat: seat,
        name: name,
        life: life,
        commanderDamage: Map.of(commanderDamage),
        commanderCasts: Map.of(commanderCasts),
        counters: Map.of(counters),
        handCount: handCount,
        libraryCount: libraryCount,
        defeated: defeated,
      );

  Map<String, dynamic> toJson() => {
        'seat': seat,
        'name': name,
        'life': life,
        'cd': commanderDamage.map((k, v) => MapEntry('$k', v)),
        'cc': commanderCasts.map((k, v) => MapEntry('$k', v)),
        'cn': counters,
        'hc': handCount,
        'lc': libraryCount,
        if (defeated) 'd': 1,
      };

  static PlayerState fromJson(Map<String, dynamic> j) => PlayerState(
        seat: j['seat'] as int,
        name: j['name'] as String,
        life: j['life'] as int,
        commanderDamage: (j['cd'] as Map).map((k, v) => MapEntry(int.parse(k as String), (v as num).toInt())),
        commanderCasts: (j['cc'] as Map).map((k, v) => MapEntry(int.parse(k as String), (v as num).toInt())),
        counters: (j['cn'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())),
        handCount: j['hc'] as int,
        libraryCount: j['lc'] as int,
        defeated: j['d'] == 1,
      );
}

/// Uma carta numa zona oculta, conhecida só pelo dono.
/// O `pid` é local ao dono e não diz nada aos outros.
class PrivateCard {
  const PrivateCard(this.pid, this.oracleId, {this.isCommander = false, this.printId});
  final int pid;
  final String oracleId;
  final bool isCommander;
  final String? printId;

  Map<String, dynamic> toJson() =>
      {'p': pid, 'o': oracleId, if (isCommander) 'c': true, if (printId != null) 'r': printId};

  static PrivateCard fromJson(Map<String, dynamic> j) =>
      PrivateCard((j['p'] as num).toInt(), j['o'] as String,
          isCommander: j['c'] == true, printId: j['r'] as String?);
}

/// Mão e grimório de um jogador (só existem no dispositivo do dono).
class PrivateZones {
  PrivateZones({List<PrivateCard>? library, List<PrivateCard>? hand})
      : library = library ?? [],
        hand = hand ?? [];

  /// O índice 0 é o topo do grimório.
  final List<PrivateCard> library;
  final List<PrivateCard> hand;

  PrivateZones clone() => PrivateZones(library: [...library], hand: [...hand]);
}

class LogEntry {
  const LogEntry(this.seq, this.actor, this.type, this.text);
  final int seq;
  final int actor;
  final String type;

  /// Texto curto em português; nomes de cartas vêm em [[oracleId]] para a
  /// UI substituir pelo nome.
  final String text;
}

/// Estado público da mesa: igual em todos os dispositivos.
class GameState {
  GameState({
    required this.format,
    required this.players,
    Map<int, CardInstance>? cards,
    this.turn = 1,
    this.activeSeat = 0,
    this.phase = 'main1',
    this.seq = 0,
    this.monarch,
    this.initiative,
    List<LogEntry>? log,
    this.highlight,
    List<TargetMark>? targets,
    this.revealed,
    this.started = false,
    this.storm = 0,
    this.dayNight,
    this.over = false,
    this.winner,
  })  : cards = cards ?? {},
        log = log ?? [],
        targets = targets ?? [];

  final String format;
  final Map<int, PlayerState> players;
  final Map<int, CardInstance> cards;
  int turn;
  int activeSeat;
  String phase;
  int seq;
  int? monarch;
  int? initiative;
  final List<LogEntry> log;

  /// Carta destacada por alguém (id) — por exemplo para apontar um alvo.
  int? highlight;

  /// Alvos apontados (setas): para uma carta ou para um jogador.
  final List<TargetMark> targets;

  /// Cartas reveladas no último evento de revelação.
  Reveal? revealed;
  bool started;

  /// Feitiços lançados neste turno (storm); volta a 0 ao passar o turno.
  int storm;

  /// 'day', 'night' ou null (ainda não é dia nem noite).
  String? dayNight;

  /// O jogo terminou (com [winner], ou sem vencedor).
  bool over;
  int? winner;

  Iterable<CardInstance> zoneCards(int seat, Zone zone) {
    final list = cards.values
        .where((c) => c.zone == zone && (zone == Zone.battlefield ? c.controller : c.owner) == seat)
        .toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  int maxOrder() => cards.values.fold(0, (m, c) => c.order > m ? c.order : m);

  GameState clone() => GameState(
        format: format,
        players: {for (final e in players.entries) e.key: e.value.clone()},
        cards: {for (final e in cards.entries) e.key: e.value.clone()},
        turn: turn,
        activeSeat: activeSeat,
        phase: phase,
        seq: seq,
        monarch: monarch,
        initiative: initiative,
        log: [...log],
        highlight: highlight,
        targets: [...targets],
        revealed: revealed,
        started: started,
        storm: storm,
        dayNight: dayNight,
        over: over,
        winner: winner,
      );

  /// Estado público serializado (para reconexão).
  Map<String, dynamic> toJson() => {
        'format': format,
        'players': [for (final p in players.values) p.toJson()],
        'cards': [for (final c in cards.values) c.toJson()],
        'turn': turn,
        'active': activeSeat,
        'phase': phase,
        'seq': seq,
        'monarch': monarch,
        'initiative': initiative,
        'started': started,
        'storm': storm,
        'dayNight': dayNight,
        'over': over,
        'winner': winner,
      };

  static GameState fromJson(Map<String, dynamic> j) => GameState(
        format: j['format'] as String,
        players: {
          for (final p in (j['players'] as List).cast<Map<String, dynamic>>())
            p['seat'] as int: PlayerState.fromJson(p),
        },
        cards: {
          for (final c in (j['cards'] as List).cast<Map<String, dynamic>>())
            c['id'] as int: CardInstance.fromJson(c),
        },
        turn: j['turn'] as int,
        activeSeat: j['active'] as int,
        phase: j['phase'] as String,
        seq: j['seq'] as int,
        monarch: j['monarch'] as int?,
        initiative: j['initiative'] as int?,
        started: j['started'] == true,
        storm: j['storm'] as int? ?? 0,
        dayNight: j['dayNight'] as String?,
        over: j['over'] == true,
        winner: j['winner'] as int?,
      );
}

class Reveal {
  const Reveal(this.seat, this.oracleIds, this.what, {this.to});
  final int seat;
  final List<String> oracleIds;

  /// Ex.: "a mão", "o topo do grimório".
  final String what;

  /// Lugar a quem se revelou (null = todos).
  final int? to;
}

/// Um alvo apontado por um jogador: de uma carta (opcional) para uma carta
/// ou para um jogador.
class TargetMark {
  const TargetMark({required this.actor, this.from, this.card, this.seat});
  final int actor;
  final int? from;
  final int? card;
  final int? seat;
}

/// Contadores especiais guardados no mapa de contadores de uma carta.
abstract final class CounterKind {
  static const plus = '+1/+1';
  static const minus = '-1/-1';
  static const loyalty = 'loyalty';

  /// Modificadores de poder e resistência (podem ser negativos).
  static const modPower = 'mod:pow';
  static const modToughness = 'mod:tou';

  /// Prefixo de habilidades dadas à carta ("kw:Flying").
  static const keyword = 'kw:';

  static bool isSigned(String kind) => kind.startsWith('mod:');
}
