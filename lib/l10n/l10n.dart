import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:card_db/card_db.dart' as db;
import 'package:mesa_core/mesa_core.dart' as mesa;

import 'strings_en.g.dart';
import 'strings_es.g.dart';
import 'strings_it.g.dart';

/// As línguas da app. O texto do código está em português e é a chave das
/// traduções (geradas de `tool/l10n`).
enum AppLang {
  pt('pt', 'Português'),
  en('en', 'English'),
  es('es', 'Español'),
  it('it', 'Italiano');

  const AppLang(this.code, this.label);
  final String code;

  /// O nome da língua na própria língua (para os seletores).
  final String label;

  Locale get locale => Locale(code);

  static AppLang? byCode(String? code) => values.where((l) => l.code == code).firstOrNull;
}

abstract final class L10n {
  static AppLang _lang = AppLang.pt;
  static Map<String, String> _map = const {};

  static AppLang get lang => _lang;

  /// A língua do telemóvel, se a app a tiver; senão inglês.
  static AppLang fromSystem() {
    for (final l in PlatformDispatcher.instance.locales) {
      if (AppLang.byCode(l.languageCode) case final lang?) return lang;
    }
    return AppLang.en;
  }

  static void use(AppLang lang) {
    _lang = lang;
    _map = switch (lang) {
      AppLang.pt => const {},
      AppLang.en => stringsEn,
      AppLang.es => stringsEs,
      AppLang.it => stringsIt,
    };
    // O registo do jogo e a validação dos decks também falam a língua da app.
    mesa.mesaTr = tr;
    db.cardDbTr = tr;
  }

  /// As traduções de uma língua (para os testes).
  static Map<String, String> table(AppLang lang) => switch (lang) {
        AppLang.pt => const {},
        AppLang.en => stringsEn,
        AppLang.es => stringsEs,
        AppLang.it => stringsIt,
      };
}

/// Traduz [pt] para a língua da app. `{nome}` no texto é trocado por
/// `args['nome']`.
String tr(String pt, [Map<String, Object?>? args]) {
  var s = L10n._map[pt] ?? pt;
  if (args != null) {
    for (final e in args.entries) {
      s = s.replaceAll('{${e.key}}', '${e.value}');
    }
  }
  return s;
}

/// O nome de uma língua na língua da app, para usar numa frase ("em italiano").
String langName(String code) => switch (code) {
      'pt' => tr('português'),
      'en' => tr('inglês'),
      'es' => tr('espanhol'),
      'it' => tr('italiano'),
      _ => code,
    };
