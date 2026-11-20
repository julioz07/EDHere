import 'package:flutter/material.dart';

import '../data/settings.dart';
import 'theme.dart';

/// O estilo ativo e as cores do kit "Encantado" (docs/design/ui-encantada).
/// Está nos quatro temas (Clássico/Encantado × Claro/Escuro): no Clássico as
/// cores apontam para as de sempre, para uma peça poder lê-las sem `if`.
@immutable
class EdhStyle extends ThemeExtension<EdhStyle> {
  const EdhStyle({
    required this.style,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.field,
    required this.gold,
    required this.goldLight,
    required this.goldPale,
    required this.goldDeep,
    required this.goldText,
    required this.plateLight,
    required this.arcane,
    required this.arcaneLight,
    required this.arcaneDeep,
    required this.text,
    required this.textMuted,
    required this.textOnGold,
    required this.success,
  });

  final UiStyle style;
  bool get isEnchanted => style == UiStyle.enchanted;

  /// Fundo da app e das molduras (gradiente de [surfaceHigh] para [surface]).
  final Color background, surface, surfaceHigh;

  /// Campos de texto e ranhuras de zona.
  final Color field;

  /// Fios de ouro, ouro do separador ativo, brilho das gemas, contorno das plaquetas.
  final Color gold, goldLight, goldPale, goldDeep;

  /// Ouro para texto: no claro é mais escuro, para se ler sobre o pergaminho.
  final Color goldText;

  /// Topo das plaquetas douradas.
  final Color plateLight;

  /// O azul EDHere do botão "gema".
  final Color arcane, arcaneLight, arcaneDeep;

  final Color text, textMuted, textOnGold, success;

  static const enchantedDark = EdhStyle(
    style: UiStyle.enchanted,
    background: Color(0xFF0A0D18),
    surface: Color(0xFF121831),
    surfaceHigh: Color(0xFF1C2442),
    field: Color(0xFF0E1326),
    gold: Color(0xFFD8B868),
    goldLight: Color(0xFFE8CB80),
    goldPale: Color(0xFFFBEBB8),
    goldDeep: Color(0xFF8A6A2E),
    goldText: Color(0xFFE8CB80),
    plateLight: Color(0xFFFFF6DA),
    arcane: Color(0xFF4682F2),
    arcaneLight: Color(0xFF86B6FF),
    arcaneDeep: Color(0xFF2149B8),
    text: Color(0xFFF2ECDD),
    textMuted: Color(0xFFA9B0C8),
    textOnGold: Color(0xFF1A120C),
    success: Color(0xFF4CC074),
  );

  /// Pergaminho, com o mesmo dourado (mais escuro onde é texto).
  static const enchantedLight = EdhStyle(
    style: UiStyle.enchanted,
    background: Color(0xFFF4EEDF),
    surface: Color(0xFFFFFBF0),
    surfaceHigh: Color(0xFFF1E7CF),
    field: Color(0xFFFBF5E6),
    gold: Color(0xFFA9822F),
    goldLight: Color(0xFFC79F48),
    goldPale: Color(0xFFE8CB80),
    goldDeep: Color(0xFF8A6A2E),
    goldText: Color(0xFF7E5F1F),
    plateLight: Color(0xFFFFF6DA),
    arcane: Color(0xFF2F6FEB),
    arcaneLight: Color(0xFF6EA8FF),
    arcaneDeep: Color(0xFF1E4FB8),
    text: Color(0xFF2A2116),
    textMuted: Color(0xFF6B6150),
    textOnGold: Color(0xFF1A120C),
    success: Color(0xFF2E9E5B),
  );

  static const classicDark = EdhStyle(
    style: UiStyle.classic,
    background: EdhColors.darkBackground,
    surface: EdhColors.darkSurface,
    surfaceHigh: EdhColors.darkSurfaceHigh,
    field: EdhColors.darkSurface,
    gold: GameColors.gold,
    goldLight: GameColors.gold,
    goldPale: GameColors.gold,
    goldDeep: GameColors.gold,
    goldText: GameColors.gold,
    plateLight: EdhColors.darkSurfaceHigh,
    arcane: EdhColors.darkPrimaryStrong,
    arcaneLight: EdhColors.darkPrimary,
    arcaneDeep: EdhColors.darkPrimaryStrong,
    text: EdhColors.darkText,
    textMuted: EdhColors.darkTextMuted,
    textOnGold: EdhColors.darkBackground,
    success: EdhColors.ok,
  );

