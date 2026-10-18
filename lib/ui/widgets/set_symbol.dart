import 'package:flutter/material.dart';

import 'set_glyphs.dart';

const _keyruneFont = 'Keyrune';

/// Símbolo de um set (fonte Keyrune), com a cor da raridade se for dada:
/// comum preto (branco no tema escuro), incomum prata, rara ouro e mítica
/// laranja, com o mesmo brilho dos símbolos impressos.
class SetSymbol extends StatelessWidget {
  const SetSymbol(this.code, {super.key, this.rarity, this.size = 20, this.color});

  /// Código do set (FRA, tdm...).
  final String code;

  /// `C`, `U`, `R`, `M` (ou `common`, `uncommon`...); null usa [color].
  final String? rarity;
  final double size;
  final Color? color;

  static bool exists(String code) => setGlyphs.containsKey(code.toLowerCase());

  static List<Color>? _gradient(String? rarity, Brightness b) => switch (rarity?.toLowerCase()) {
        'u' || 'uncommon' => const [Color(0xFF5A6572), Color(0xFF9E9E9E), Color(0xFF5A6572)],
        'r' || 'rare' => const [Color(0xFF876A3B), Color(0xFFDFBD6B), Color(0xFF876A3B)],
        'm' || 'mythic' => const [Color(0xFFB21F0F), Color(0xFFF38300), Color(0xFFB21F0F)],
        'c' || 'common' => b == Brightness.dark
            ? const [Color(0xFFBDBDBD), Color(0xFFF5F5F5), Color(0xFFBDBDBD)]
            : const [Color(0xFF302B2C), Color(0xFF474040), Color(0xFF302B2C)],
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final glyph = setGlyphs[code.toLowerCase()];
    if (glyph == null) {
      // Sets sem símbolo na Keyrune: um ícone genérico do mesmo tamanho.
      return Icon(Icons.style_outlined, size: size, color: color ?? IconTheme.of(context).color);
    }
    final text = Text(
      String.fromCharCode(glyph),
      style: TextStyle(
        fontFamily: _keyruneFont,
        fontSize: size,
        height: 1,
        color: color ?? IconTheme.of(context).color,
      ),
    );
    final colors = _gradient(rarity, Theme.of(context).brightness);
    if (colors == null) return text;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => LinearGradient(colors: colors).createShader(r),
      child: text,
    );
  }
}
