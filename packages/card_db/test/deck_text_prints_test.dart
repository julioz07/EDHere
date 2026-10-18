import 'package:card_db/card_db.dart';
import 'package:test/test.dart';

void main() {
  const gisa = Card(oracleId: 'gisa', name: 'Ghoulcaller Gisa', typeLine: 'Legendary Creature — Human Wizard');
  const sol = Card(oracleId: 'sol', name: 'Sol Ring', typeLine: 'Artifact');
  const swamp = Card(oracleId: 'swamp', name: 'Swamp', typeLine: 'Basic Land — Swamp');
  final byName = {for (final c in [gisa, sol, swamp]) c.name: c};

  test('a lista do Moxfield traz a coleção e o número de cada carta', () {
    final lines = parseDeckText('''
Commander
1 Ghoulcaller Gisa (FDC) 6 *F*

Deck
33 Swamp (FDN) 286
1x Sol Ring (CMR) 472 *F* [Ramp]
1 Sol Ring
''', hasCommandZone: true);
    expect(lines.first.setCode, 'fdc');
    expect(lines.first.collectorNumber, '6');
    expect(lines[1].qty, 33);
    expect((lines[1].setCode, lines[1].collectorNumber), ('fdn', '286'));
    expect(lines[2].category, 'Ramp');
    expect((lines[2].setCode, lines[2].collectorNumber), ('cmr', '472'));
    expect(lines[3].setCode, isNull);

    final r = resolveDeckText(lines, (n) => byName[n]);
    expect(r.unresolved, isEmpty);
    // A primeira versão de cada carta é a que conta.
    expect(r.printings, {
      'gisa': (set: 'fdc', number: '6'),
      'swamp': (set: 'fdn', number: '286'),
      'sol': (set: 'cmr', number: '472'),
    });
    expect(r.entries.firstWhere((e) => e.oracleId == 'sol').qty, 2);
  });

  test('exportar mantém a versão escolhida (e só nomes sem ela)', () {
    final deck = const Deck(name: 'd', format: 'commander')
        .add('gisa', board: Board.command, printId: 'p-gisa')
        .add('sol');
    final cards = {for (final c in [gisa, sol]) c.oracleId: c};
    PrintInfo? printOf(String id) =>
        id == 'p-gisa' ? const PrintInfo(printId: 'p-gisa', oracleId: 'gisa', setCode: 'fdc', collectorNumber: '6') : null;
    final text = exportDeckText(deck, cards, printOf: printOf);
    expect(text, contains('1 Ghoulcaller Gisa (FDC) 6'));
    expect(text, contains('1 Sol Ring\n').or(endsWith('1 Sol Ring')));
    expect(exportDeckText(deck, cards), isNot(contains('(FDC)')));
    // E volta a ler-se igual.
    final back = resolveDeckText(parseDeckText(text, hasCommandZone: true), (n) => byName[n]);
    expect(back.printings['gisa'], (set: 'fdc', number: '6'));
  });
}

extension on Matcher {
  Matcher or(Matcher other) => anyOf(this, other);
}
