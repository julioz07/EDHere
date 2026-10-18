import 'dart:math';

import 'package:card_db/card_db.dart';
import 'package:test/test.dart';

void main() {
  const info = BoosterSetInfo(
      code: 'TST', name: 'Teste', date: '2025-01-01', type: 'expansion', kind: 'play', size: 5);
  final oracles = [for (var i = 0; i < 12; i++) 'o$i'];
  // 8 comuns, 3 incomuns, 1 rara; 2 composições: uma com foil (peso 1) e outra sem (peso 3).
  final json = {
    'prints': [
      for (var i = 0; i < 12; i++) ['s$i', i, i < 8 ? 'C' : (i < 11 ? 'U' : 'R'), '$i'],
    ],
    'sheets': {
      'common': {
        'foil': 0,
        'cards': [
          for (var i = 0; i < 8; i++) [i, 1]
        ],
      },
      'uncommon': {
        'foil': 0,
        'cards': [
          for (var i = 8; i < 11; i++) [i, 1]
        ],
      },
      'rare': {
        'foil': 0,
        'cards': [
          [11, 1],
        ],
      },
      'foil': {
        'foil': 1,
        'cards': [
          for (var i = 0; i < 12; i++) [i, 1]
        ],
      },
    },
    'configs': [
      [
        3,
        {'common': 3, 'uncommon': 1, 'rare': 1}
      ],
      [
        1,
        {'common': 2, 'uncommon': 1, 'rare': 1, 'foil': 1}
      ],
    ],
  };

  test('abre boosters com a composição e sem repetir cartas', () {
    final set = SetBoosters.fromJson(info, json, oracles);
    final random = Random(7);
    var foils = 0;
    for (var n = 0; n < 400; n++) {
      final pack = set.open(random);
      expect(pack.length, inInclusiveRange(4, 5));
      final normal = pack.where((c) => !c.foil).map((c) => c.print.scryfallId).toList();
      expect(normal.toSet().length, normal.length, reason: 'sem cartas repetidas no mesmo booster');
      expect(pack.first.print.rarity, 'R', reason: 'a rara vem primeiro');
      expect(pack.where((c) => c.print.rarity == 'U' && !c.foil).length, 1);
      foils += pack.where((c) => c.foil).length;
    }
    // A composição com foil tem peso 1 em 4: ~100 em 400.
    expect(foils, inInclusiveRange(60, 140));
  });

  test('imagens do Scryfall a partir do id', () {
    expect(BoosterPrint.imageUrl('abcdef', 'small'), 'https://cards.scryfall.io/small/front/a/b/abcdef.jpg');
    expect(BoosterPrint.imageUrl('abcdef', 'normal', back: true),
        'https://cards.scryfall.io/normal/back/a/b/abcdef.jpg');
  });

  test('pacote JumpStart: a carta de destaque é a de raridade mais alta', () {
    final p = JumpstartPacket.fromJson({
      'set': 'JMP',
      'name': 'Goblins 1',
      'theme': 'Goblins',
      'cards': [
        ['a', 0, 'C', '1', 6],
        ['b', 1, 'M', '2', 1],
        ['c', 2, 'R', '3', 1],
        ['d', 3, 'C', '4', 12],
      ],
    }, oracles);
    expect(p.count, 20);
    expect(p.featured.scryfallId, 'b');
  });

  test('packs de cubo não repetem cartas entre packs', () {
    final cube = [for (var i = 0; i < 45; i++) 'c$i'];
    final packs = cubePacks(cube, 3, 15, Random(1));
    expect(packs.length, 3);
    expect(packs.expand((p) => p).toSet().length, 45);
  });
}
