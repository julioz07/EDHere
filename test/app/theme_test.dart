import 'package:edhoff/app/gold_frame_border.dart';
import 'package:edhoff/app/style_tokens.dart';
import 'package:edhoff/app/theme.dart';
import 'package:edhoff/data/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Size? _minSize(ButtonStyle? s) => s?.minimumSize?.resolve({});

void main() {
  for (final b in Brightness.values) {
    final dark = b == Brightness.dark;

    test('Clássico ${b.name}: igual ao de hoje', () {
      for (final t in [buildTheme(b), buildTheme(b, UiStyle.classic)]) {
        expect(t.colorScheme.primary, dark ? EdhColors.darkPrimary : EdhColors.lightPrimary);
        expect(t.colorScheme.surface, dark ? EdhColors.darkSurface : EdhColors.lightSurface);
        expect(t.scaffoldBackgroundColor, dark ? EdhColors.darkBackground : EdhColors.lightBackground);
        expect(t.textTheme.bodyMedium?.fontFamily, isNot('Inter'));
        final shape = t.cardTheme.shape as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(EdhSize.radiusM));
        expect(_minSize(t.filledButtonTheme.style), const Size.fromHeight(EdhSize.button));
        expect(_minSize(t.outlinedButtonTheme.style), const Size.fromHeight(EdhSize.button));
        expect(t.extension<EdhStyle>(), same(dark ? EdhStyle.classicDark : EdhStyle.classicLight));
      }
    });

    test('Encantado ${b.name}: tokens, letras e molduras do kit', () {
      final t = buildTheme(b, UiStyle.enchanted);
      final s = t.extension<EdhStyle>()!;
      expect(s, same(dark ? EdhStyle.enchantedDark : EdhStyle.enchantedLight));
      expect(t.brightness, b);
      expect(t.scaffoldBackgroundColor, s.background);
      expect(t.textTheme.bodyMedium?.fontFamily, EdhFonts.body);
      expect(t.textTheme.titleLarge?.fontFamily, EdhFonts.display);
      expect(t.cardTheme.shape, isA<GoldFrameBorder>());
      expect(_minSize(t.filledButtonTheme.style), const Size.fromHeight(EdhSize.button));
      expect(t.filledButtonTheme.style?.backgroundBuilder, isNotNull);
      expect(_minSize(t.outlinedButtonTheme.style), const Size.fromHeight(EdhSize.button));
    });
  }

  testWidgets('o botão flutuante largo (+ Deck) não fica num círculo', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark, UiStyle.enchanted),
      home: Scaffold(
        floatingActionButton:
            FloatingActionButton.extended(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('Deck')),
      ),
    ));
    final size = tester.getSize(find.byType(FloatingActionButton));
    expect(size.width, greaterThan(size.height));
    final shape = tester.widget<RawMaterialButton>(find.byType(RawMaterialButton)).shape;
    expect(shape, isNot(isA<CircleBorder>()));
    final label = tester.getRect(find.text('Deck'));
    final fab = tester.getRect(find.byType(FloatingActionButton));
    expect(fab.contains(label.topLeft) && fab.contains(label.bottomRight), isTrue);
  });

  testWidgets('os botões e cartões do Encantado desenham-se sem erros', (tester) async {
    for (final b in Brightness.values) {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(b, UiStyle.enchanted),
        home: Scaffold(
          body: Column(children: [
            FilledButton(onPressed: () {}, child: const Text('Criar sala')),
            const FilledButton(onPressed: null, child: Text('Desligado')),
            OutlinedButton(onPressed: () {}, child: const Text('Entrar')),
            const Card(child: SizedBox(width: 100, height: 40)),
            const TextField(decoration: InputDecoration(labelText: 'Nome')),
          ]),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Criar sala'), findsOneWidget);
    }
  });
}
