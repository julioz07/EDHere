import 'package:flutter/material.dart';

import 'gold_frame_border.dart';
import 'gold_tab_indicator.dart';
import 'style_tokens.dart';
import 'theme.dart';

/// O tema do estilo Encantado (kit em docs/design/ui-encantada). Só muda a
/// pele: os tamanhos mínimos dos botões e campos são os do Clássico.
ThemeData buildEnchantedTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? EdhStyle.enchantedDark : EdhStyle.enchantedLight;
  final radius = BorderRadius.circular(12);

  final scheme = ColorScheme.fromSeed(seedColor: c.arcane, brightness: brightness).copyWith(
    primary: dark ? c.arcaneLight : c.arcane,
    onPrimary: dark ? c.background : Colors.white,
    primaryContainer: dark ? const Color(0xFF1B2A55) : const Color(0xFFE3ECFF),
    onPrimaryContainer: dark ? c.arcaneLight : c.arcaneDeep,
    secondary: c.gold,
    onSecondary: c.textOnGold,
    secondaryContainer: dark ? const Color(0xFF3A3020) : const Color(0xFFF5E6BF),
    onSecondaryContainer: c.goldText,
    surface: c.surface,
    onSurface: c.text,
    onSurfaceVariant: c.textMuted,
    surfaceContainerLowest: c.background,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surfaceHigh,
    surfaceContainerHighest: c.surfaceHigh,
    outline: c.gold.withOpacity(.45),
    outlineVariant: c.gold.withOpacity(.25),
    error: EdhColors.bad,
  );

  final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme, fontFamily: EdhFonts.body);
  // Os estilos dos componentes têm de ter inherit: false, como os do Material:
  // senão a transição Clássico ↔ Encantado não consegue interpolá-los.
  final solid = Typography.englishLike2021.bodyMedium!.copyWith(fontFamily: EdhFonts.body, color: c.text);
  TextStyle k(TextStyle s) => solid.merge(s);
  TextStyle? display(TextStyle? s, FontWeight w) =>
      s?.copyWith(fontFamily: EdhFonts.display, fontWeight: w, color: c.text);
  final text = base.textTheme.copyWith(
    displayLarge: display(base.textTheme.displayLarge, FontWeight.w800),
    displayMedium: display(base.textTheme.displayMedium, FontWeight.w800),
    displaySmall: display(base.textTheme.displaySmall, FontWeight.w800),
    headlineLarge: display(base.textTheme.headlineLarge, FontWeight.w800),
    headlineMedium: display(base.textTheme.headlineMedium, FontWeight.w700),
    headlineSmall: display(base.textTheme.headlineSmall, FontWeight.w700),
    titleLarge: display(base.textTheme.titleLarge, FontWeight.w700),
  );

  final frame = GoldFrameBorder(gold: c.gold);

  // Botão "gema": gradiente azul, fio de ouro e letra Cinzel.
  Widget gem(BuildContext context, Set<WidgetState> states, Widget? child) {
    final off = states.contains(WidgetState.disabled);
    final down = states.contains(WidgetState.pressed);
    final colors = off
        ? [c.surfaceHigh, c.surface]
        : down
            ? [c.arcane, c.arcaneDeep]
            : [c.arcaneLight, c.arcane, c.arcaneDeep];
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: colors.length == 3 ? const [0, .42, 1] : null,
        ),
        boxShadow: off ? null : [BoxShadow(color: c.arcane.withOpacity(down ? .55 : .35), blurRadius: down ? 20 : 14)],
      ),
      child: child,
    );
  }

  // Botão "obsidiana": fundo da moldura e fio de ouro.
  Widget obsidian(BuildContext context, Set<WidgetState> states, Widget? child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: states.contains(WidgetState.pressed) ? [c.surface, c.surfaceHigh] : [c.surfaceHigh, c.surface],
          ),
        ),
        child: child,
      );

  WidgetStateProperty<BorderSide?> goldSide(double alpha) => WidgetStateProperty.resolveWith((s) => BorderSide(
        color: s.contains(WidgetState.disabled)
            ? c.gold.withOpacity(.25)
            : s.contains(WidgetState.pressed)
                ? c.goldLight
                : c.gold.withOpacity(alpha),
        width: s.contains(WidgetState.pressed) ? 1.5 : 1.2,
      ));

  final buttonText = k(EdhText.button.copyWith(fontSize: 16));

  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    textTheme: text,
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.text,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: k(EdhText.title.copyWith(color: c.text, fontSize: 20)),
      shape: Border(bottom: BorderSide(color: c.gold.withOpacity(.35))),
    ),
    cardTheme: CardTheme(color: c.surface, elevation: 0, margin: EdgeInsets.zero, shape: frame),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(EdhSize.button)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
        side: goldSide(1),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.textMuted : Colors.white),
        overlayColor: WidgetStatePropertyAll(Colors.white.withOpacity(.08)),
        textStyle: WidgetStatePropertyAll(buttonText),
        backgroundBuilder: gem,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(EdhSize.button)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
        side: goldSide(.65),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.goldText.withOpacity(.4) : c.goldText),
        overlayColor: WidgetStatePropertyAll(c.goldLight.withOpacity(.08)),
        textStyle: WidgetStatePropertyAll(buttonText.copyWith(fontWeight: FontWeight.w700)),
        backgroundBuilder: obsidian,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.goldText,
        textStyle: buttonText.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.field,
      labelStyle: k(EdhText.section.copyWith(color: c.goldText, fontSize: 12)),
      floatingLabelStyle: k(EdhText.section.copyWith(color: c.goldText, fontSize: 12)),
      hintStyle: k(EdhText.body.copyWith(color: c.textMuted)),
      helperStyle: k(EdhText.label.copyWith(color: c.textMuted)),
      prefixIconColor: c.gold,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.gold.withOpacity(.45))),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.gold.withOpacity(.45))),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.goldLight, width: 1.5)),
    ),
    tabBarTheme: TabBarTheme(
      labelColor: c.goldText,
      unselectedLabelColor: c.textMuted,
      // Inter e não Cinzel: a Cinzel é larga e "Estatísticas" já não cabia em 3
      // separadores a 360 dp. O dourado e o indicador ficam.
      labelStyle: k(EdhText.label.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
      unselectedLabelStyle: k(EdhText.label.copyWith(fontSize: 14, fontWeight: FontWeight.w500)),
      indicator: GoldTabIndicator(color: c.goldLight, gem: c.goldPale),
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: c.gold.withOpacity(.3),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.arcane,
      indicatorShape: StadiumBorder(side: BorderSide(color: c.gold, width: 1.5)),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Colors.white : c.textMuted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => k(EdhText.label.copyWith(
            color: s.contains(WidgetState.selected) ? c.goldText : c.textMuted,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ))),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: c.gold.withOpacity(.6))),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.goldLight : c.field),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.textOnGold : c.text),
        textStyle: WidgetStatePropertyAll(k(EdhText.label.copyWith(fontSize: 14, fontWeight: FontWeight.w600))),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.field,
      selectedColor: c.goldLight,
      side: BorderSide(color: c.gold.withOpacity(.5)),
      labelStyle: k(EdhText.label.copyWith(fontSize: 13, color: c.text)),
      secondaryLabelStyle: k(EdhText.label.copyWith(fontSize: 13, color: c.textOnGold)),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: GoldFrameBorder(gold: c.gold, radius: EdhSize.radiusL),
      titleTextStyle: k(EdhText.title.copyWith(color: c.text, fontSize: 20)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.gold.withOpacity(.6),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(EdhSize.radiusL)),
        side: BorderSide(color: c.gold.withOpacity(.5)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surfaceHigh,
      contentTextStyle: k(EdhText.body.copyWith(color: c.text)),
      actionTextColor: c.goldText,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.gold.withOpacity(.6))),
    ),
    dividerTheme: DividerThemeData(color: c.gold.withOpacity(.25), thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(iconColor: c.gold),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.arcane,
      foregroundColor: Colors.white,
      shape: CircleBorder(side: BorderSide(color: c.gold, width: 1.5)),
    ),
  );
}
