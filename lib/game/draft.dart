import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/foundation.dart';
import 'package:mesa_protocol/mesa_protocol.dart';

import '../net/room_link.dart';
import '../l10n/l10n.dart';

/// Mensagens diretas do draft (fora do registo da sala: os packs são
/// privados de cada jogador).
abstract final class DraftMsg {
  /// Anfitrião -> jogador: o pack que tem à frente (ou nenhum, à espera).
  static const pack = 'd:draft_pack';

  /// Anfitrião -> todos: quem está à espera de quê.
  static const status = 'd:draft_status';

  /// Anfitrião -> jogador: as cartas que já escolheu (fim ou religação).
  static const pool = 'd:draft_pool';

  /// Jogador -> anfitrião: as cartas escolhidas.
  static const pick = 'd:draft_pick';

  /// Jogador -> anfitrião: "manda-me outra vez o meu pack e as escolhas".
  static const sync = 'd:draft_sync';
}

/// Uma carta concreta num draft (cada uma tem um id único na partida).
class DraftCard {
  const DraftCard(this.id, this.print, {this.foil = false});
  final int id;
  final db.BoosterPrint print;
  final bool foil;

  db.PackCard get pack => db.PackCard(print, foil: foil);

  Map<String, dynamic> toJson() => {
        'i': id,
        's': print.scryfallId,
        'o': print.oracleId,
        'r': print.rarity,
        'n': print.number,
        'e': print.setCode,
        if (foil) 'f': 1,
      };

  static DraftCard fromJson(Map<String, dynamic> j) => DraftCard(
        (j['i'] as num).toInt(),
        db.BoosterPrint(j['s'] as String, j['o'] as String, j['r'] as String? ?? 'C', j['n'] as String? ?? '',
            setCode: j['e'] as String? ?? ''),
        foil: j['f'] == 1,
      );
}

/// Regras escolhidas pelo anfitrião antes de começar.
class DraftConfig {
  const DraftConfig({
    required this.title,
    this.setCode,
    this.packs = 3,
    this.picks = 1,
    this.timer = 0,
    this.commander = false,
    required this.seats,
  });

  /// Commander draft: no fim monta-se um deck de 60 com comandante.
  final bool commander;

  /// Nome do set ou do cubo (para mostrar).
  final String title;
  final String? setCode;

  /// Boosters por jogador (rondas).
  final int packs;

  /// Cartas que cada um tira de cada vez (1, ou 2 no Pick-Two Draft).
  final int picks;

  /// Segundos por escolha (0 = sem temporizador).
  final int timer;

  /// Lugares à volta da mesa, pela ordem de passagem. `seat` null = bot.
  final List<({int? seat, String name})> seats;

  Map<String, dynamic> toJson() => {
        'title': title,
        if (setCode != null) 'set': setCode,
        'packs': packs,
        'picks': picks,
        'timer': timer,
        if (commander) 'cmd': true,
        'seats': [
          for (final s in seats) {'seat': s.seat, 'name': s.name},
        ],
      };

  static DraftConfig fromJson(Map<String, dynamic> j) => DraftConfig(
        title: j['title'] as String? ?? tr('Draft'),
        setCode: j['set'] as String?,
        packs: (j['packs'] as num?)?.toInt() ?? 3,
        picks: (j['picks'] as num?)?.toInt() ?? 1,
        timer: (j['timer'] as num?)?.toInt() ?? 0,
        commander: j['cmd'] == true,
        seats: [
          for (final s in (j['seats'] as List).cast<Map<String, dynamic>>())
            (seat: (s['seat'] as num?)?.toInt(), name: s['name'] as String),
        ],
      );
}

/// O draft em si, sem rede: packs a passar de lugar em lugar. Cada lugar
/// tem uma fila de packs à espera; escolhe do primeiro e passa o resto.
/// A 1.ª e 3.ª rondas passam para a esquerda (lugar seguinte), a 2.ª para a
/// direita.
class DraftEngine {
  DraftEngine({required this.packs, this.picks = 1})
      : seats = packs.first.length,
        queues = List.generate(packs.first.length, (_) => Queue<List<DraftCard>>()),
        pools = List.generate(packs.first.length, (_) => <DraftCard>[]);

