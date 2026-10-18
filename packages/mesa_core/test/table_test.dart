import 'dart:convert';
import 'dart:math';

import 'package:mesa_core/mesa_core.dart';
import 'package:test/test.dart';

/// Dois dispositivos: A controla o lugar 0, B o lugar 1. Um "anfitrião"
/// ordena os eventos e entrega-os a ambos, como na rede.
class Pod {
  Pod()
      : a = Table(format: 'commander', localSeats: {0}, random: Random(1)),
        b = Table(format: 'commander', localSeats: {1}, random: Random(2));

  final Table a;
  final Table b;
  int seq = 0;

  Table of(int seat) => seat == 0 ? a : b;

  void send(int actor, Intent i) {
    // Simula a rede: o payload passa por JSON.
    final p = jsonDecode(jsonEncode(i.payload)) as Map<String, dynamic>;
    seq++;
    a.apply(seq, i.type, actor, p);
    b.apply(seq, i.type, actor, p);
  }

  void expectInSync() {
    expect(jsonEncode(a.state.toJson()), jsonEncode(b.state.toJson()));
    expect(a.state.log.map((l) => l.text).toList(), b.state.log.map((l) => l.text).toList());
  }
}

List<String> deck(String prefix, int n) => [for (var i = 0; i < n; i++) '$prefix$i'];

