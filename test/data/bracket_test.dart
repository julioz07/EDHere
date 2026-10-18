import 'dart:ffi';
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:edhoff/data/bracket.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

void main() {
  test('turnos extra e destruição de terrenos em massa pelo texto das cartas', () async {
    if (Platform.isWindows) {
      open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(r'C:\Python313\DLLs\sqlite3.dll'));
    }
    final dir = Directory.systemTemp.createTempSync('bracket');
    final imp = CardImporter('${dir.path}/c.sqlite')..open();
    await imp.importLines(Stream.fromIterable(File('test/fixtures/tutorial_cards.jsonl').readAsLinesSync()));
    imp.finish({});
    final repo = CardRepository.open('${dir.path}/c.sqlite')!;
    Card c(String n) => repo.findByName(n)!;
    expect(BracketEstimate.isExtraTurn(c('Time Warp')), isTrue);
    expect(BracketEstimate.isExtraTurn(c('Temporal Manipulation')), isTrue);
    expect(BracketEstimate.isLandDenial(c('Armageddon')), isTrue);
    expect(BracketEstimate.isLandDenial(c('Ruination')), isTrue);
    expect(BracketEstimate.isLandDenial(c('Winter Orb')), isTrue);
    for (final n in ['Sol Ring', 'Forest', 'Lightning Bolt', 'Swords to Plowshares', 'Giant Growth']) {
      expect(BracketEstimate.isLandDenial(c(n)) || BracketEstimate.isExtraTurn(c(n)), isFalse, reason: n);
    }
    final deck = const Deck(name: 'd', format: 'commander')
        .add(c('Marwyn, the Nurturer').oracleId, board: Board.command)
        .add(c('Time Warp').oracleId)
        .add(c('Temporal Manipulation').oracleId)
        .add(c('Armageddon').oracleId);
    final cards = repo.getMany(deck.entries.map((e) => e.oracleId));
    final b = BracketEstimate.of(deck, cards);
    expect(b.extraTurns.length, 2);
    expect(b.chainsExtraTurns, isTrue);
    expect(b.landDenial, ['Armageddon']);
    expect(b.minimum, 4);
  });
}
