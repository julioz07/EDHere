import 'package:edhoff/app/theme.dart';
import 'package:edhoff/data/settings.dart';
import 'package:edhoff/ui/style/style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _classic = Key('classic');

Future<void> _pump(WidgetTester tester, UiStyle style, Widget child,
    {Brightness b = Brightness.dark, bool reduceMotion = false, double width = 360, double textScale = 1}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(b, style),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 640),
        disableAnimations: reduceMotion,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(body: Center(child: SizedBox(width: width, child: child))),
    ),
  ));
}

void main() {
  group('no Clássico cada peça devolve o widget de hoje', () {
    final cases = <String, Widget>{
      'SectionDivider': const SectionDivider('Com outros', classic: Text('Com outros', key: _classic)),
      'GoldPlate': const GoldPlate('40', classic: Text('40', key: _classic)),
      'StyleFrame': StyleFrame(
        classic: (child) => Card(key: _classic, child: child),
        child: const Text('dentro'),
      ),
      'TurnGlow': TurnGlow(
        active: true,
        classic: (child) => DecoratedBox(key: _classic, decoration: const BoxDecoration(), child: child),
        child: const Text('Ana'),
      ),
      'ManaOrb': const ManaOrb(color: Colors.red, classic: SizedBox(key: _classic, width: 8, height: 8)),
    };
    for (final MapEntry(key: name, value: w) in cases.entries) {
      testWidgets(name, (tester) async {
        await _pump(tester, UiStyle.classic, w);
        expect(find.byKey(_classic), findsOneWidget);
      });
    }

    testWidgets('LegendCrown não aparece', (tester) async {
      await _pump(tester, UiStyle.classic, const LegendCrown());
      expect(find.descendant(of: find.byType(LegendCrown), matching: find.byType(CustomPaint)), findsNothing);
    });

    testWidgets('TurnGlow sem classic devolve só o filho', (tester) async {
      await _pump(tester, UiStyle.classic, const TurnGlow(active: true, child: Text('Ana')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Ana'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('no Encantado aparece a peça do kit', () {
    for (final b in Brightness.values) {
      testWidgets('todas, ${b.name}', (tester) async {
        await _pump(
          tester,
          UiStyle.enchanted,
          b: b,
          Column(children: [
            const SectionDivider('Com outros', classic: Text('x', key: _classic)),
            const GoldPlate('40', classic: Text('y', key: _classic)),
            StyleFrame(highlighted: true, classic: (c) => Card(key: _classic, child: c), child: const Text('dentro')),
            const TurnGlow(active: true, child: Text('Ana')),
            const LegendCrown(),
            const ManaOrb(color: Colors.red),
          ]),
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(_classic), findsNothing);
        expect(find.text('COM OUTROS'), findsOneWidget);
        expect(find.text('40'), findsOneWidget);
        expect(find.text('dentro'), findsOneWidget);
        expect(find.text('Ana'), findsOneWidget);
      });
    }
  });

  testWidgets('StyleFrame aplica a margem só no Encantado (no Clássico é do classic)', (tester) async {
    Widget frame() => StyleFrame(
          margin: const EdgeInsets.only(bottom: 20),
          classic: (c) => Card(margin: EdgeInsets.zero, child: c),
          child: const SizedBox(width: 100, height: 40, key: Key('in')),
        );
    await _pump(tester, UiStyle.enchanted, Column(mainAxisSize: MainAxisSize.min, children: [frame(), const SizedBox(key: Key('after'))]));
    final inner = tester.getRect(find.byKey(const Key('in')));
    expect(tester.getTopLeft(find.byKey(const Key('after'))).dy, greaterThanOrEqualTo(inner.bottom + 20));
    await _pump(tester, UiStyle.classic, Column(mainAxisSize: MainAxisSize.min, children: [frame(), const SizedBox(key: Key('after'))]));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('after'))).dy, tester.getRect(find.byKey(const Key('in'))).bottom);
  });

  testWidgets('com "remover animações" o TurnGlow não anima', (tester) async {
    await _pump(tester, UiStyle.enchanted, const TurnGlow(active: true, child: Text('Ana')), reduceMotion: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('sem "remover animações" o TurnGlow respira', (tester) async {
    await _pump(tester, UiStyle.enchanted, const TurnGlow(active: true, child: Text('Ana')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('um título de secção longo não se parte em muitas linhas', (tester) async {
    await _pump(tester, UiStyle.enchanted, const SectionDivider('Com outros, cada um com o seu telemóvel', classic: SizedBox()),
        width: 312);
    final h = tester.getSize(find.textContaining('COM OUTROS')).height;
    expect(h, lessThan(3 * 13 * 1.6));
  });

  testWidgets('um título de secção curto fica ao centro', (tester) async {
    await _pump(tester, UiStyle.enchanted, const SectionDivider('Abrir boosters', classic: SizedBox()), width: 312);
    final text = tester.getCenter(find.text('ABRIR BOOSTERS'));
    final row = tester.getCenter(find.byType(SectionDivider));
    expect((text.dx - row.dx).abs(), lessThan(1));
  });

  testWidgets('GoldPlate de 3 dígitos cabe em 60 px com letra a 1,3×', (tester) async {
    await _pump(tester, UiStyle.enchanted, const GoldPlate('140', classic: SizedBox()), width: 60, textScale: 1.3);
    expect(tester.takeException(), isNull);
  });
}
