import 'package:flutter/services.dart';

import '../l10n/l10n.dart';

/// Um deck base que vem com a app (as listas estão em assets/precons e são
/// conferidas com `python -I tool/precons/check.py`).
class Precon {
  const Precon(this.id, this.name, this.format, this.face, {this.source});

  final String id;

  /// O nome oficial (não se traduz).
  final String name;
  final String format;

  /// A carta que aparece na lista: o comandante ou a que dá a cara ao deck.
  final String face;

  /// De onde vem a lista.
  final String? source;

  /// Como se joga, numa linha.
  String get about => switch (id) {
        'fdc_angels' => tr('Anjos: joga anjos que voam e ganha mana para chegar aos maiores.'),
        'fdc_thopters' => tr('Artefactos: cada artefacto que jogas enche a mesa de tópteros.'),
        'fdc_zombies' => tr('Zombies: cria zombies e sacrifica-os para fazer ainda mais.'),
        'fdc_dragons' => tr('Dragões: junta tesouros e joga dragões enormes.'),
        'fdc_dinos' => tr('Dinossauros: criaturas gigantes que passam por cima de tudo.'),
        'modern_burn' => tr('Rápido: criaturas pequenas e feitiços que tiram vida diretamente ao adversário.'),
        'modern_stompy' => tr('Criaturas verdes grandes e baratas: acelera a mana e ataca.'),
        _ => '',
      };

  Future<String> load() => rootBundle.loadString('assets/precons/$id.txt');
}

/// Os 5 Foundations Commander (feitos para quem começa no Commander) e dois
/// decks de 60 cartas simples de jogar.
const precons = [
  Precon('fdc_angels', 'Calling All Angels', 'commander', 'Giada, Font of Hope', source: 'Foundations Commander'),
  Precon('fdc_thopters', 'Keen Engineering', 'commander', 'Sai, Master Thopterist', source: 'Foundations Commander'),
  Precon('fdc_zombies', 'Wretched Ranks', 'commander', 'Ghoulcaller Gisa', source: 'Foundations Commander'),
  Precon('fdc_dragons', 'Reign of Dragons', 'commander', 'Lathliss, Dragon Queen', source: 'Foundations Commander'),
  Precon('fdc_dinos', 'Tramplesaurus Rex', 'commander', 'Ghalta, Primal Hunger', source: 'Foundations Commander'),
  Precon('modern_burn', 'Mono-Red Burn', 'modern', 'Lightning Bolt'),
  Precon('modern_stompy', 'Mono-Green Stompy', 'modern', 'Steel Leaf Champion'),
];
