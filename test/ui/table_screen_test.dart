import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:edhoff/data/app_paths.dart';
import 'package:edhoff/data/providers.dart';
import 'package:edhoff/game/game_controller.dart';
import 'package:edhoff/ui/table/table_screen.dart';
import 'package:edhoff/ui/table/table_sheets.dart';
import 'package:flutter/material.dart' hide Intent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesa_core/mesa_core.dart' hide Table;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';

void _setUpSqlite() {
  if (!Platform.isWindows) return;
  for (final p in [Platform.environment['SQLITE3_DLL'], r'C:\Python313\DLLs\sqlite3.dll']) {
    if (p != null && File(p).existsSync()) {
      open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(p));
      return;
    }
  }
}

Map<String, dynamic> _card(String name, String type) => {
      'id': 'p-$name',
      'oracle_id': 'o-$name',
      'name': name,
      'layout': 'normal',
      'type_line': type,
      'oracle_text': '',
      'mana_cost': '',
      'cmc': 0,
      'colors': <String>[],
      'color_identity': <String>[],
      'legalities': {'commander': 'legal'},
      'games': ['paper'],
    };

/// A mesa de 4 jogadores nos ecrãs dos testers: sem overflows e com os avisos novos.
void main() {
  late CardRepository repo;
  late Directory dir;
  setUpAll(() async {
    _setUpSqlite();
    dir = Directory.systemTemp.createTempSync('tablescreen');
    final imp = CardImporter('${dir.path}/cards.sqlite')..open();
    await imp.importLines(Stream.fromIterable([
      _card('Boss', 'Legendary Creature — Goblin'),
      for (var i = 0; i < 12; i++) _card('Card$i', 'Creature — Goblin'),
      _card('Mountain', 'Basic Land — Mountain'),
    ].map(jsonEncode)));
    imp.finish({'bulk_updated_at': 'test'});
    repo = CardRepository.open('${dir.path}/cards.sqlite')!;
  });

  Deck deck(String name) {
    var d = Deck(name: name, format: 'commander').add('o-Boss', board: Board.command);
    for (var i = 0; i < 12; i++) {
      d = d.add('o-Card$i');
    }
    return d.add('o-Mountain', qty: 30);
  }

  Future<GameController> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final ctrl = GameController.playtest(
      repo: repo,
      format: GameFormat.byId('commander'),
      seats: [
        for (final (i, n) in ['Gabriel', 'Cesar', 'José Maria Antunes', 'Maria'].indexed)
          SeatSetup(seat: i, name: n, deck: deck(n)),
      ],
    );
    ctrl.openingDone.addAll([0, 1, 2, 3]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        pathsProvider.overrideWithValue(AppPaths.forTest(dir.path)),
      ],
      child: MaterialApp(home: TableScreen(ctrl: ctrl)),
    ));
    await tester.pump();
    return ctrl;
  }

  for (final (name, size) in const [('Small Phone', Size(360, 640)), ('Pixel Fold aberto', Size(944, 978))]) {
    testWidgets('4 jogadores no $name: cabe tudo e os avisos aparecem', (tester) async {
      final ctrl = await pump(tester, size);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Ronda 1'), findsOneWidget);

      // Aos 0 de vida o aviso fica à vista até se responder.
      ctrl.sendAs(0, const Intent(Ev.life, {'seat': 0, 'delta': -40}));
      await tester.pump();
      expect(find.textContaining('0 de vida'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      expect(find.textContaining('0 de vida'), findsOneWidget, reason: 'não desaparece sozinho');

      // Só resta um: propõe o vencedor.
      for (final s in [0, 1, 2]) {
        ctrl.sendAs(s, Intent(Ev.defeated, {'seat': s, 'value': true}));
      }
      await tester.pump();
      expect(find.textContaining('Só resta Maria'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a folha do jogador cabe num telemóvel de 360 (os −5 e +5 ficavam cortados)', (tester) async {
    final ctrl = await pump(tester, const Size(360, 640));
    showPlayerSheet(tester.element(find.byType(TableScreen)), ctrl, 0);
    await tester.pumpAndSettle();
    expect(find.text('-5'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final right = tester.getRect(find.text('+5')).right;
    expect(right, lessThanOrEqualTo(360));
    expect(tester.getRect(find.text('-5')).left, greaterThanOrEqualTo(0));
  });
}
