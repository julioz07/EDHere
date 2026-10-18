import 'dart:convert';
import 'dart:math';

import 'package:mesa_core/mesa_core.dart';
import 'package:test/test.dart';

/// Voltar a um jogo depois de a app fechar: o dispositivo repete o registo
/// como se fosse um observador e depois repõe a mão e o grimório guardados.
void main() {
  test('repetir o registo e repor as zonas ocultas dá o mesmo estado', () {
    final a = Table(format: 'commander', localSeats: {0}, random: Random(1));
    final b = Table(format: 'commander', localSeats: {1}, random: Random(2));
    final log = <(int, String, int, Map<String, dynamic>)>[];
    var seq = 0;
    void send(int actor, Intent i) {
      final p = jsonDecode(jsonEncode(i.payload)) as Map<String, dynamic>;
      seq++;
      log.add((seq, i.type, actor, p));
      a.apply(seq, i.type, actor, p);
      b.apply(seq, i.type, actor, p);
    }

    send(0, const Intent(Ev.joinTable, {'seat': 0, 'name': 'Ana', 'life': 40}));
    send(1, const Intent(Ev.joinTable, {'seat': 1, 'name': 'Rui', 'life': 40}));
    send(0, a.loadDeck(0, [for (var i = 0; i < 60; i++) 'a$i'], ['cmdA']));
    send(1, b.loadDeck(1, [for (var i = 0; i < 60; i++) 'b$i'], ['cmdB']));
    send(0, const Intent(Ev.startGame, {'first': 1}));
    send(1, b.draw(1, 7));
    final played = b.private[1]!.hand.first;
    send(1, b.moveHidden(1, Zone.hand, played.pid, Zone.battlefield, x: .2, y: .2));
    send(1, b.createToken(1, name: 'Goblin', pt: '1/1', qty: 3));

    // B guarda as zonas ocultas e a app fecha.
    final saved = jsonDecode(jsonEncode(b.exportPrivate(1))) as Map<String, dynamic>;
    final savedSeq = seq;

    // Entretanto A continua a jogar.
    send(0, a.draw(0, 7));
    send(0, const Intent(Ev.storm, {'delta': 2}));

    // B volta: repete o registo sem zonas locais e repõe a mão no ponto guardado.
    final c = Table(format: 'commander', random: Random(3));
    for (final (s, type, actor, p) in log) {
      c.apply(s, type, actor, p);
      if (s == savedSeq) c.importPrivate(1, saved);
    }

    expect(jsonEncode(c.state.toJson()), jsonEncode(b.state.toJson()));
    expect(c.private[1]!.hand.map((x) => x.pid), b.private[1]!.hand.map((x) => x.pid));
    expect(c.private[1]!.library.map((x) => x.oracleId), b.private[1]!.library.map((x) => x.oracleId));

    // E consegue continuar: os ids novos não repetem os já usados.
    final next = c.moveHidden(1, Zone.hand, c.private[1]!.hand.first.pid, Zone.battlefield);
    final id = (next.payload['newId'] as num).toInt();
    expect(c.state.cards.containsKey(id), isFalse);
    expect(c.state.storm, 2);
  });

  test('passar o turno põe o storm a zero; fim do jogo fica no estado', () {
    final t = Table(format: 'commander', localSeats: {0});
    var seq = 0;
    void send(Intent i) =>
        t.apply(++seq, i.type, 0, jsonDecode(jsonEncode(i.payload)) as Map<String, dynamic>);
    send(const Intent(Ev.joinTable, {'seat': 0, 'name': 'Ana', 'life': 40}));
    send(const Intent(Ev.joinTable, {'seat': 1, 'name': 'Rui', 'life': 40}));
    send(const Intent(Ev.startGame, {'first': 0}));
    send(const Intent(Ev.storm, {'delta': 3}));
    expect(t.state.storm, 3);
    send(const Intent(Ev.passTurn, {}));
    expect(t.state.storm, 0);
    send(const Intent(Ev.dayNight, {'value': 'night'}));
    expect(t.state.dayNight, 'night');
    send(const Intent(Ev.gameOver, {'winner': 1}));
    expect(t.state.over, isTrue);
    expect(t.state.winner, 1);
    expect(t.state.log.last.text, contains('Rui venceu'));
  });
}