  /// [ronda][lugar] -> cartas do booster.
  final List<List<List<DraftCard>>> packs;
  final int picks;
  final int seats;
  final List<Queue<List<DraftCard>>> queues;
  final List<List<DraftCard>> pools;
  int round = -1;
  int _left = 0;

  bool get finished => round >= packs.length;

  /// Para onde passa nesta ronda: +1 (esquerda) ou -1 (direita).
  int get direction => round.isEven ? 1 : -1;

  /// Pack à frente do lugar (null se estiver à espera).
  List<DraftCard>? current(int pos) => queues[pos].isEmpty ? null : queues[pos].first;

  /// Quantas cartas tem de tirar agora (no fim do pack pode ser menos).
  int picksNow(int pos) => min(picks, current(pos)?.length ?? 0);

  void start() => _nextRound();

  void _nextRound() {
    round++;
    if (finished) return;
    _left = 0;
    for (var p = 0; p < seats; p++) {
      final pack = [...packs[round][p]];
      _left += pack.length;
      queues[p].add(pack);
    }
  }

  /// O lugar [pos] tira as cartas [ids] do pack que tem à frente. Devolve os
  /// lugares cujo pack da frente mudou (para lhes avisar).
  Set<int> pick(int pos, List<int> ids) {
    final pack = current(pos);
    if (pack == null || ids.length != picksNow(pos)) return const {};
    final chosen = [for (final id in ids) pack.where((c) => c.id == id).firstOrNull];
    if (chosen.any((c) => c == null) || ids.toSet().length != ids.length) return const {};
    for (final c in chosen) {
      pack.remove(c);
      pools[pos].add(c!);
    }
    _left -= ids.length;
    queues[pos].removeFirst();
    final changed = {pos};
    if (pack.isNotEmpty) {
      final next = (pos + direction) % seats;
      final wasIdle = queues[next].isEmpty;
      queues[next].add(pack);
      if (wasIdle) changed.add(next);
    }
    if (_left == 0) {
      _nextRound();
      changed.addAll(List.generate(seats, (i) => i));
    }
    return changed;
  }
}

/// Bot simples: raridade primeiro, mais o [valueOf] de cada carta (remoção e
/// criaturas fazem os decks de Limited); depois das primeiras escolhas,
/// prefere as cores em que já está.
List<int> botPick(List<DraftCard> pack, List<DraftCard> pool, int n, int Function(String oracleId) colorsOf,
    {double Function(String oracleId)? valueOf}) {
  final counts = List.filled(5, 0);
  for (final c in pool) {
    final m = colorsOf(c.print.oracleId);
    for (var b = 0; b < 5; b++) {
      if (m & (1 << b) != 0) counts[b]++;
    }
  }
  final ranked = [for (var b = 0; b < 5; b++) b]..sort((a, b) => counts[b].compareTo(counts[a]));
  final mine = pool.length >= 4 ? (1 << ranked[0]) | (1 << ranked[1]) : 0x1f;
  double score(DraftCard c) {
    final m = colorsOf(c.print.oracleId);
    var s = c.print.rarityRank * 2.0 + 1 + (valueOf?.call(c.print.oracleId) ?? 0);
    if (m == 0) {
      s += 0.5; // incolor serve a qualquer deck
    } else if (m & ~mine == 0) {
      s += 3; // nas minhas cores
    } else if (m & mine != 0) {
      s += 1;
    } else if (pool.length >= 4) {
      s -= 4; // fora das cores: só uma mítica compensa
    }
    return s;
  }

  final sorted = [...pack]..sort((a, b) => score(b).compareTo(score(a)));
  return [for (final c in sorted.take(n)) c.id];
}

/// Corre o draft no anfitrião: gera os packs, recebe as escolhas, joga
/// pelos bots e pelo temporizador, e manda a cada um só o que é seu.
class DraftHost {
  DraftHost({
    required this.link,
    required this.config,
    required List<List<List<DraftCard>>> packs,
    required this.colorsOf,
    this.valueOf,
  }) : engine = DraftEngine(packs: packs, picks: config.picks) {
    _sub = link.direct.listen(_onDirect);
  }

