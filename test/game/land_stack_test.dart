import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:edhoff/game/game_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesa_core/mesa_core.dart';
import 'package:sqlite3/open.dart';

void main() {
  test('terrenos anexados viram todos juntos; "só esta" vira um', () async {
    if (Platform.isWindows) {
      open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(r'C:\Python313\DLLs\sqlite3.dll'));
    }
    final dir = Directory.systemTemp.createTempSync('lands');
    final imp = CardImporter('${dir.path}/c.sqlite')..open();
    Map<String, dynamic> card(String id, String name, String type) => {
          'id': 'p$id',
          'oracle_id': id,
          'name': name,
          'layout': 'normal',
          'type_line': type,
          'legalities': {'commander': 'legal'},
          'games': ['paper'],
        };
    await imp.importLines(Stream.fromIterable([
      jsonEncode(card('swamp', 'Swamp', 'Basic Land — Swamp')),
      jsonEncode(card('aura', 'Aura', 'Enchantment — Aura')),
      jsonEncode(card('bear', 'Bear', 'Creature — Bear')),
    ]));
    imp.finish({});
    final repo = CardRepository.open('${dir.path}/c.sqlite')!;
    final deck = const Deck(name: 'd', format: 'free').add('swamp', qty: 20).add('aura', qty: 5).add('bear', qty: 5);
    final ctrl = GameController.playtest(
      repo: repo,
      format: GameFormat.free,
      seats: [SeatSetup(seat: 0, name: 'Eu', deck: deck)],
    );
    // Põe em campo 4 pântanos e uma aura, saídos do grimório.
    PrivateCard pick(String oracle) => ctrl.zones(0).library.firstWhere((c) => c.oracleId == oracle);
    for (var i = 0; i < 4; i++) {
      ctrl.fromLibrary(pick('swamp'), Zone.battlefield);
    }
    ctrl.fromLibrary(pick('aura'), Zone.battlefield);
    final field = ctrl.state.cards.values.where((c) => c.zone == Zone.battlefield).toList();
    final swamps = field.where((c) => c.oracleId == 'swamp').toList();
    final aura = field.firstWhere((c) => c.oracleId == 'aura');
    final host = swamps[0];
    for (final s in [swamps[1], swamps[2], aura]) {
      ctrl.send(Intent(Ev.attach, {'id': s.id, 'to': host.id}));
    }

    // Tocar num dos anexados vira a pilha de terrenos (não a aura nem o 4.º).
    ctrl.toggleTap(ctrl.state.cards[swamps[2].id]!);
    bool tapped(CardInstance c) => ctrl.state.cards[c.id]!.tapped;
    expect([for (final s in swamps.take(3)) tapped(s)], [true, true, true]);
    expect(tapped(swamps[3]), isFalse);
    expect(tapped(aura), isFalse);

    // "Desvirar só esta".
    ctrl.toggleTap(ctrl.state.cards[swamps[1].id]!, single: true);
    expect([for (final s in swamps.take(3)) tapped(s)], [true, false, true]);

    // A aura sozinha e um terreno solto continuam a virar sozinhos.
    expect(ctrl.landStack(ctrl.state.cards[aura.id]!).length, 1);
    expect(ctrl.landStack(ctrl.state.cards[swamps[3].id]!).length, 1);
  });
}
