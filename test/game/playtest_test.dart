import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:edhoff/game/game_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

void main() {
  test('playtest: mão inicial privada com 7 cartas', () async {
    if (Platform.isWindows) {
      open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(r'C:\Python313\DLLs\sqlite3.dll'));
    }
    final dir = Directory.systemTemp.createTempSync('pt');
    final imp = CardImporter('${dir.path}/c.sqlite')..open();
    await imp.importLines(Stream.fromIterable([
      for (var i = 0; i < 10; i++)
        jsonEncode({
          'id': 'p$i',
          'oracle_id': 'o$i',
          'name': 'C$i',
          'layout': 'normal',
          'type_line': 'Creature',
          'legalities': {'commander': 'legal'},
          'games': ['paper'],
        }),
    ]));
    imp.finish({});
    final repo = CardRepository.open('${dir.path}/c.sqlite')!;
    var deck = const Deck(name: 'd', format: 'commander').add('o0', board: Board.command);
    for (var i = 1; i < 10; i++) {
      deck = deck.add('o$i', qty: 5);
    }
    final ctrl = GameController.playtest(
      repo: repo,
      format: GameFormat.commander,
      seats: [SeatSetup(seat: 0, name: 'Eu', deck: deck)],
    );
    expect(ctrl.state.players[0]!.handCount, 7);
    expect(ctrl.zones(0).hand.length, 7);

    // Gravar e continuar depois: o mesmo estado, a mesma mão e o jogo segue.
    ctrl.mulligans[0] = 1;
    ctrl.openingDone.add(0);
    ctrl.passTurn();
    final json = jsonDecode(jsonEncode(ctrl.saveJson())) as Map<String, dynamic>;
    final back = GameController.restore(repo: repo, json: json, decks: {0: deck});
    expect(jsonEncode(back.state.toJson()), jsonEncode(ctrl.state.toJson()));
    expect(back.zones(0).hand.map((c) => c.oracleId), ctrl.zones(0).hand.map((c) => c.oracleId));
    expect(back.zones(0).library.map((c) => c.oracleId), ctrl.zones(0).library.map((c) => c.oracleId));
    expect(back.mulligans[0], 1);
    expect(back.openingDone, {0});
    expect(back.state.log.length, ctrl.state.log.length);
    back.draw();
    expect(back.zones(0).hand.length, ctrl.zones(0).hand.length + 1);
  });
}
