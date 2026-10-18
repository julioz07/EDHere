import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:test/test.dart';

import 'helpers.dart';

DeckStore _open(String name) {
  final dir = Directory.systemTemp.createTempSync('backup_$name');
  return DeckStore.open('${dir.path}/user.sqlite');
}

void main() {
  setUpAll(setUpSqlite);

  test('exporta e importa decks, coleção e histórico noutro dispositivo', () {
    final a = _open('a');
    final deck = a.save(const Deck(name: 'Atraxa', format: 'commander', notes: 'n')
        .add('atraxa', board: Board.command)
        .add('sol', printId: 'p1')
        .add('forest', qty: 30, category: 'Lands'));
    a.addOwned({'sol': 2, 'forest': 10});
    a.saveGame(GameRecord(
      format: 'commander',
      players: const [GamePlayer(name: 'Eu', deckName: 'Atraxa', me: true)],
      myDeckId: deck.id,
      myWon: true,
      turns: 9,
      duration: const Duration(minutes: 40),
      playedAt: DateTime(2026, 10, 1, 20),
    ));
    a.setPreferredPrint('sol', 'p2');
    a.savePrints(const [PrintInfo(printId: 'p1', oracleId: 'sol', name: 'Sol Ring')]);

    final text = Backup.collect(a, nameOf: (id) => {'sol': 'Sol Ring'}[id]).encode();

    final b = _open('b');
    b.save(const Deck(name: 'Outro', format: 'modern'));
    b.addOwned({'forest': 20});
    final r = importBackup(b, Backup.decode(text));
    expect(r.decksAdded, 1);
    expect(r.gamesAdded, 1);
    final got = b.listDecks().firstWhere((d) => d.name == 'Atraxa');
    expect(got.notes, 'n');
    expect(got.count(Board.command), 1);
    expect(got.entries.firstWhere((e) => e.oracleId == 'sol').printId, 'p1');
    expect(got.entries.firstWhere((e) => e.oracleId == 'forest').category, 'Lands');
    // Coleção: fica a quantidade maior.
    expect(b.collection(), {'sol': 2, 'forest': 20});
    // A partida aponta para o deck importado.
    expect(b.listGames().single.myDeckId, got.id);
    expect(b.preferredPrints(), {'sol': 'p2'});
    expect(b.printInfo('p1')?.name, 'Sol Ring');

    // Importar outra vez não duplica nada.
    final again = importBackup(b, Backup.decode(text));
    expect(again.decksAdded, 0);
    expect(again.decksSkipped, 1);
    expect(again.gamesAdded, 0);
    expect(b.listDecks().length, 2);

    // Mesmo nome com cartas diferentes entra com outro nome.
    b.save(got.setQty('forest', Board.main, 29));
    importBackup(b, Backup.decode(text));
    expect(b.listDecks().map((d) => d.name), contains('Atraxa (importado)'));
  });

  test('cartas que não existem procuram-se pelo nome ou ficam de fora', () {
    final a = _open('c');
    a.save(const Deck(name: 'D', format: 'free').add('old-sol').add('gone', qty: 2));
    final text =
        Backup.collect(a, collection: false, nameOf: (id) => {'old-sol': 'Sol Ring', 'gone': 'Lost'}[id])
            .encode();
    final b = _open('d');
    final r = importBackup(b, Backup.decode(text),
        resolve: (id, name) => name == 'Sol Ring' ? 'new-sol' : null);
    expect(b.listDecks().single.entries.map((e) => e.oracleId), ['new-sol']);
    expect(r.missing, {'Lost'});
  });

  test('ficheiros que não são backups dão um erro claro', () {
    expect(() => Backup.decode('olá'), throwsFormatException);
    expect(() => Backup.decode('{"a":1}'), throwsFormatException);
    expect(() => Backup.decode('{"kind":"edhere-backup","version":99}'), throwsFormatException);
  });
}