  final RoomLink link;
  final DraftConfig config;
  final DraftEngine engine;
  final int Function(String oracleId) colorsOf;
  final double Function(String oracleId)? valueOf;
  late final StreamSubscription<Envelope> _sub;
  final Map<int, DateTime> _deadline = {};
  Timer? _clock;

  /// Lugar à mesa de um jogador da sala.
  int? posOf(int seat) {
    final i = config.seats.indexWhere((s) => s.seat == seat);
    return i < 0 ? null : i;
  }

  bool _isBot(int pos) => config.seats[pos].seat == null;

  void start() {
    engine.start();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _changed({for (var p = 0; p < engine.seats; p++) p});
  }

  void dispose() {
    _clock?.cancel();
    _sub.cancel();
  }

  void _onDirect(Envelope env) {
    final type = env.type;
    final seat = env.actor;
    final pos = posOf(seat);
    if (pos == null) return;
    final p = env.payload;
    switch (type) {
      case DraftMsg.pick:
        final ids = [for (final i in (p['ids'] as List)) (i as num).toInt()];
        _changed(engine.pick(pos, ids));
      case DraftMsg.sync:
        _sendPack(pos);
        _sendPool(pos);
        _sendStatus();
    }
  }

  void _changed(Set<int> positions) {
    if (positions.isEmpty) return;
    for (final pos in positions) {
      if (_isBot(pos)) {
        _botTurn(pos);
      } else {
        _setDeadline(pos);
        _sendPack(pos);
        if (engine.finished) _sendPool(pos);
      }
    }
    _sendStatus();
  }

  void _botTurn(int pos) {
    final pack = engine.current(pos);
    if (pack == null || engine.finished) return;
    // Um instante, para não parecer que os bots escolhem antes de abrir.
    Timer(const Duration(milliseconds: 350), () {
      if (engine.current(pos) != pack) return;
      _changed(engine.pick(pos, botPick(pack, engine.pools[pos], engine.picksNow(pos), colorsOf, valueOf: valueOf)));
    });
  }

  void _setDeadline(int pos) {
    final pack = engine.current(pos);
    if (config.timer <= 0 || pack == null) {
      _deadline.remove(pos);
      return;
    }
    _deadline[pos] = DateTime.now().add(Duration(seconds: config.timer));
  }

  /// Tempo esgotado: o anfitrião escolhe pelo jogador (como faria um bot).
  void _tick() {
    final now = DateTime.now();
    for (final MapEntry(key: pos, value: limit) in _deadline.entries.toList()) {
      final pack = engine.current(pos);
      if (pack == null || now.isBefore(limit)) continue;
      _deadline.remove(pos);
      _changed(engine.pick(pos, botPick(pack, engine.pools[pos], engine.picksNow(pos), colorsOf, valueOf: valueOf)));
      // O jogador não escolheu: tem de saber o que a app tirou por ele.
      _sendPool(pos);
    }
  }

  void _sendPack(int pos) {
    final seat = config.seats[pos].seat;
    if (seat == null) return;
    final pack = engine.current(pos);
    link.sendDirect(seat, DraftMsg.pack, {
      'round': engine.round,
      'finished': engine.finished,
      'picks': engine.picksNow(pos),
      'pick': engine.pools[pos].length + 1,
      if (pack != null) 'pack': [for (final c in pack) c.toJson()],
      if (_deadline[pos] != null) 'deadline': _deadline[pos]!.millisecondsSinceEpoch,
    });
  }

  void _sendPool(int pos) {
    final seat = config.seats[pos].seat;
    if (seat == null) return;
    link.sendDirect(seat, DraftMsg.pool, {
      'pool': [for (final c in engine.pools[pos]) c.toJson()],
    });
  }

