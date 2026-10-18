import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  setUpAll(setUpSqlite);

  test('gravar, ler, alterar e apagar decks', () {
    final dir = Directory.systemTemp.createTempSync('deck_store');
    final store = DeckStore.open('${dir.path}/user.sqlite');
    var deck = const Deck(name: 'Atraxa', format: 'commander')
        .add('a', board: Board.command)
        .add('b', qty: 3, category: 'Ramp')
        .add('c', board: Board.side);
    deck = store.save(deck);
    expect(deck.id, isNotNull);
    expect(store.listDecks().single.entries.length, 3);

    deck = store.save(deck.setQty('b', Board.main, 0).copyWith(name: 'Atraxa 2'));
    final again = store.getDeck(deck.id!)!;
    expect(again.name, 'Atraxa 2');
    expect(again.entries.map((e) => e.oracleId), ['a', 'c']);
    expect(store.allDeckOracleIds(), {'a', 'c'});

    store.setSetting('k', 'v');
    expect(store.setting('k'), 'v');
    store.markPackInstalled('commander', 'small');
    expect(store.installedPacks('small'), {'commander'});

    store.deleteDeck(deck.id!);
    expect(store.listDecks(), isEmpty);
    store.close();
    // Reabrir não recria tabelas nem perde dados.
    final reopened = DeckStore.open('${dir.path}/user.sqlite');
    expect(reopened.setting('k'), 'v');
    reopened.close();
  });

  test('histórico de jogos', () {
    final dir = Directory.systemTemp.createTempSync('games');
    final store = DeckStore.open('${dir.path}/user.sqlite');
    store.saveGame(GameRecord(
      format: 'commander',
      players: const [GamePlayer(name: 'Ana', deckName: 'Krenko', commanders: ['Krenko'], me: true), GamePlayer(name: 'Rui')],
      winner: 'Ana',
      myDeckId: 3,
      myWon: true,
      turns: 9,
      duration: const Duration(minutes: 42),
      playedAt: DateTime(2026, 10, 18),
    ));
    final g = store.listGames().single;
    expect(g.winner, 'Ana');
    expect(g.myWon, isTrue);
    expect(g.players.first.commanders, ['Krenko']);
    expect(g.duration.inMinutes, 42);
    store.deleteGame(g.id!);
    expect(store.listGames(), isEmpty);
    store.close();
  });

  test('versões: impressão por entrada, impressões guardadas e preferidas', () {
    final dir = Directory.systemTemp.createTempSync('prints');
    final store = DeckStore.open('${dir.path}/user.sqlite');
    const p1 = PrintInfo(printId: 'p1', oracleId: 'a', setCode: 'lea', collectorNumber: '1',
        releasedAt: '1993-08-05', imgSmall: 's1', imgNormal: 'n1');
    const p2 = PrintInfo(printId: 'p2', oracleId: 'a', setCode: 'cmm', collectorNumber: '9',
        releasedAt: '2023-08-04', faces: [PrintFace(imgSmall: 'fs', imgNormal: 'fn')]);
    store.savePrints([p1, p2]);
    expect(store.printsOf('a').map((p) => p.printId), ['p2', 'p1']);
    expect(store.printInfo('p2')!.faces.single.imgNormal, 'fn');

    var deck = const Deck(name: 'x', format: 'commander').add('a', printId: 'p1').add('b');
    deck = store.save(deck.setPrint('b', Board.main, 'p9'));
    final again = store.getDeck(deck.id!)!;
    expect({for (final e in again.entries) e.oracleId: e.printId}, {'a': 'p1', 'b': 'p9'});
    expect(again.move('a', Board.main, Board.side).entries.firstWhere((e) => e.oracleId == 'a').printId, 'p1');
    expect(again.setPrint('a', Board.main, null).entries.first.printId, isNull);

    store.setPreferredPrint('a', 'p2');
    expect(store.preferredPrints(), {'a': 'p2'});
    store.setPreferredPrint('a', null);
    expect(store.preferredPrints(), isEmpty);
    store.close();
  });

  test('carta com outra impressão troca arte e coleção, mantém o resto', () {
    const card = Card(oracleId: 'a', name: 'Delver', printId: 'p0', setCode: 'isd', faces: [
      CardFace(name: 'Delver', imgSmall: 'x', imgNormal: 'y'),
      CardFace(name: 'Insectile', imgSmall: 'x2', imgNormal: 'y2'),
    ]);
    const p = PrintInfo(printId: 'p7', oracleId: 'a', setCode: 'mid', faces: [
      PrintFace(imgSmall: 'a', imgNormal: 'b'),
      PrintFace(imgSmall: 'c', imgNormal: 'd'),
    ]);
    final c = card.withPrint(p);
    expect(c.printId, 'p7');
    expect(c.setCode, 'mid');
    expect(c.faces[1].name, 'Insectile');
    expect(c.faces[1].imgNormal, 'd');
    expect(ImageRef.allOf(c).map((r) => r.key), ['p7_0', 'p7_1']);
  });

  test('mover entre boards junta quantidades', () {
    final d = const Deck(name: 'x', format: 'modern')
        .add('a', qty: 2)
        .add('a', qty: 1, board: Board.side)
        .move('a', Board.side, Board.main);
    expect(d.entries.single.qty, 3);
    expect(d.entries.single.board, Board.main);
  });
}
