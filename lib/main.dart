import 'package:card_db/card_db.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'app/theme.dart';
import 'data/app_paths.dart';
import 'data/providers.dart';
import 'data/settings.dart';
import 'ui/onboarding_screen.dart';
import 'l10n/l10n.dart';

/// Marca a reparação da língua da 1.9.2 (ver `main`).
const _langRepairedKey = 'lang_repaired_192';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
        ['Mana (Andrew Gioia)'], await rootBundle.loadString('assets/licenses/mana_OFL.txt'));
    // O EDHere e o motor do bot (Forge) são GPL-3.0.
    final gpl = await rootBundle.loadString('assets/licenses/gpl-3.0.txt');
    yield LicenseEntryWithLineBreaks(['EDHere'], gpl);
    yield LicenseEntryWithLineBreaks(['Forge (motor de regras do bot)'], gpl);
  });
  final prefs = await SharedPreferences.getInstance();
  // A língua da app: a escolhida nas Definições ou a do telemóvel. Até à
  // 1.9.1 quem nunca escolheu língua passava a português na 2.ª vez que
  // abria a app; quem ficou assim volta (uma vez) à língua do telemóvel.
  if (prefs.getBool(_langRepairedKey) != true) {
    if (prefs.getString(Settings.langKey) == AppLang.pt.code && L10n.fromSystem() != AppLang.pt) {
      await prefs.remove(Settings.langKey);
    }
    await prefs.setBool(_langRepairedKey, true);
  }
  L10n.use(AppLang.byCode(prefs.getString(Settings.langKey)) ?? L10n.fromSystem());
  final paths = await AppPaths.resolve();
  final store = DeckStore.open(paths.userDb);
  runApp(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      pathsProvider.overrideWithValue(paths),
      deckStoreProvider.overrideWithValue(store),
    ],
    child: const EdhereApp(),
  ));
}

class EdhereApp extends ConsumerWidget {
  const EdhereApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final lang = settings.appLang;
    return MaterialApp(
      // Mudar de língua refaz a app toda (os textos são lidos ao construir).
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
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      home: const OnboardingGate(),
    );
  }
}
