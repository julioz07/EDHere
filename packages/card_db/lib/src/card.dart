import 'dart:convert';

import 'colors.dart';

/// Uma face de uma carta com várias faces (transform, MDFC, split, adventure...).
class CardFace {
  const CardFace({
    required this.name,
    this.manaCost = '',
    this.typeLine = '',
    this.oracleText = '',
    this.power,
    this.toughness,
    this.loyalty,
    this.defense,
    this.imgSmall,
    this.imgNormal,
    this.artist,
  });

  factory CardFace.fromJson(Map<String, dynamic> j) => CardFace(
        name: j['name'] as String? ?? '',
        manaCost: j['mana_cost'] as String? ?? '',
        typeLine: j['type_line'] as String? ?? '',
        oracleText: j['oracle_text'] as String? ?? '',
        power: j['power'] as String?,
        toughness: j['toughness'] as String?,
        loyalty: j['loyalty'] as String?,
        defense: j['defense'] as String?,
        imgSmall: j['img_small'] as String?,
        imgNormal: j['img_normal'] as String?,
        artist: j['artist'] as String?,
      );

  final String name;
  final String manaCost;
  final String typeLine;
  final String oracleText;
  final String? power;
  final String? toughness;
  final String? loyalty;
  final String? defense;

  /// URLs das imagens desta face, quando cada face tem imagem própria.
  final String? imgSmall;
  final String? imgNormal;
  final String? artist;

  bool get hasOwnImage => imgNormal != null;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (manaCost.isNotEmpty) 'mana_cost': manaCost,
        if (typeLine.isNotEmpty) 'type_line': typeLine,
        if (oracleText.isNotEmpty) 'oracle_text': oracleText,
        if (power != null) 'power': power,
        if (toughness != null) 'toughness': toughness,
        if (loyalty != null) 'loyalty': loyalty,
        if (defense != null) 'defense': defense,
        if (imgSmall != null) 'img_small': imgSmall,
        if (imgNormal != null) 'img_normal': imgNormal,
        if (artist != null) 'artist': artist,
      };
}

/// Uma carta (uma entrada por Oracle ID) com a impressão por defeito.
class Card {
  const Card({
    required this.oracleId,
    required this.name,
    this.manaCost = '',
    this.mv = 0,
    this.typeLine = '',
    this.oracleText = '',
    this.power,
    this.toughness,
    this.loyalty,
    this.defense,
    this.colorMask = 0,
    this.identityMask = 0,
    this.layout = 'normal',
    this.keywords = const [],
    this.rarity = '',
    this.setCode = '',
    this.collectorNumber = '',
    this.printId = '',
    this.artist,
    this.imgSmall,
    this.imgNormal,
    this.faces = const [],
    this.producedMana = const [],
    this.isToken = false,
    this.isExtra = false,
    this.gameChanger = false,
    this.edhrecRank,
  });

  final String oracleId;
  final String name;
  final String manaCost;
  final double mv;
  final String typeLine;
  final String oracleText;
  final String? power;
  final String? toughness;
  final String? loyalty;
  final String? defense;
  final int colorMask;
  final int identityMask;
  final String layout;
  final List<String> keywords;
  final String rarity;
  final String setCode;
  final String collectorNumber;

  /// ID Scryfall da impressão por defeito; nome dos ficheiros de imagem.
  final String printId;
  final String? artist;
  final String? imgSmall;
  final String? imgNormal;
  final List<CardFace> faces;
  final List<String> producedMana;
  final bool isToken;

  /// Tokens, emblemas, planos, esquemas e outras cartas fora do baralho.
  final bool isExtra;
  final bool gameChanger;
  final int? edhrecRank;

  List<String> get colors => ManaColors.lettersOf(colorMask);
  List<String> get colorIdentity => ManaColors.lettersOf(identityMask);

  /// Nome da face da frente ("Delver of Secrets" em vez de "A // B").
  String get frontName => faces.isNotEmpty ? faces.first.name : name;

  /// Tipo da face da frente, que é o que conta para a mesa e a curva.
  String get frontType => faces.isNotEmpty && faces.first.typeLine.isNotEmpty
      ? faces.first.typeLine
      : typeLine.split(' // ').first;

  bool get isLand => frontType.contains('Land');
  bool get isBasicLand => typeLine.contains('Basic') && typeLine.contains('Land');
  bool get isLegendary => frontType.contains('Legendary');

  /// Faces com imagem própria (cartas de duas faces físicas).
  bool get hasFaceImages => faces.isNotEmpty && faces.first.hasOwnImage;

  /// Pode ser comandante: criatura lendária ou texto que o permite.
  bool get canBeCommander =>
      (isLegendary && frontType.contains('Creature')) ||
      oracleText.contains('can be your commander');

  /// Máximo de cópias num deck, com as exceções das próprias cartas:
  /// terrenos básicos e "any number" não têm limite (null); "up to seven"
  /// (Seven Dwarves) tem o seu. As restantes usam [formatLimit].
  int? copyLimit(int formatLimit) {
    if (isBasicLand) return null;
    if (oracleText.contains('A deck can have any number of cards named')) return null;
    final m = RegExp(r'A deck can have up to (\w+) cards named').firstMatch(oracleText);
    if (m != null) {
      const words = {'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9};
      return words[m.group(1)] ?? int.tryParse(m.group(1)!) ?? formatLimit;
    }
    return formatLimit;
  }

  static List<String> _list(Object? raw) =>
      raw is String && raw.isNotEmpty ? (jsonDecode(raw) as List).cast<String>() : const [];

  factory Card.fromRow(Map<String, Object?> r) => Card(
        oracleId: r['oracle_id']! as String,
        name: r['name']! as String,
        manaCost: r['mana_cost'] as String? ?? '',
        mv: (r['mv'] as num?)?.toDouble() ?? 0,
        typeLine: r['type_line'] as String? ?? '',
        oracleText: r['oracle_text'] as String? ?? '',
        power: r['power'] as String?,
        toughness: r['toughness'] as String?,
        loyalty: r['loyalty'] as String?,
        defense: r['defense'] as String?,
        colorMask: (r['color_mask'] as int?) ?? 0,
        identityMask: (r['identity_mask'] as int?) ?? 0,
        layout: r['layout'] as String? ?? 'normal',
        keywords: _list(r['keywords']),
        rarity: r['rarity'] as String? ?? '',
        setCode: r['set_code'] as String? ?? '',
        collectorNumber: r['collector_number'] as String? ?? '',
        printId: r['print_id'] as String? ?? '',
        artist: r['artist'] as String?,
        imgSmall: r['img_small'] as String?,
        imgNormal: r['img_normal'] as String?,
        faces: r['faces_json'] is String && (r['faces_json']! as String).isNotEmpty
            ? [
                for (final f in jsonDecode(r['faces_json']! as String) as List)
                  CardFace.fromJson((f as Map).cast<String, dynamic>()),
              ]
            : const [],
        producedMana: _list(r['produced_mana']),
        isToken: r['is_token'] == 1,
        isExtra: r['is_extra'] == 1,
        gameChanger: r['game_changer'] == 1,
        edhrecRank: r['edhrec_rank'] as int?,
      );

  @override
  String toString() => 'Card($name)';
}
