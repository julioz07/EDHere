import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:edhoff/data/precons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cada deck base tem a lista e o número certo de cartas', () {
    for (final p in precons) {
      final format = GameFormat.byId(p.format);
      final text = File('assets/precons/${p.id}.txt').readAsStringSync();
      final lines = parseDeckText(text, hasCommandZone: format.hasCommandZone);
      final total = lines.fold(0, (n, l) => n + l.qty);
      expect(total, format.hasCommandZone ? 100 : 60, reason: p.id);
      if (format.hasCommandZone) {
        expect(lines.where((l) => l.board == Board.command).map((l) => l.name), [p.face], reason: p.id);
      } else {
        expect(lines.any((l) => l.name == p.face), isTrue, reason: p.id);
      }
      expect(p.about, isNotEmpty, reason: p.id);
    }
  });
}
