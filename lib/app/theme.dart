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
  final radius = BorderRadius.circular(14);
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
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
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
