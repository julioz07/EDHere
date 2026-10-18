import 'dart:convert';
import 'dart:io';

import 'package:card_db/card_db.dart';

Map<String, dynamic> card(
  String name, {
  String? id,
  String cost = '',
  double cmc = 0,
  String type = 'Creature — Test',
  String text = '',
  List<String> colors = const [],
  List<String>? identity,
  String layout = 'normal',
  List<String> keywords = const [],
  String rarity = 'common',
  Map<String, String> legal = const {},
  List<Map<String, dynamic>>? faces,
  List<String> produced = const [],
  String? power,
  String? toughness,
}) =>
    {
      'id': 'print-${id ?? name}',
      'oracle_id': id ?? 'oid-$name',
      'name': name,
      'layout': layout,
      if (faces == null) 'mana_cost': cost,
      'cmc': cmc,
      'type_line': type,
      if (faces == null) 'oracle_text': text,
      'colors': colors,
      'color_identity': identity ?? colors,
      'keywords': keywords,
      'rarity': rarity,
      'set': 'tst',
      'collector_number': '1',
      'games': ['paper'],
      'legalities': {
        'commander': 'legal',
        'modern': 'not_legal',
        ...legal,
      },
      if (faces == null)
        'image_uris': {
          'small': 'https://img/small/$name.jpg',
          'normal': 'https://img/normal/$name.jpg',
        },
      if (faces != null) 'card_faces': faces,
      if (power != null) 'power': power,
      if (toughness != null) 'toughness': toughness,
      'produced_mana': produced,
    };

final fixtureCards = [
  card('Sol Ring', cost: '{1}', cmc: 1, type: 'Artifact',
      text: '{T}: Add {C}{C}.', rarity: 'uncommon', produced: ['C'],
      legal: {'modern': 'not_legal', 'vintage': 'restricted'}),
  card('Atraxa, Praetors\' Voice', cost: '{G}{W}{U}{B}', cmc: 4,
      type: 'Legendary Creature — Phyrexian Angel Horror',
      text: 'Flying, vigilance, deathtouch, lifelink', colors: ['W', 'U', 'B', 'G'],
      keywords: ['Flying', 'Vigilance', 'Deathtouch', 'Lifelink'], rarity: 'mythic',
      power: '4', toughness: '4'),
  card('Lightning Bolt', cost: '{R}', cmc: 1, type: 'Instant',
      text: 'Lightning Bolt deals 3 damage to any target.', colors: ['R'],
      legal: {'modern': 'legal'}),
  card('Counterspell', cost: '{U}{U}', cmc: 2, type: 'Instant',
      text: 'Counter target spell.', colors: ['U'], legal: {'modern': 'not_legal'}),
  card('Llanowar Elves', cost: '{G}', cmc: 1, type: 'Creature — Elf Druid',
      text: '{T}: Add {G}.', colors: ['G'], power: '1', toughness: '1', produced: ['G'],
      legal: {'modern': 'legal'}),
  card('Forest', type: 'Basic Land — Forest', text: '({T}: Add {G}.)',
      produced: ['G'], legal: {'modern': 'legal'}),
  card('Island', type: 'Basic Land — Island', text: '({T}: Add {U}.)',
      produced: ['U'], legal: {'modern': 'legal'}),
  card('Relentless Rats', cost: '{1}{B}{B}', cmc: 3, type: 'Creature — Rat',
      text: 'A deck can have any number of cards named Relentless Rats.',
      colors: ['B'], power: '2', toughness: '2'),
  card('Seven Dwarves', cost: '{1}{R}', cmc: 2, type: 'Creature — Dwarf',
      text: 'A deck can have up to seven cards named Seven Dwarves.', colors: ['R']),
  card('Mana Crypt', cost: '{0}', type: 'Artifact', text: '{T}: Add {C}{C}.',
      legal: {'commander': 'banned'}),
  card('Æther Vial', cost: '{1}', cmc: 1, type: 'Artifact', legal: {'modern': 'legal'}),
  card('Fire // Ice', cmc: 4, type: 'Instant // Instant', colors: ['U', 'R'],
      layout: 'split', faces: [
        {'name': 'Fire', 'mana_cost': '{1}{R}', 'type_line': 'Instant',
            'oracle_text': 'Fire deals 2 damage divided as you choose.'},
        {'name': 'Ice', 'mana_cost': '{1}{U}', 'type_line': 'Instant',
            'oracle_text': 'Tap target permanent. Draw a card.'},
      ]),
  card('Delver of Secrets // Insectile Aberration', cmc: 1,
      type: 'Creature — Human Wizard // Creature — Human Insect', colors: ['U'],
      layout: 'transform', faces: [
        {'name': 'Delver of Secrets', 'mana_cost': '{U}', 'type_line': 'Creature — Human Wizard',
            'oracle_text': 'At the beginning of your upkeep, look at the top card.',
            'colors': ['U'], 'power': '1', 'toughness': '1',
            'image_uris': {'small': 's0', 'normal': 'n0'}},
        {'name': 'Insectile Aberration', 'mana_cost': '', 'type_line': 'Creature — Human Insect',
            'oracle_text': 'Flying', 'colors': ['U'], 'power': '3', 'toughness': '2',
            'image_uris': {'small': 's1', 'normal': 'n1'}},
      ]),
  card('Thrasios, Triton Hero', cost: '{G}{U}', cmc: 2,
      type: 'Legendary Creature — Merfolk Wizard',
      text: '{4}: Scry 1.\nPartner (You can have two commanders if both have partner.)',
      colors: ['G', 'U'], keywords: ['Partner']),
  card('Tymna the Weaver', cost: '{1}{W}{B}', cmc: 3,
      type: 'Legendary Creature — Human Cleric',
      text: 'Lifelink\nPartner (You can have two commanders if both have partner.)',
      colors: ['W', 'B'], keywords: ['Lifelink', 'Partner']),
  card('Wilson, Refined Grizzly', cost: '{1}{G}', cmc: 2,
      type: 'Legendary Creature — Bear Warrior',
      text: 'Choose a Background (You can have a Background as a second commander.)',
      colors: ['G'], keywords: ['Choose a Background']),
  card('Raised by Giants', cost: '{5}{G}', cmc: 6,
      type: 'Legendary Enchantment — Background', colors: ['G']),
  // Uma carta cujo verso tem o nome de outra carta que existe.
  card('Wheel of Fortune', cost: '{2}{R}', cmc: 3, type: 'Sorcery', colors: ['R']),
  card('Naktamun Lorespinner // Wheel of Fortune', cmc: 3, type: 'Creature — Jackal // Sorcery',
      colors: ['R'], layout: 'prepare', faces: [
        {'name': 'Naktamun Lorespinner', 'mana_cost': '{2}{R}', 'type_line': 'Creature — Jackal'},
        {'name': 'Wheel of Fortune', 'mana_cost': '{2}{R}', 'type_line': 'Sorcery'},
      ]),
  card('Elf Warrior', type: 'Token Creature — Elf Warrior', layout: 'token',
      colors: ['G'], power: '1', toughness: '1'),
  card('Art Card', layout: 'art_series', type: 'Card'),
];

/// Cria uma base com as cartas de teste e devolve o caminho.
Future<String> buildFixtureDb() async {
  final dir = Directory.systemTemp.createTempSync('card_db_test');
  final path = '${dir.path}${Platform.pathSeparator}cards.sqlite';
  final imp = CardImporter(path)..open();
  await imp.importLines(Stream.fromIterable(fixtureCards.map(jsonEncode)));
  imp.finish({'bulk_updated_at': 'test'});
  return path;
}