  static const classicLight = EdhStyle(
    style: UiStyle.classic,
    background: EdhColors.lightBackground,
    surface: EdhColors.lightSurface,
    surfaceHigh: EdhColors.lightSurfaceHigh,
    field: EdhColors.lightSurface,
    gold: GameColors.gold,
    goldLight: GameColors.gold,
    goldPale: GameColors.gold,
    goldDeep: GameColors.gold,
    goldText: EdhColors.lightPrimaryStrong,
    plateLight: EdhColors.lightSurfaceHigh,
    arcane: EdhColors.lightPrimary,
    arcaneLight: EdhColors.lightPrimary,
    arcaneDeep: EdhColors.lightPrimaryStrong,
    text: EdhColors.lightText,
    textMuted: EdhColors.lightTextMuted,
    textOnGold: EdhColors.lightText,
    success: EdhColors.ok,
  );

  static EdhStyle of(UiStyle style, Brightness b) => switch ((style, b)) {
        (UiStyle.enchanted, Brightness.dark) => enchantedDark,
        (UiStyle.enchanted, Brightness.light) => enchantedLight,
        (UiStyle.classic, Brightness.dark) => classicDark,
        (UiStyle.classic, Brightness.light) => classicLight,
      };

  @override
  EdhStyle copyWith({UiStyle? style}) => style == null || style == this.style ? this : of(style, _brightness);

  Brightness get _brightness =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark ? Brightness.dark : Brightness.light;

  @override
  EdhStyle lerp(ThemeExtension<EdhStyle>? other, double t) {
    if (other is! EdhStyle) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return EdhStyle(
      style: t < 0.5 ? style : other.style,
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      field: l(field, other.field),
      gold: l(gold, other.gold),
      goldLight: l(goldLight, other.goldLight),
      goldPale: l(goldPale, other.goldPale),
      goldDeep: l(goldDeep, other.goldDeep),
      goldText: l(goldText, other.goldText),
      plateLight: l(plateLight, other.plateLight),
      arcane: l(arcane, other.arcane),
      arcaneLight: l(arcaneLight, other.arcaneLight),
      arcaneDeep: l(arcaneDeep, other.arcaneDeep),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      textOnGold: l(textOnGold, other.textOnGold),
      success: l(success, other.success),
    );
  }
}

extension EdhStyleX on BuildContext {
  EdhStyle get edhStyle => Theme.of(this).extension<EdhStyle>() ?? EdhStyle.classicDark;
}

/// As famílias do Encantado (em assets/fonts; a app é offline).
abstract final class EdhFonts {
  static const display = 'Cinzel';
  static const flavor = 'CrimsonPro';
  static const body = 'Inter';
}

/// A escala de texto do kit. Sem cor: quem usa junta a do token.
abstract final class EdhText {
  static const display = TextStyle(fontFamily: EdhFonts.display, fontWeight: FontWeight.w800, fontSize: 30, height: 1.0);
  static const screenTitle = TextStyle(fontFamily: EdhFonts.display, fontWeight: FontWeight.w800, fontSize: 22);
  static const title = TextStyle(fontFamily: EdhFonts.display, fontWeight: FontWeight.w700, fontSize: 17);
  static const button =
      TextStyle(fontFamily: EdhFonts.display, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: .6);
  static const section =
      TextStyle(fontFamily: EdhFonts.display, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 1.8);
  static const plate = TextStyle(fontFamily: EdhFonts.display, fontWeight: FontWeight.w800, fontSize: 19);
  static const flavor =
      TextStyle(fontFamily: EdhFonts.flavor, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500, fontSize: 16);
  static const body = TextStyle(fontFamily: EdhFonts.body, fontWeight: FontWeight.w400, fontSize: 15);
  static const label = TextStyle(fontFamily: EdhFonts.body, fontWeight: FontWeight.w500, fontSize: 12);
}
