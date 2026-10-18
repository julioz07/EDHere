import 'dart:convert';
import 'dart:math';

import 'package:mesa_core/mesa_core.dart';
import 'package:test/test.dart';

/// Gravar um jogo solo e continuar depois: a mesa toda vai para JSON e volta.
void main() {
  test('gravar e repor a mesa dá o mesmo estado e o jogo continua', () {
    final a = Table(format: 'commander', localSeats: {0, 1}, random: Random(1));
    var seq = 0;
    void send(int actor, Intent i) => a.apply(++seq, i.type, actor, jsonDecode(jsonEncode(i.payload)));

    send(0, const Intent(Ev.joinTable, {'seat': 0, 'name': 'Ana', 'life': 40}));
    send(1, const Intent(Ev.joinTable, {'seat': 1, 'name': 'Rui', 'life': 40}));
    send(0, a.loadDeck(0, [for (var i = 0; i < 60; i++) 'a$i'], ['cmdA']));
    send(1, a.loadDeck(1, [for (var i = 0; i < 60; i++) 'b$i'], ['cmdB']));
    send(0, const Intent(Ev.startGame, {'first': 0}));
    send(0, a.draw(0, 7));
    send(1, a.draw(1, 7));
    send(0, a.moveHidden(0, Zone.hand, a.private[0]!.hand.first.pid, Zone.battlefield, x: .3, y: .4));
    send(0, a.createToken(0, name: 'Goblin', pt: '1/1', qty: 3));
    send(1, const Intent(Ev.storm, {'delta': 2}));
    send(0, const Intent(Ev.passTurn, {}));

    final saved = jsonDecode(jsonEncode(a.saveAll())) as Map<String, dynamic>;
    final b = Table(format: 'commander', localSeats: {0, 1})..restoreAll(saved);

    expect(jsonEncode(b.state.toJson()), jsonEncode(a.state.toJson()));
    expect(b.state.log.map((e) => e.text), a.state.log.map((e) => e.text));
    for (final s in [0, 1]) {
      expect(b.private[s]!.hand.map((x) => x.oracleId), a.private[s]!.hand.map((x) => x.oracleId));
      // O grimório fica pela mesma ordem.
      expect(b.private[s]!.library.map((x) => x.oracleId), a.private[s]!.library.map((x) => x.oracleId));
    }

    // Continua: compra, joga e os ids novos não repetem os já usados.
    var bseq = b.state.seq;
    void sendB(int actor, Intent i) => b.apply(++bseq, i.type, actor, jsonDecode(jsonEncode(i.payload)));
    sendB(1, b.draw(1, 1));
    expect(b.private[1]!.hand.length, 8);
    final next = b.moveHidden(1, Zone.hand, b.private[1]!.hand.first.pid, Zone.battlefield);
    final id = (next.payload['newId'] as num).toInt();
    expect(b.state.cards.containsKey(id), isFalse);
    sendB(1, next);
    expect(b.state.cards.containsKey(id), isTrue);
  });
}
