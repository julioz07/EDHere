import 'package:card_db/card_db.dart';
import 'package:flutter/material.dart';

import 'mana_glyphs.dart';

/// Cores dos círculos de custo (as do `ms-cost` do Mana).
abstract final class ManaPalette {
  static const w = Color(0xFFF0F2C0);
  static const u = Color(0xFFB5CDE3);
  static const b = Color(0xFFACA29A);
  static const r = Color(0xFFDB8664);
  static const g = Color(0xFF93B483);
  static const c = Color(0xFFBEB9B2);

  static Color of(String letter) => switch (letter.toUpperCase()) {
        'W' => w,
        'U' => u,
        'B' => b,
        'R' => r,
        'G' => g,
        _ => c,
      };
}

const _manaFont = 'Mana';
const _ink = Color(0xFF111111);

/// Um glifo qualquer da fonte Mana pelo nome da classe (sem "ms-"),
/// por exemplo `tap`, `counter-plus`, `ability-flying`.
class ManaIcon extends StatelessWidget {
  const ManaIcon(this.name, {super.key, this.size = 16, this.color});

  final String name;
  final double size;
  final Color? color;

  static bool exists(String name) => manaGlyphs.containsKey(name);

  @override
  Widget build(BuildContext context) {
    final code = manaGlyphs[name];
    if (code == null) return SizedBox.square(dimension: size);
    return Text(
      String.fromCharCode(code),
      style: TextStyle(
        fontFamily: _manaFont,
        fontSize: size,
        height: 1,
        color: color ?? IconTheme.of(context).color,
      ),
    );
  }
}

/// Classe do Mana para um símbolo do Scryfall ("W/U" -> "wu", "T" -> "tap").
String? manaClassFor(String symbol) {
  final s = symbol.toUpperCase();
  final name = switch (s) {
    'T' => 'tap',
    'Q' => 'untap',
    '∞' => 'infinity',
    '½' => '1-2',
    'PW' => 'planeswalker',
    'CHAOS' => 'chaos',
    'TK' => 'ticket',
    _ => s.replaceAll('/', '').toLowerCase(),
  };
  return manaGlyphs.containsKey(name) ? name : null;
}

/// Um símbolo de custo: círculo colorido com o glifo do Mana.
class ManaSymbol extends StatelessWidget {
  const ManaSymbol(this.symbol, {super.key, this.size = 16});

  final String symbol;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = symbol.toUpperCase().split('/');
    final colors = parts.where((p) => 'WUBRG'.contains(p) && p.length == 1).toList();
    final phyrexian = parts.contains('P');
    final hybrid = parts.length >= 2 && !(parts.length == 2 && phyrexian);

    Widget glyph(String name, double s) => Text(
          String.fromCharCode(manaGlyphs[name]!),
          style: TextStyle(fontFamily: _manaFont, fontSize: s, height: 1, color: _ink),
        );

    Widget? inner;
    BoxDecoration deco;
    if (hybrid) {
      // Híbrido: diagonal com as duas cores e os dois símbolos pequenos.
      final a = parts[0].toLowerCase(), b = parts[1].toLowerCase();
      final ca = 'WUBRG'.contains(parts[0]) ? ManaPalette.of(parts[0]) : ManaPalette.c;
      final cb = 'WUBRG'.contains(parts[1]) ? ManaPalette.of(parts[1]) : ManaPalette.c;
      deco = BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.5, 0.5],
          colors: [ca, cb],
        ),
      );
      if (manaGlyphs.containsKey(a) && manaGlyphs.containsKey(b)) {
        inner = Stack(children: [
          Positioned(left: size * 0.12, top: size * 0.08, child: glyph(a, size * 0.45)),
          Positioned(right: size * 0.12, bottom: size * 0.1, child: glyph(b, size * 0.45)),
        ]);
      }
    } else {
      final name = phyrexian ? 'p' : manaClassFor(symbol);
      deco = BoxDecoration(
        shape: BoxShape.circle,
        color: colors.isEmpty ? ManaPalette.c : ManaPalette.of(colors.first),
      );
      if (name != null) inner = Center(child: glyph(name, size * 0.68));
    }

    // Símbolo que a fonte não tem: letra simples.
    inner ??= Center(
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child:
              Text(symbol, style: TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: size * 0.6)),
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 0.6),
      decoration: deco.copyWith(
        boxShadow: const [BoxShadow(color: Colors.black38, offset: Offset(-0.5, 0.8))],
      ),
      child: inner,
    );
  }
}

class ManaCost extends StatelessWidget {
  const ManaCost(this.cost, {super.key, this.size = 16});

  final String cost;
  final double size;

  @override
  Widget build(BuildContext context) {
    final symbols = parseManaSymbols(cost);
    if (symbols.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in symbols)
          s == '//'
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Text('//', style: TextStyle(fontSize: size * 0.8)),
                )
              : ManaSymbol(s, size: size),
      ],
    );
  }
}

/// Texto Oracle com os símbolos {X} desenhados em linha.
class OracleText extends StatelessWidget {
  const OracleText(this.text, {super.key, this.style, this.maxLines, this.overflow});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final size = (base.fontSize ?? 14) * 1.05;
    final spans = <InlineSpan>[];
    final re = RegExp(r'\{([^}]+)\}');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: ManaSymbol(m.group(1)!, size: size),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(children: spans), style: base, maxLines: maxLines, overflow: overflow);
  }
}

/// Identidade de cor como símbolos de mana.
class ColorIdentity extends StatelessWidget {
  const ColorIdentity(this.mask, {super.key, this.size = 14});

  final int mask;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letters = ManaColors.lettersOf(mask);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (letters.isEmpty) ManaSymbol('C', size: size),
      for (final l in letters) ManaSymbol(l, size: size),
    ]);
  }
}

/// Ícone de habilidade do Mana para uma palavra-chave ("Flying" ->
/// `ability-flying`), ou null se a fonte não tiver.
String? abilityIconFor(String keyword) {
  final name = 'ability-${keyword.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
  return manaGlyphs.containsKey(name) ? name : null;
}

/// Ícone do Mana para um tipo de contador.
String? counterIconFor(String kind) {
  final k = kind.toLowerCase();
  final name = switch (k) {
    '+1/+1' => 'counter-plus',
    '-1/-1' => 'counter-minus',
    'loyalty' => 'counter-loyalty',
    _ => 'counter-$k',
  };
  return manaGlyphs.containsKey(name) ? name : null;
}