  void _sendStatus() {
    final status = {
      'round': engine.round,
      'finished': engine.finished,
      'dir': engine.direction,
      'seats': [
        for (var p = 0; p < engine.seats; p++)
          {'waiting': engine.queues[p].length, 'picked': engine.pools[p].length},
      ],
    };
    for (final s in config.seats) {
      if (s.seat != null) link.sendDirect(s.seat!, DraftMsg.status, status);
    }
  }
}

/// O lado de cada jogador (também o do anfitrião): o pack à frente, as
/// escolhas já feitas e o estado da mesa.
class DraftClient extends ChangeNotifier {
  DraftClient({required this.link, required this.config}) {
    _sub = link.direct.listen(_onDirect);
    _status = link.statusChanges.listen((s) {
      // Ao voltar a ligar, os packs enviados entretanto perderam-se: pede-os.
      if (s == LinkStatus.connected) requestSync();
    });
    requestSync();
  }

  final RoomLink link;
  final DraftConfig config;
  late final StreamSubscription<Envelope> _sub;
  late final StreamSubscription<LinkStatus> _status;

  List<DraftCard>? pack;
  List<DraftCard> pool = [];
  int round = 0;
  int picks = 1;
  int pickNo = 1;
  bool finished = false;
  DateTime? deadline;
  int direction = 1;
  List<({int waiting, int picked})> seats = const [];

  void requestSync() => link.sendDirect(0, DraftMsg.sync, {});

  void _onDirect(Envelope env) {
    final p = env.payload;
    switch (env.type) {
      case DraftMsg.pack:
        round = (p['round'] as num).toInt();
        finished = p['finished'] == true;
        picks = (p['picks'] as num?)?.toInt() ?? 1;
        pickNo = (p['pick'] as num?)?.toInt() ?? 1;
        pack = p['pack'] == null
            ? null
            : [for (final c in (p['pack'] as List).cast<Map<String, dynamic>>()) DraftCard.fromJson(c)];
        final d = (p['deadline'] as num?)?.toInt();
        deadline = d == null ? null : DateTime.fromMillisecondsSinceEpoch(d);
      case DraftMsg.pool:
        pool = [for (final c in (p['pool'] as List).cast<Map<String, dynamic>>()) DraftCard.fromJson(c)];
      case DraftMsg.status:
        round = (p['round'] as num).toInt();
        finished = p['finished'] == true;
        direction = (p['dir'] as num?)?.toInt() ?? 1;
        seats = [
          for (final s in (p['seats'] as List).cast<Map<String, dynamic>>())
            (waiting: (s['waiting'] as num).toInt(), picked: (s['picked'] as num).toInt()),
        ];
      default:
        return;
    }
    notifyListeners();
  }

  /// Escolhe estas cartas do pack que está à frente.
  void choose(List<DraftCard> cards) {
    final p = pack;
    if (p == null || cards.length != picks) return;
    pool = [...pool, ...cards];
    pack = null;
    deadline = null;
    link.sendDirect(0, DraftMsg.pick, {
      'ids': [for (final c in cards) c.id]
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    _status.cancel();
    super.dispose();
  }
}

/// Gera os packs do draft: [rondas][lugares] boosters de um set, ou de um
/// cubo (lista de oracle ids com a impressão por defeito).
List<List<List<DraftCard>>> draftPacks({
  required int rounds,
  required int seats,
  db.SetBoosters? set,
  List<db.BoosterPrint>? cube,
  int cubePackSize = 15,
  Random? random,
}) {
  final rnd = random ?? Random();
  var next = 1;
  DraftCard card(db.PackCard c) => DraftCard(next++, c.print, foil: c.foil);
  if (set != null) {
    return [
      for (var r = 0; r < rounds; r++)
        [
          for (var s = 0; s < seats; s++) [for (final c in set.open(rnd)) card(c)],
        ],
    ];
  }
  final pool = [...cube!]..shuffle(rnd);
  var at = 0;
  return [
    for (var r = 0; r < rounds; r++)
      [
        for (var s = 0; s < seats; s++)
          [
            for (var i = 0; i < cubePackSize && at < pool.length; i++) card(db.PackCard(pool[at++])),
          ],
      ],
  ];
}
