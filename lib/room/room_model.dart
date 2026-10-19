import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:mesa_protocol/mesa_protocol.dart';

import '../net/room_link.dart';
import '../l10n/l10n.dart';

class PlayerView {
  PlayerView({required this.seat, required this.name, this.isHost = false});
  final int seat;
  String name;
  bool isHost;
  bool connected = true;
}

/// Resultado de um teste de carga: quantos eventos chegaram e se chegaram
/// pela ordem em que foram enviados.
class BurstResult {
  BurstResult(this.actor, this.run, this.expected);
  final int actor;
  final int run;
  final int expected;
  int received = 0;
  bool inOrder = true;
  int firstSeq = 0;
  int lastSeq = 0;
  bool get done => received >= expected;
}

/// Estado público da sala, construído só a partir dos eventos ordenados.
/// Todos os dispositivos aplicam os mesmos eventos e chegam ao mesmo estado.
class RoomModel extends ChangeNotifier {
  RoomModel(this.link) {
    for (final e in link.history) {
      _apply(e);
    }
    _eventsSub = link.events.listen((e) {
      _apply(e);
      notifyListeners();
    });
    _statusSub = link.statusChanges.listen((_) => notifyListeners());
    // O RTT muda sem eventos; refresca o ecrã de vez em quando.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
  }

  final RoomLink link;
  late final StreamSubscription<Envelope> _eventsSub;
  late final StreamSubscription<LinkStatus> _statusSub;
  late final Timer _tick;

  final SplayTreeMap<int, PlayerView> players = SplayTreeMap();
  final List<Envelope> log = [];
  final Map<String, BurstResult> bursts = {};
  int _burstRun = 0;

  int get lastSeq => log.isEmpty ? 0 : log.last.seq;
  int get mySeat => link.mySeat;

  String nameOf(int seat) =>
      seat < 0 ? tr('Sala') : players[seat]?.name ?? tr('Jogador {seat}', {'seat': seat});

  void _apply(Envelope e) {
    log.add(e);
    final p = e.payload;
    switch (e.type) {
      case MsgType.join:
        final seat = (p['seat'] as num).toInt();
        players[seat] = PlayerView(
          seat: seat,
          name: p['name'] as String? ?? tr('Jogador {seat}', {'seat': seat}),
          isHost: p['host'] == true,
        );
      case MsgType.leave:
        players.remove((p['seat'] as num).toInt());
      case MsgType.playerStatus:
        players[(p['seat'] as num).toInt()]?.connected = p['connected'] == true;
      case MsgType.burst:
        final run = (p['run'] as num?)?.toInt() ?? 0;
        final key = '${e.actor}:$run';
        final r = bursts.putIfAbsent(
            key, () => BurstResult(e.actor, run, (p['n'] as num?)?.toInt() ?? 0)..firstSeq = e.seq);
        final i = (p['i'] as num?)?.toInt() ?? -1;
        if (i != r.received) r.inOrder = false;
        r.received++;
        r.lastSeq = e.seq;
    }
  }

  void ping() => link.submit(MsgType.ping);

  void rollDie(int sides) {
    final value = 1 + (DateTime.now().microsecondsSinceEpoch % sides);
    link.submit(MsgType.rollDie, {'sides': sides, 'value': value});
  }

  void flipCoin() => link.submit(MsgType.flipCoin, {'heads': DateTime.now().microsecondsSinceEpoch.isEven});

  /// Envia [n] eventos seguidos para medir ordem e débito.
  void sendBurst(int n) {
    final run = DateTime.now().millisecondsSinceEpoch ~/ 1000 * 10 + (_burstRun++ % 10);
    for (var i = 0; i < n; i++) {
      link.submit(MsgType.burst, {'run': run, 'i': i, 'n': n});
    }
  }

  /// Texto legível de um evento, para o registo.
  String describe(Envelope e) {
    final p = e.payload;
    final who = nameOf(e.actor);
    return switch (e.type) {
      MsgType.join => p['host'] == true
          ? tr('{v} criou a sala', {'v': p['name']})
          : tr('{v} entrou (lugar {v2})', {'v': p['name'], 'v2': p['seat']}),
      MsgType.leave => tr('{v} saiu', {'v': nameOf((p['seat'] as num).toInt())}),
      MsgType.playerStatus => p['connected'] == true
          ? tr('{v} voltou a ligar-se', {'v': nameOf((p['seat'] as num).toInt())})
          : tr('{v} perdeu a ligação', {'v': nameOf((p['seat'] as num).toInt())}),
      MsgType.ping => tr('{who}: ping', {'who': who}),
      MsgType.rollDie => tr('{who} lançou um d{v}: {v2}', {'who': who, 'v': p['sides'], 'v2': p['value']}),
      MsgType.flipCoin =>
        tr('{who} lançou a moeda: {v}', {'who': who, 'v': p['heads'] == true ? tr('cara') : tr('coroa')}),
      MsgType.burst => tr('{who}: carga {v}/{v2}', {'who': who, 'v': (p['i'] as num) + 1, 'v2': p['n']}),
      _ => '$who: ${e.type}',
    };
  }

  @override
  void dispose() {
    _eventsSub.cancel();
    _statusSub.cancel();
    _tick.cancel();
    super.dispose();
  }
}
