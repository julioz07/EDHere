import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:edhoff/data/app_paths.dart';
import 'package:edhoff/data/providers.dart';
import 'package:edhoff/game/game_controller.dart';
import 'package:edhoff/ui/table/table_screen.dart';
import 'package:edhoff/ui/table/table_sheets.dart';
import 'package:edhoff/ui/table/table_tour.dart';
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

  Future<GameController> pump(WidgetTester tester, Size size,
      {bool tour = false, void Function(GameController ctrl)? before}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // a visita à mesa tem o seu teste; nos outros já foi vista
    SharedPreferences.setMockInitialValues({'table_tour_done': !tour});
    final prefs = await SharedPreferences.getInstance();
    final ctrl = GameController.playtest(
      repo: repo,
      format: GameFormat.byId('commander'),
      seats: [
        for (final (i, n) in ['Gabriel', 'Cesar', 'José Maria Antunes', 'Maria'].indexed)
          SeatSetup(seat: i, name: n, deck: deck(n)),
      ],
    );
    if (before != null) {
      before(ctrl);
    } else {
      ctrl.openingDone.addAll([0, 1, 2, 3]);
    }
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

  for (final (name, size) in const [
    ('Small Phone', Size(360, 640)),
    ('Pixel Fold aberto', Size(944, 978)),
    ('Pixel Tablet deitado', Size(1280, 800)),
    ('Pixel Tablet ao alto', Size(800, 1280)),
  ]) {
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

  testWidgets('no tablet: um só campo, jogadores grandes e o registo ao lado', (tester) async {
    await pump(tester, const Size(1280, 800));
    expect(tester.takeException(), isNull);
    expect(find.byType(TableBattlefield), findsOneWidget);
    expect(find.bySemanticsLabel('Maria: 40 de vida'), findsOneWidget);
    expect(find.text('Registo'), findsOneWidget);
  });

  testWidgets('ao voltar a um jogo, quem já ficou com a mão não volta a ver o mulligan', (tester) async {
    await pump(tester, const Size(1280, 800), before: (ctrl) {
      // o anfitrião volta ao jogo: o "fiquei" está no estado, não no controlador
      for (final seat in [0, 1, 2, 3]) {
        ctrl.sendAs(seat, Intent(Ev.keepHand, {'seat': seat}));
      }
    });
    await tester.pump();
    expect(find.textContaining('MULLIGAN'), findsNothing);
  });

  testWidgets('a visita à mesa no primeiro jogo cabe num telemóvel de 360 e só aparece uma vez', (tester) async {
    await pump(tester, const Size(360, 640), tour: true);
    await tester.pump();
    expect(find.text('Os jogadores'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      // o balão fica sempre dentro do ecrã
      expect(tester.getRect(find.byType(TableTour)).contains(tester.getCenter(find.text('Seguinte'))), isTrue);
      await tester.tap(find.text('Seguinte'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Passar o turno'), findsOneWidget);
    await tester.tap(find.text('Começar a jogar'));
    await tester.pump();
    expect(find.text('Os jogadores'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('table_tour_done'), isTrue);
  });

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
