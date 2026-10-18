import 'dart:io';

import 'package:card_db/card_db.dart' as db;
import 'package:edhoff/data/limited_builds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decks por montar: guardar, reabrir, substituir e apagar', () {
    final dir = Directory.systemTemp.createTempSync('builds');
    final path = '${dir.path}/b.json';
    final store = LimitedBuildStore(path);
    const card = db.PackCard(db.BoosterPrint('s1', 'o1', 'R', '12', setCode: 'DOM'), foil: true);
    store.put(LimitedBuild(
      id: 'a',
      title: 'Sealed · DOM',
      commander: true,
      pool: const [card, db.PackCard(db.BoosterPrint('', 'o2', 'C', ''))],
      deck: {1},
      lands: {'W': 8},
      cmdPool: [0],
      cmdExtra: ['piper'],
    ));
    store.put(LimitedBuild(id: 'b', title: 'Draft', pool: const []));

    final again = LimitedBuildStore(path);
    expect(again.builds.map((b) => b.id), ['b', 'a']);
    final a = again.builds.last;
    expect(a.commander, isTrue);
    expect(a.pool.first.foil, isTrue);
    expect(a.pool.first.print.setCode, 'DOM');
    expect(a.pool.first.print.number, '12');
    expect(a.pool.last.print.oracleId, 'o2');
    expect(a.deck, {1});
    expect(a.lands, {'W': 8});
    expect(a.cmdPool, [0]);
    expect(a.cmdExtra, ['piper']);

    // Guardar o mesmo id substitui e passa para o topo.
    again.put(LimitedBuild(id: 'a', title: 'Sealed · DOM', pool: const [card], deck: {0}));
    expect(again.builds.map((b) => b.id), ['a', 'b']);
    expect(again.builds.first.deck, {0});
    again.remove('a');
    expect(LimitedBuildStore(path).builds.map((b) => b.id), ['b']);

    // No máximo [LimitedBuildStore.keep].
    for (var i = 0; i < 10; i++) {
      again.put(LimitedBuild(id: 'x$i', title: 't', pool: const []));
    }
    expect(again.builds.length, LimitedBuildStore.keep);
  });
}
