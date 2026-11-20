import 'dart:math' as math;

import 'package:edhoff/app/style_tokens.dart';
import 'package:edhoff/data/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.red / 255) + 0.7152 * ch(c.green / 255) + 0.0722 * ch(c.blue / 255);
}

double _contrast(Color a, Color b) {
  final (la, lb) = (_lum(a), _lum(b));
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (name, t) in [('escuro', EdhStyle.enchantedDark), ('claro', EdhStyle.enchantedLight)]) {
    test('Encantado $name: texto legível (≥ 4,5:1)', () {
      for (final (what, fg, bg) in [
        ('text/surface', t.text, t.surface),
        ('text/surfaceHigh', t.text, t.surfaceHigh),
        ('textMuted/surface', t.textMuted, t.surface),
        ('goldText/surface', t.goldText, t.surface),
        ('goldText/background', t.goldText, t.background),
        ('textOnGold/plateLight', t.textOnGold, t.plateLight),
        ('textOnGold/goldLight', t.textOnGold, t.goldLight),
      ]) {
        expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$name $what');
      }
    });
  }

  test('os quatro conjuntos dizem o seu estilo', () {
    expect(EdhStyle.classicDark.isEnchanted, isFalse);
    expect(EdhStyle.classicLight.isEnchanted, isFalse);
    expect(EdhStyle.enchantedDark.isEnchanted, isTrue);
    expect(EdhStyle.enchantedLight.style, UiStyle.enchanted);
  });

  test('lerp nos extremos devolve cada lado', () {
    final a = EdhStyle.enchantedDark, b = EdhStyle.enchantedLight;
    expect(a.lerp(b, 0).gold, a.gold);
    expect(a.lerp(b, 1).gold, b.gold);
    expect(a.lerp(b, 1).style, b.style);
  });

  testWidgets('context.edhStyle lê a extensão do tema', (tester) async {
    late EdhStyle got;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [EdhStyle.enchantedLight]),
      home: Builder(builder: (c) {
        got = c.edhStyle;
        return const SizedBox();
      }),
    ));
    expect(got, same(EdhStyle.enchantedLight));
  });
}
