import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:edhoff/bot/forge_engine.dart';
import 'package:edhoff/data/app_paths.dart';
import 'package:edhoff/data/providers.dart';
import 'package:edhoff/bot/forge_table.dart';
import 'package:edhoff/ui/bot/bot_dialogs.dart';
import 'package:edhoff/ui/bot/bot_table_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

Map<String, Object?> _c(int id, String name, String zone, int owner) =>
    {'id': id, 'n': name, 'z': zone, 'ow': owner, 'c': owner};

/// Um alvo no cemitério (Goblin Dark-Dwellers): o Forge desliga OK e Cancelar até
/// se tocar num alvo, por isso tem de se conseguir escolher a carta a partir do cemitério.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CardRepository repo;
  late Directory dir;
  MockStreamHandlerEventSink? sink;
  final acts = <Map>[];

  setUpAll(() async {
    _setUpSqlite();
    dir = Directory.systemTemp.createTempSync('botzone');
    final imp = CardImporter('${dir.path}/cards.sqlite')..open();
    await imp.importLines(Stream.fromIterable([
      _card('Goblin Dark-Dwellers', 'Creature — Goblin'),
      _card('Lightning Bolt', 'Instant'),
      _card('Grizzly Bears', 'Creature — Bear'),
      _card('Mountain', 'Basic Land — Mountain'),
    ].map(jsonEncode)));
    imp.finish({'bulk_updated_at': 'test'});
    repo = CardRepository.open('${dir.path}/cards.sqlite')!;
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('edhere/forge'), (call) async {
      if (call.method == 'act') acts.add(call.arguments as Map);
      return null;
    });
    m.setMockMessageHandler('dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async => const StandardMessageCodec().encodeMessage(<Object?>[]));
    m.setMockStreamHandler(
      const EventChannel('edhere/forge/events'),
      MockStreamHandler.inline(onListen: (_, s) {
        sink = s;
      }),
    );
  });

  Map<String, Object?> prompt({
    String input = 'select',
    List<int> sel = const [],
    List<int> play = const [],
    String msg = 'Goblin Dark-Dwellers - Choose target instant or sorcery card',
  }) =>
      {
        'type': 'prompt',
        'turn': 5,
        'phase': 'MAIN1',
        'active': 1,
        'priority': 1,
        'msg': msg,
        'ok': {'label': 'OK', 'on': false},
        'cancel': {'label': 'Cancelar', 'on': false},
        'input': input,
        'sel': sel,
        'selP': <int>[],
        'chosen': <int>[],
        'play': play,
        'players': [
          {'id': 1, 'name': 'Julio', 'life': 18, 'hand': 1, 'library': 80},
          {'id': 2, 'name': 'Bot', 'life': 32, 'hand': 5, 'library': 71},
        ],
        'cards': [
          _c(10, 'Goblin Dark-Dwellers', 'battlefield', 1),
          _c(21, 'Grizzly Bears', 'graveyard', 1),
          _c(20, 'Lightning Bolt', 'graveyard', 1),
        ],
        'stack': <Object>[],
        'log': <String>[],
      };

  Future<void> pumpTable(WidgetTester tester, Map<String, Object?> event) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    acts.clear();
    SharedPreferences.setMockInitialValues({'table_tour_done': true});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        pathsProvider.overrideWithValue(AppPaths.forTest(dir.path)),
        cardRepoProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(
        home: BotTableScreen(
          seats: [
            ForgeSeat(name: 'Julio', deck: Deck(name: 'a', format: 'commander')),
            ForgeSeat(name: 'Bot', deck: Deck(name: 'b', format: 'commander'), bot: BotLevel.normal),
          ],
          commander: true,
        ),
      ),
    ));
    await tester.pump();
    sink!.success(event);
    // o evento atravessa o canal fora do tempo falso dos testes
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3)); // a moeda ao ar e as animações
  }

  /// Abre o cemitério pelo contador da barra do jogador (o último desenhado é o meu).
  Future<void> openGraveyard(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Finder sheetCard(String name) =>
      find.descendant(of: find.byType(BottomSheet), matching: find.text(name)).first;

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('o alvo pedido escolhe-se a partir do cemitério', (tester) async {
    await pumpTable(tester, prompt(sel: [20]));
    await openGraveyard(tester);
    await tester.tap(sheetCard('Lightning Bolt'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(acts, [
      {'kind': 'card', 'id': 20}
    ]);
    expect(find.byType(BottomSheet), findsNothing, reason: 'a folha fecha depois de escolher');
    await finish(tester);
  });

  testWidgets('uma carta do cemitério que não é alvo não envia nada', (tester) async {
    await pumpTable(tester, prompt(sel: [20]));
    await openGraveyard(tester);
    await tester.tap(sheetCard('Grizzly Bears'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(acts, isEmpty);
    await finish(tester);
  });

  testWidgets('com a prioridade, uma carta jogável do cemitério (flashback) joga-se', (tester) async {
    await pumpTable(tester, prompt(input: 'priority', play: [20], msg: 'Priority'));
    await openGraveyard(tester);
    await tester.tap(sheetCard('Lightning Bolt'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(acts, [
      {'kind': 'card', 'id': 20}
    ]);
    await finish(tester);
  });

  testWidgets('o aviso de alvo inválido não mostra o código do Forge', (tester) async {
    await pumpTable(
        tester,
        prompt(
            sel: [20],
            msg: 'Goblin Dark-Dwellers - The selected card is not an Instant.YouCtrl+cmcLE3 or Sorcery.YouCtrl+cmcLE3.'));
    expect(find.textContaining('YouCtrl', findRichText: true), findsNothing);
    await finish(tester);
  });

  testWidgets('quando o alvo só está no cemitério, a barra leva até lá', (tester) async {
    await pumpTable(tester, prompt(sel: [20]));
    final go = find.text('Cemitério (1)');
    expect(go, findsOneWidget);
    await tester.tap(go);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(sheetCard('Lightning Bolt'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(acts, [
      {'kind': 'card', 'id': 20}
    ]);
    await finish(tester);
  });

  testWidgets('sem botões e sem nada em que tocar, a mesa oferece saltar o passo', (tester) async {
    await pumpTable(tester, prompt());
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Saltar'));
    await tester.pump();
    expect(acts, [
      {'kind': 'cancel'}
    ]);
    await finish(tester);
  });

  testWidgets('com alvos à vista, saltar só aparece se a escolha se arrastar', (tester) async {
    await pumpTable(tester, prompt(sel: [20]));
    expect(find.text('Saltar'), findsNothing);
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('Saltar'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Saltar'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('no mulligan nunca se oferece saltar', (tester) async {
    await pumpTable(tester, prompt(input: 'bottom', sel: [10], msg: '1'));
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Saltar'), findsNothing);
    await finish(tester);
  });

  testWidgets('uma carta a escolher que a mesa não mostra escolhe-se pelo nome', (tester) async {
    await pumpTable(tester, {
      ...prompt(sel: [99]),
      'selOut': [
        {'id': 99, 'n': 'Grizzly Bears'}
      ],
    });
    await tester.tap(find.text('Outras cartas (1)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.textContaining('Grizzly', findRichText: true)).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(acts, [
      {'kind': 'card', 'id': 99}
    ]);
    await finish(tester);
  });

  group('perguntas', () {
    Object? result = 'por responder';
    Future<void> openAsk(WidgetTester tester, Map<String, Object?> ask, {Size size = const Size(412, 900)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      result = 'por responder';
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showForgeAsk(context, ForgeAsk.fromMap({'id': 1, ...ask}), ForgeCardLookup(repo), null);
            },
            child: const Text('abrir'),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    List<Map<String, Object?>> labels(int n) => [
          for (var i = 0; i < n; i++) {'label': 'Opção $i'}
        ];

    testWidgets('a tecla de voltar não responde por ti', (tester) async {
      await openAsk(tester, {'kind': 'confirm', 'msg': 'Queres?'});
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Queres?', findRichText: true), findsOneWidget);
      expect(result, 'por responder');
    });

    testWidgets('pedir mais do que há: basta escolher tudo o que há', (tester) async {
      await openAsk(tester, {'kind': 'choose', 'min': 3, 'max': 3, 'options': labels(2)});
      await tester.tap(find.text('Opção 0', findRichText: true));
      await tester.tap(find.text('Opção 1', findRichText: true));
      await tester.pump();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(result, [0, 1]);
    });

    testWidgets('um número inválido não se pode confirmar', (tester) async {
      await openAsk(tester, {'kind': 'input', 'title': 'Quantos?', 'numeric': true, 'initial': ''});
      Finder confirm() => find.widgetWithText(FilledButton, 'Confirmar');
      expect(tester.widget<FilledButton>(confirm()).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm()).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '2');
      await tester.pump();
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(result, '2');
    });

    testWidgets('dividir menos do que os alvos não dá valores negativos', (tester) async {
      await openAsk(tester, {'kind': 'distribute', 'amount': 1, 'atLeastOne': true, 'options': labels(3)});
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(result, [1, 0, 0]);
    });

    testWidgets('um título enorme num ecrã pequeno não esconde os botões', (tester) async {
      await openAsk(
        tester,
        {'kind': 'choose', 'min': 2, 'max': 2, 'title': 'Texto muito comprido. ' * 80, 'options': labels(8)},
        size: const Size(360, 640),
      );
      expect(tester.takeException(), isNull);
      final button = tester.getRect(find.text('Confirmar'));
      expect(button.bottom, lessThanOrEqualTo(640));
    });
  });
}
