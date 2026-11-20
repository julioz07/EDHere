import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings.dart';
import '../l10n/l10n.dart';
import 'theme.dart';

/// O `MaterialApp` do EDHere: língua, modo claro/escuro e estilo vêm das
/// Definições.
class EdhereMaterialApp extends ConsumerWidget {
  const EdhereMaterialApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final lang = settings.appLang;
    final style = settings.uiStyle;
    return MaterialApp(
      // Mudar de língua refaz a app toda (os textos são lidos ao construir).
      // O estilo NÃO entra na key: troca só o tema, sem perder o que está aberto.
      key: ValueKey(lang),
      title: 'EDHere',
      locale: lang.locale,
      supportedLocales: [for (final l in AppLang.values) l.locale],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, style),
      darkTheme: buildTheme(Brightness.dark, style),
      themeMode: settings.themeMode,
      home: home,
    );
  }
}