void main() {
  late Pod pod;

  setUp(() {
    pod = Pod();
    pod.send(0, const Intent(Ev.joinTable, {'seat': 0, 'name': 'Ana', 'life': 40}));
    pod.send(1, const Intent(Ev.joinTable, {'seat': 1, 'name': 'Rui', 'life': 40}));
    pod.send(0, pod.a.loadDeck(0, deck('a', 99), ['cmdA']));
    pod.send(1, pod.b.loadDeck(1, deck('b', 99), ['cmdB']));
    pod.send(0, const Intent(Ev.startGame, {'first': 0}));
  });

  test('carregar decks: comandantes públicos, grimórios só no dono', () {
    pod.expectInSync();
    expect(pod.a.state.players[0]!.libraryCount, 99);
    expect(pod.a.private[0]!.library.length, 99);
    expect(pod.b.private.containsKey(0), isFalse, reason: 'B não pode saber o grimório de A');
    final cmds = pod.a.state.cards.values.where((c) => c.zone == Zone.command).toList();
    expect(cmds.map((c) => c.oracleId).toSet(), {'cmdA', 'cmdB'});
  });

  test('comprar, jogar da mão, virar e mandar para o cemitério', () {
    pod.send(0, pod.a.draw(0, 7));
    expect(pod.a.private[0]!.hand.length, 7);
    expect(pod.b.state.players[0]!.handCount, 7);
    expect(pod.b.state.players[0]!.libraryCount, 92);

    final card = pod.a.private[0]!.hand.first;
    pod.send(0, pod.a.moveHidden(0, Zone.hand, card.pid, Zone.battlefield, x: .3, y: .4));
    pod.expectInSync();
    final onField = pod.b.state.cards.values.singleWhere((c) => c.zone == Zone.battlefield);
    expect(onField.oracleId, card.oracleId);
    expect(pod.a.private[0]!.hand.length, 6);
    expect(pod.b.state.players[0]!.handCount, 6);

    pod.send(0, Intent(Ev.tap, {'ids': [onField.id], 'value': true}));
    expect(pod.b.state.cards[onField.id]!.tapped, isTrue);
    pod.send(0, pod.a.movePublic(onField.id, Zone.graveyard));
    pod.expectInSync();
    final dead = pod.b.state.cards[onField.id]!;
    expect(dead.zone, Zone.graveyard);
    expect(dead.tapped, isFalse);
  });

  test('carta pública que volta para a mão deixa de ser visível aos outros', () {
    pod.send(0, pod.a.draw(0, 1));
    final pid = pod.a.private[0]!.hand.single.pid;
    pod.send(0, pod.a.moveHidden(0, Zone.hand, pid, Zone.battlefield));
    final id = pod.a.state.cards.values.singleWhere((c) => c.zone == Zone.battlefield).id;
    pod.send(0, pod.a.movePublic(id, Zone.hand));
    pod.expectInSync();
    expect(pod.b.state.cards.containsKey(id), isFalse);
    expect(pod.b.state.players[0]!.handCount, 1);
    expect(pod.a.private[0]!.hand.length, 1);
  });

  test('mão para o grimório não revela a carta', () {
    pod.send(0, pod.a.draw(0, 2));
    final c = pod.a.private[0]!.hand.first;
    pod.send(0, pod.a.moveHidden(0, Zone.hand, c.pid, Zone.library, pos: 'bottom'));
    pod.expectInSync();
    expect(pod.a.private[0]!.library.last.oracleId, c.oracleId);
    expect(pod.b.state.log.last.text, isNot(contains(c.oracleId)));
  });

  test('mill e scry', () {
    final top3 = pod.a.private[0]!.library.take(3).map((c) => c.oracleId).toList();
    pod.send(0, pod.a.mill(0, 2));
    pod.expectInSync();
    final grave = pod.b.state.zoneCards(0, Zone.graveyard).map((c) => c.oracleId).toList();
    expect(grave, top3.take(2).toList());
    expect(pod.b.state.players[0]!.libraryCount, 97);

    final lib = pod.a.private[0]!.library;
    final p0 = lib[0].pid, p1 = lib[1].pid;
    pod.send(0, pod.a.scryDone(0, top: [p1], bottom: [p0]));
    expect(pod.a.private[0]!.library.first.pid, p1);
    expect(pod.a.private[0]!.library.last.pid, p0);
    pod.expectInSync();
  });

  test('mulligan de Londres: 7 novas e 1 para o fundo', () {
    pod.send(0, pod.a.draw(0, 7));
    final before = pod.a.private[0]!.hand.map((c) => c.pid).toSet();
    pod.send(0, pod.a.mulligan(0));
    expect(pod.a.private[0]!.hand.length, 7);
    expect(pod.a.private[0]!.library.length + 7, 99);
    final pid = pod.a.private[0]!.hand.first.pid;
    pod.send(0, pod.a.bottom(0, [pid]));
    expect(pod.b.state.players[0]!.handCount, 6);
    expect(pod.b.state.players[0]!.libraryCount, 93);
    expect(pod.a.private[0]!.library.last.pid, pid);
    expect(before.length, 7);
    pod.expectInSync();
  });

  test('taxa de comandante e dano de comandante', () {
    final cmd = pod.a.state.cards.values.firstWhere((c) => c.oracleId == 'cmdA');
    pod.send(0, pod.a.movePublic(cmd.id, Zone.battlefield));
    pod.send(0, pod.a.movePublic(cmd.id, Zone.command));
    pod.send(0, pod.a.movePublic(cmd.id, Zone.battlefield));
    expect(pod.b.state.players[0]!.commanderTax(cmd.id), 4);
    pod.send(0, Intent(Ev.commanderDamage, {'seat': 1, 'cmdId': cmd.id, 'delta': 7}));
    expect(pod.b.state.players[1]!.commanderDamage[cmd.id], 7);
    expect(pod.b.state.players[1]!.life, 33);
    pod.expectInSync();
  });

  test('tokens: criar, empilhar e desaparecer ao sair do campo', () {
    pod.send(1, pod.b.createToken(1, name: 'Soldier', pt: '1/1', qty: 3));
    final t = pod.a.state.cards.values.singleWhere((c) => c.isToken);
    expect(t.stackQty, 3);
    expect(t.id ~/ 1000000, 1, reason: 'ids gerados pelo dono não colidem');
    pod.send(1, Intent(Ev.tokenQty, {'id': t.id, 'qty': 5}));
    expect(pod.a.state.cards[t.id]!.stackQty, 5);
    pod.send(1, pod.b.movePublic(t.id, Zone.graveyard));
    expect(pod.a.state.cards.containsKey(t.id), isFalse);
    pod.expectInSync();
  });

  test('passar o turno desvira as cartas do jogador seguinte', () {
    pod.send(1, pod.b.draw(1, 1));
    final pid = pod.b.private[1]!.hand.single.pid;
    pod.send(1, pod.b.moveHidden(1, Zone.hand, pid, Zone.battlefield));
    final id = pod.b.state.cards.values.singleWhere((c) => c.zone == Zone.battlefield).id;
    pod.send(1, Intent(Ev.tap, {'ids': [id], 'value': true}));
    pod.send(0, const Intent(Ev.passTurn, {}));
    expect(pod.a.state.activeSeat, 1);
    expect(pod.a.state.turn, 2);
    expect(pod.a.state.cards[id]!.tapped, isFalse);
    pod.expectInSync();
  });

  test('desfazer a última ação própria, incluindo as zonas ocultas', () {
    pod.send(0, pod.a.draw(0, 3));
    final handBefore = pod.a.private[0]!.hand.map((c) => c.pid).toList();
    final pid = handBefore.first;
    pod.send(0, pod.a.moveHidden(0, Zone.hand, pid, Zone.battlefield));
    expect(pod.a.canUndo(0), isTrue);
    expect(pod.a.canUndo(1), isFalse);
    pod.send(0, pod.a.undo());
    pod.expectInSync();
    expect(pod.a.private[0]!.hand.map((c) => c.pid).toList(), handBefore);
    expect(pod.b.state.cards.values.where((c) => c.zone == Zone.battlefield), isEmpty);
    expect(pod.b.state.players[0]!.handCount, 3);
  });

  test('undo de outro jogador é ignorado em todos', () {
    pod.send(0, pod.a.draw(0, 1));
    final seqBefore = pod.a.state.players[0]!.handCount;
    pod.send(1, Intent(Ev.undo, {'seq': pod.seq}));
    expect(pod.a.state.players[0]!.handCount, seqBefore);
    pod.expectInSync();
  });

  test('anexar segue a carta quando ela se mexe', () {
    pod.send(0, pod.a.draw(0, 2));
    final h = pod.a.private[0]!.hand;
    final p1 = h[0].pid, p2 = h[1].pid;
    pod.send(0, pod.a.moveHidden(0, Zone.hand, p1, Zone.battlefield, x: .2, y: .2));
    pod.send(0, pod.a.moveHidden(0, Zone.hand, p2, Zone.battlefield, x: .6, y: .6));
    final field = pod.a.state.zoneCards(0, Zone.battlefield).toList();
    pod.send(0, Intent(Ev.attach, {'id': field[1].id, 'to': field[0].id}));
    pod.send(0, Intent(Ev.position, {'id': field[0].id, 'x': .5, 'y': .5}));
    expect(pod.b.state.cards[field[1].id]!.x, closeTo(.5, 1e-9));
    pod.send(0, pod.a.movePublic(field[0].id, Zone.graveyard));
    expect(pod.b.state.cards[field[1].id]!.attachedTo, isNull);
    pod.expectInSync();
  });

  test('contadores com valor fixo, modificadores negativos e habilidades', () {
    pod.send(0, pod.a.draw(0, 1));
    pod.send(0, pod.a.moveHidden(0, Zone.hand, pod.a.private[0]!.hand.single.pid, Zone.battlefield));
    final id = pod.a.state.zoneCards(0, Zone.battlefield).single.id;
    pod.send(0, Intent(Ev.counter, {'id': id, 'kind': CounterKind.plus, 'value': 5}));
    pod.send(0, Intent(Ev.counter, {'id': id, 'kind': CounterKind.plus, 'delta': -2}));
    pod.send(0, Intent(Ev.counter, {'id': id, 'kind': CounterKind.modPower, 'value': 2}));
    pod.send(0, Intent(Ev.counter, {'id': id, 'kind': CounterKind.modToughness, 'value': -1}));
    pod.send(0, Intent(Ev.counter, {'id': id, 'kind': 'kw:Flying', 'value': 1}));
    final c = pod.b.state.cards[id]!;
    expect(c.counters, {CounterKind.plus: 3, CounterKind.modPower: 2, CounterKind.modToughness: -1, 'kw:Flying': 1});
    pod.send(0, Intent(Ev.counter, {'id': id, 'kind': 'kw:Flying', 'value': 0}));
    pod.send(0, Intent(Ev.counter, {'id': id, 'kind': CounterKind.modToughness, 'delta': 1}));
    expect(pod.b.state.cards[id]!.counters, {CounterKind.plus: 3, CounterKind.modPower: 2});
    expect(pod.b.state.log.last.text, contains('resistência'));
    pod.expectInSync();
  });

  test('alvos: carta, jogador, limpar e desaparecem ao passar o turno', () {
    final cmdA = pod.a.state.cards.values.firstWhere((c) => c.oracleId == 'cmdA');
    final cmdB = pod.a.state.cards.values.firstWhere((c) => c.oracleId == 'cmdB');
    pod.send(0, Intent(Ev.arrow, {'from': cmdA.id, 'to': cmdB.id}));
    pod.send(0, const Intent(Ev.arrow, {'seat': 1}));
    expect(pod.b.state.targets.length, 2);
    expect(pod.b.state.targets.last.seat, 1);
    expect(pod.b.state.log.last.text, 'Ana aponta para Rui');
    pod.send(1, const Intent(Ev.arrow, {'seat': 0}));
    pod.send(0, const Intent(Ev.arrow, {}));
    expect(pod.b.state.targets.map((t) => t.actor), [1], reason: 'só limpa os da Ana');
    pod.send(0, const Intent(Ev.passTurn, {}));
    expect(pod.b.state.targets, isEmpty);
    pod.expectInSync();
  });

  test('a impressão escolhida acompanha a carta entre zonas', () {
    final t = Table(format: 'commander', localSeats: {0});
    var seq = 0;
    void send(Intent i) =>
        t.apply(++seq, i.type, 0, jsonDecode(jsonEncode(i.payload)) as Map<String, dynamic>);
    send(const Intent(Ev.joinTable, {'seat': 0, 'name': 'Ana', 'life': 40}));
    send(t.loadDeck(0, ['x', 'x', 'y'], ['cmd'], prints: {'x': 'px', 'cmd': 'pc'}));
    expect(t.state.cards.values.single.printId, 'pc');
    send(t.draw(0, 3));
    final px = t.private[0]!.hand.firstWhere((c) => c.oracleId == 'x');
    expect(px.printId, 'px');
    send(t.moveHidden(0, Zone.hand, px.pid, Zone.battlefield));
    final onField = t.state.zoneCards(0, Zone.battlefield).single;
    expect(onField.printId, 'px');
    send(t.movePublic(onField.id, Zone.hand));
    expect(t.private[0]!.hand.where((c) => c.printId == 'px').length, 2);
    send(t.mill(0, 0));
    expect(GameState.fromJson(t.state.toJson()).cards.values.first.printId, 'pc');
  });

  test('evento inválido é ignorado sem estragar o estado', () {
    final before = jsonEncode(pod.a.state.toJson());
    pod.send(0, const Intent(Ev.draw, {'seat': 9, 'n': 1}));
    pod.send(0, const Intent(Ev.life, {'seat': 0}));
    final after = pod.a.state.toJson()..remove('seq');
    expect(jsonEncode(after), jsonEncode((jsonDecode(before) as Map)..remove('seq')));
    pod.send(0, pod.a.draw(0, 1));
    expect(pod.a.private[0]!.hand.length, 1);
    pod.expectInSync();
  });

  test('o estado público sobrevive a JSON (snapshot de reconexão)', () {
    pod.send(0, pod.a.draw(0, 7));
    pod.send(0, pod.a.mill(0, 3));
    final json = jsonEncode(pod.a.state.toJson());
    final back = GameState.fromJson(jsonDecode(json) as Map<String, dynamic>);
    expect(jsonEncode(back.toJson()), json);
  });
}
