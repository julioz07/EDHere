import 'dart:convert';
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:edhoff/data/image_service.dart';
import 'package:edhoff/data/settings.dart';
import 'package:edhoff/l10n/l10n.dart';
import 'package:edhoff/tutorial/chapters_basics.dart';
import 'package:edhoff/tutorial/chapters_commander.dart';
import 'package:edhoff/tutorial/tutorial.dart';
import 'package:edhoff/ui/tutorial/glossary_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesa_core/mesa_core.dart';

/// Os textos que vivem em dados (traduzidos ao serem mostrados), com a origem.
Map<String, String> dataKeys() {
  final keys = <String, String>{};
  void add(String? k, String where) {
    if (k != null && k.trim().isNotEmpty) keys.putIfAbsent(k, () => where);
  }

  for (final c in [...basicsChapters, ...commanderChapters]) {
    final w = 'tutorial:${c.id}';
    add(c.title, w);
    add(c.summary, w);
    for (final p in c.pages) {
      add(p.title, w);
      add(p.body, w);
      for (final card in p.cards) {
        add(card.caption, w);
      }
    }
    for (final a in c.setup?.prepare ?? const <Act>[]) {
      add(a.say, w);
    }
    for (final s in c.steps) {
      add(s.title, w);
      add(s.text, w);
      add(s.hint, w);
      for (final a in s.run) {
        add(a.say, w);
      }
    }
  }
  for (final (pt, _, text) in glossary) {
    add(pt, 'glossary');
    add(text, 'glossary');
  }
  for (final p in ImagePack.all) {
    add(p.label, 'image_packs');
    add(p.description, 'image_packs');
  }
  for (final b in TableBackground.builtIn) {
    add(b.label, 'backgrounds');
  }
  for (final f in GameFormat.all) {
    add(f.label, 'formats');
  }
  for (final z in Zone.values) {
    add(z.label, 'zones');
  }
  return keys;
}

final _placeholder = RegExp(r'\{([a-z][A-Za-z0-9]*)\}');

Set<String> _placeholders(String s) => {for (final m in _placeholder.allMatches(s)) m[1]!};

void main() {
  test('os textos dos dados (para tool/l10n/extract.py)', () {
    L10n.use(AppLang.pt);
    final keys = dataKeys();
    expect(keys, isNotEmpty);
    if (Platform.environment['L10N_DUMP'] != null) {
      File('tool/l10n/data_keys.json')
          .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(keys));
    }
  });

  test('todas as chaves têm tradução em inglês, espanhol e italiano', () {
    final file = File('tool/l10n/keys.json');
    final keys = [
      for (final e in jsonDecode(file.readAsStringSync()) as List) (e as Map)['key'] as String,
    ];
    for (final lang in [AppLang.en, AppLang.es, AppLang.it]) {
      final table = L10n.table(lang);
      final missing = [for (final k in keys) if (!table.containsKey(k)) k];
      expect(missing, isEmpty, reason: '${lang.code}: faltam ${missing.length}, p.ex. ${missing.take(5)}');
      for (final k in keys) {
        expect(_placeholders(table[k]!), _placeholders(k), reason: '${lang.code}: marcadores em "$k"');
      }
    }
  });

  test('o tutorial e o glossário traduzem-se ao ler', () {
    L10n.use(AppLang.en);
    final first = basicsChapters.first;
    expect(first.title, isNot('O que é o Magic e as cartas'));
    L10n.use(AppLang.pt);
    expect(first.title, 'O que é o Magic e as cartas');
  });

  test('a língua do sistema escolhe uma das quatro, ou inglês', () {
    expect(AppLang.byCode('it'), AppLang.it);
    expect(AppLang.byCode('fr'), isNull);
    expect(AppLang.values.map((l) => l.code), ['pt', 'en', 'es', 'it']);
  });
}
