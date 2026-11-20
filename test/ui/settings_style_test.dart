import 'dart:io';

import 'package:edhoff/app/app.dart';
import 'package:edhoff/app/style_tokens.dart';
import 'package:edhoff/data/app_paths.dart';
import 'package:edhoff/data/providers.dart';
import 'package:edhoff/data/settings.dart';
import 'package:edhoff/ui/settings/ui_style_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          Text('n=$n ${context.edhStyle.isEnchanted ? 'encantado' : 'classico'}'),
          TextButton(onPressed: () => setState(() => n++), child: const Text('+')),
          // os botões do tema também passam pela transição (o lerp dos estilos de texto)
          FilledButton(onPressed: () {}, child: const Text('cheio')),
          OutlinedButton(onPressed: () {}, child: const Text('contorno')),
          const UiStyleSelector(),
        ]),
      );
}

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    prefs = await SharedPreferences.getInstance();
  });

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      prefsProvider.overrideWithValue(prefs),
      pathsProvider.overrideWithValue(AppPaths.forTest(Directory.systemTemp.path)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const EdhereMaterialApp(home: _Counter()),
    ));
    return container;
  }

  testWidgets('trocar de estilo muda o tema sem perder o estado do ecrã', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('+'));
    await tester.pump();
    expect(find.text('n=1 classico'), findsOneWidget);

    container.read(settingsProvider).uiStyle = UiStyle.enchanted;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('n=1 encantado'), findsOneWidget);
    container.read(settingsProvider).uiStyle = UiStyle.classic;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('n=1 classico'), findsOneWidget);
  });

  testWidgets('o seletor grava a escolha', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Encantado'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).uiStyle, UiStyle.enchanted);
    await tester.tap(find.text('Clássico'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).uiStyle, UiStyle.classic);
  });
}
