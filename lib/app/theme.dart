import 'package:flutter/material.dart';

/// Paleta do EDHere (ver "Nome e identidade visual" no plano).
abstract final class EdhColors {
  static const seed = Color(0xFF2F6FEB);

  static const darkPrimary = Color(0xFF6EA8FF);
  static const darkPrimaryStrong = Color(0xFF2F6FEB);
  static const darkPrimarySoft = Color(0xFF16264A);
  static const darkBackground = Color(0xFF0B111C);
  static const darkSurface = Color(0xFF141C2B);
  static const darkSurfaceHigh = Color(0xFF1C2638);
  static const darkText = Color(0xFFE6EBF5);
  static const darkTextMuted = Color(0xFF93A0B8);
  static const darkOutline = Color(0xFF26324A);

  static const lightPrimary = Color(0xFF2F6FEB);
  static const lightPrimaryStrong = Color(0xFF1E4FB8);
  static const lightPrimarySoft = Color(0xFFE3ECFF);
  static const lightBackground = Color(0xFFF5F7FB);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceHigh = Color(0xFFEEF2F9);
  static const lightText = Color(0xFF0F172A);
  static const lightTextMuted = Color(0xFF5B6478);
  static const lightOutline = Color(0xFFD5DCE8);

  static const ok = Color(0xFF3FB27F);
  static const warn = Color(0xFFE0A63A);
  static const bad = Color(0xFFE5534B);
}

/// As cores do jogo, iguais nos dois temas (vivem por cima da mesa escura).
/// Cada uma quer dizer sempre o mesmo, em todas as mesas.
abstract final class GameColors {
  /// Uma cor por lugar (tu primeiro); escolhidas para se distinguirem também
  /// em daltonismo e pela luminosidade, não só pelo tom.
  static const players = [
    Color(0xFF3B7BF0),
    Color(0xFFE69F00),
    Color(0xFF56B4E9),
    Color(0xFFCC79A7),
    Color(0xFF2BB58F),
  ];
  static Color player(int seat) => players[seat % players.length];

  /// Atacantes, setas de ataque, vida perdida.
  static const attack = Color(0xFFE53935);
  static const block = Color(0xFF1E88E5);
  static const lifeGain = Color(0xFF43A047);

  /// O dano marcado numa criatura (fundo de um número branco).
  static const damage = Color(0xFFB71C1C);

  /// O que se pode jogar ou escolher agora.
  static const playable = Color(0xFFFFC107);

  /// Alvos escolhidos.
  static const target = Color(0xFFFF5A7A);

  /// As paragens na barra de fases.
  static const stop = Color(0xFFFF9800);

  /// Comandante, vencedor, destaques dourados.
  static const gold = Color(0xFFFFC107);

  static const counterPlus = Color(0xFF2E9E5B);
  static const counterMinus = Color(0xFFC0392B);
  static const counterLoyalty = Color(0xFF6C4BB6);
  static const counterOther = Color(0xFF455A64);
}

/// Medidas partilhadas: espaços numa grelha de 4, cantos e alturas de botão.
abstract final class EdhSize {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;

  /// Cantos: pequenos (chips, badges), médios (cartões, botões, campos) e
  /// grandes (folhas e diálogos). As cartas usam [cardCorner] da largura.
  static const radiusS = 8.0;
  static const radiusM = 14.0;
  static const radiusL = 28.0;

  /// O botão principal de um ecrã e os botões numa linha (barra da mesa, retomar).
  static const button = 52.0;
  static const buttonCompact = 40.0;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: EdhColors.seed,
    brightness: brightness,
  ).copyWith(
    primary: dark ? EdhColors.darkPrimary : EdhColors.lightPrimary,
    onPrimary: dark ? EdhColors.darkBackground : Colors.white,
    primaryContainer: dark ? EdhColors.darkPrimarySoft : EdhColors.lightPrimarySoft,
    onPrimaryContainer: dark ? EdhColors.darkPrimary : EdhColors.lightPrimaryStrong,
    surface: dark ? EdhColors.darkSurface : EdhColors.lightSurface,
    surfaceContainerHighest: dark ? EdhColors.darkSurfaceHigh : EdhColors.lightSurfaceHigh,
    surfaceContainerHigh: dark ? EdhColors.darkSurfaceHigh : EdhColors.lightSurfaceHigh,
    surfaceContainer: dark ? EdhColors.darkSurface : EdhColors.lightSurface,
    onSurface: dark ? EdhColors.darkText : EdhColors.lightText,
    onSurfaceVariant: dark ? EdhColors.darkTextMuted : EdhColors.lightTextMuted,
    outline: dark ? EdhColors.darkOutline : EdhColors.lightOutline,
    outlineVariant: dark ? EdhColors.darkOutline : EdhColors.lightOutline,
    error: EdhColors.bad,
  );
  final radius = BorderRadius.circular(EdhSize.radiusM);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? EdhColors.darkBackground : EdhColors.lightBackground,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? EdhColors.darkBackground : EdhColors.lightBackground,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardTheme(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(EdhSize.button),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(EdhSize.button),
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: scheme.outline),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.outline),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? EdhColors.darkSurfaceHigh : EdhColors.lightSurface,
      showDragHandle: true,
    ),
    dividerTheme: DividerThemeData(color: scheme.outline, space: 1),
  );
}
