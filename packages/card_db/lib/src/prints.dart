import 'card.dart';

/// Imagens e artista de uma face numa impressão de duas faces.
class PrintFace {
  const PrintFace({this.imgSmall, this.imgNormal, this.artist});

  final String? imgSmall;
  final String? imgNormal;
  final String? artist;

  Map<String, dynamic> toJson() => {
        if (imgSmall != null) 's': imgSmall,
        if (imgNormal != null) 'n': imgNormal,
        if (artist != null) 'a': artist,
      };

  static PrintFace fromJson(Map<String, dynamic> j) =>
      PrintFace(imgSmall: j['s'] as String?, imgNormal: j['n'] as String?, artist: j['a'] as String?);
}

/// Uma impressão (versão) de uma carta: coleção, número, arte.
class PrintInfo {
  const PrintInfo({
    required this.printId,
    required this.oracleId,
    this.name = '',
    this.setCode = '',
    this.setName = '',
    this.collectorNumber = '',
    this.releasedAt = '',
    this.artist,
    this.rarity = '',
    this.lang = 'en',
    this.imgSmall,
    this.imgNormal,
    this.faces = const [],
    this.promo = false,
  });

  /// A partir de um objeto `card` da API do Scryfall.
  factory PrintInfo.fromScryfall(Map<String, dynamic> c) {
    final faces = (c['card_faces'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final top = (c['image_uris'] as Map?)?.cast<String, dynamic>();
    final faceImgs = faces.any((f) => f['image_uris'] is Map);
    return PrintInfo(
      printId: c['id'] as String,
      oracleId: (c['oracle_id'] ?? (faces.isNotEmpty ? faces.first['oracle_id'] : null) ?? '') as String,
      name: c['name'] as String? ?? '',
      setCode: c['set'] as String? ?? '',
      setName: c['set_name'] as String? ?? '',
      collectorNumber: c['collector_number'] as String? ?? '',
      releasedAt: c['released_at'] as String? ?? '',
      artist: c['artist'] as String?,
      rarity: c['rarity'] as String? ?? '',
      lang: c['lang'] as String? ?? 'en',
      imgSmall: top?['small'] as String?,
      imgNormal: top?['normal'] as String?,
      promo: c['promo'] == true,
      faces: faceImgs
          ? [
              for (final f in faces)
                PrintFace(
                  imgSmall: (f['image_uris'] as Map?)?['small'] as String?,
                  imgNormal: (f['image_uris'] as Map?)?['normal'] as String?,
                  artist: f['artist'] as String?,
                ),
            ]
          : const [],
    );
  }

  final String printId;
  final String oracleId;
  final String name;
  final String setCode;
  final String setName;
  final String collectorNumber;
  final String releasedAt;
  final String? artist;
  final String rarity;
  final String lang;
  final String? imgSmall;
  final String? imgNormal;

  /// Imagens por face, nas cartas de duas faces físicas.
  final List<PrintFace> faces;
  final bool promo;

  /// "CMM #123 · 2023"
  String get label => [
        '${setCode.toUpperCase()} #$collectorNumber',
        if (releasedAt.length >= 4) releasedAt.substring(0, 4),
      ].join(' · ');

  Map<String, dynamic> toJson() => {
        'id': printId,
        'o': oracleId,
        'name': name,
        'set': setCode,
        'setName': setName,
        'cn': collectorNumber,
        'date': releasedAt,
        if (artist != null) 'artist': artist,
        'rarity': rarity,
        'lang': lang,
        if (imgSmall != null) 's': imgSmall,
        if (imgNormal != null) 'n': imgNormal,
        if (faces.isNotEmpty) 'faces': [for (final f in faces) f.toJson()],
        if (promo) 'promo': true,
      };

  static PrintInfo fromJson(Map<String, dynamic> j) => PrintInfo(
        printId: j['id'] as String,
        oracleId: j['o'] as String,
        name: j['name'] as String? ?? '',
        setCode: j['set'] as String? ?? '',
        setName: j['setName'] as String? ?? '',
        collectorNumber: j['cn'] as String? ?? '',
        releasedAt: j['date'] as String? ?? '',
        artist: j['artist'] as String?,
        rarity: j['rarity'] as String? ?? '',
        lang: j['lang'] as String? ?? 'en',
        imgSmall: j['s'] as String?,
        imgNormal: j['n'] as String?,
        faces: [
          for (final f in (j['faces'] as List? ?? const []))
            PrintFace.fromJson((f as Map).cast<String, dynamic>()),
        ],
        promo: j['promo'] == true,
      );
}

extension CardPrint on Card {
  /// A mesma carta com a arte, coleção e imagens de outra impressão.
  Card withPrint(PrintInfo p) => Card(
        oracleId: oracleId,
        name: name,
        manaCost: manaCost,
        mv: mv,
        typeLine: typeLine,
        oracleText: oracleText,
        power: power,
        toughness: toughness,
        loyalty: loyalty,
        defense: defense,
        colorMask: colorMask,
        identityMask: identityMask,
        layout: layout,
        keywords: keywords,
        rarity: p.rarity.isEmpty ? rarity : p.rarity,
        setCode: p.setCode,
        collectorNumber: p.collectorNumber,
        printId: p.printId,
        artist: p.artist ?? artist,
        imgSmall: p.imgSmall,
        imgNormal: p.imgNormal,
        faces: [
          for (var i = 0; i < faces.length; i++)
            CardFace(
              name: faces[i].name,
              manaCost: faces[i].manaCost,
              typeLine: faces[i].typeLine,
              oracleText: faces[i].oracleText,
              power: faces[i].power,
              toughness: faces[i].toughness,
              loyalty: faces[i].loyalty,
              defense: faces[i].defense,
              imgSmall: i < p.faces.length ? p.faces[i].imgSmall : null,
              imgNormal: i < p.faces.length ? p.faces[i].imgNormal : null,
              artist: i < p.faces.length ? p.faces[i].artist : faces[i].artist,
            ),
        ],
        producedMana: producedMana,
        isToken: isToken,
        isExtra: isExtra,
        gameChanger: gameChanger,
        edhrecRank: edhrecRank,
      );
}
