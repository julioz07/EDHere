import 'dart:math';

import 'card.dart';
import 'prints.dart';

/// Uma impressão dentro dos dados de boosters: o id do Scryfall (para a
/// imagem) e o oracle id (para o texto, que vem da base de cartas).
class BoosterPrint {
  const BoosterPrint(this.scryfallId, this.oracleId, this.rarity, this.number, {this.setCode = ''});

  final String scryfallId;
  final String oracleId;

  /// C, U, R, M ou S (especial).
  final String rarity;
  final String number;
  final String setCode;

  /// Ordem das raridades (para escolher a carta de destaque, por exemplo).
  int get rarityRank => const {'M': 4, 'R': 3, 'S': 2, 'U': 1}[rarity] ?? 0;

  static String imageUrl(String scryfallId, String size, {bool back = false}) =>
      'https://cards.scryfall.io/$size/${back ? 'back' : 'front'}/'
      '${scryfallId[0]}/${scryfallId[1]}/$scryfallId.jpg';

  /// A versão desta carta, para a mostrar com a arte certa. [base] é a
  /// carta da base local (sabe se tem duas faces com imagem).
  PrintInfo printInfo(Card base) {
    final faces = base.hasFaceImages;
    return PrintInfo(
      printId: scryfallId,
      oracleId: oracleId,
      name: base.name,
      setCode: setCode,
      collectorNumber: number,
      rarity: const {'C': 'common', 'U': 'uncommon', 'R': 'rare', 'M': 'mythic'}[rarity] ?? 'special',
      imgSmall: faces ? null : imageUrl(scryfallId, 'small'),
      imgNormal: faces ? null : imageUrl(scryfallId, 'normal'),
      faces: faces
          ? [
              PrintFace(imgSmall: imageUrl(scryfallId, 'small'), imgNormal: imageUrl(scryfallId, 'normal')),
              PrintFace(
                  imgSmall: imageUrl(scryfallId, 'small', back: true),
                  imgNormal: imageUrl(scryfallId, 'normal', back: true)),
            ]
          : const [],
    );
  }

  static BoosterPrint fromJson(List<dynamic> j, List<String> oracles, String setCode) =>
      BoosterPrint(j[0] as String, oracles[(j[1] as num).toInt()], j[2] as String, '${j[3]}',
          setCode: setCode);
}

/// Uma carta saída de um booster.
class PackCard {
  const PackCard(this.print, {this.foil = false});
  final BoosterPrint print;
  final bool foil;
}

/// Um set no índice dos boosters.
class BoosterSetInfo {
  const BoosterSetInfo(
      {required this.code,
      required this.name,
      required this.date,
      required this.type,
      required this.kind,
      required this.size});

  final String code;
  final String name;
  final String date;
  final String type;

  /// `play`, `draft` ou `default`.
  final String kind;

  /// Cartas por booster.
  final int size;

  int get year => int.tryParse(date.split('-').first) ?? 0;

  static BoosterSetInfo fromJson(Map<String, dynamic> j) => BoosterSetInfo(
        code: j['code'] as String,
        name: j['name'] as String,
        date: j['date'] as String? ?? '',
        type: j['type'] as String? ?? '',
        kind: j['kind'] as String? ?? 'draft',
        size: (j['size'] as num?)?.toInt() ?? 15,
      );
}

class _Sheet {
  _Sheet(this.foil, this.cards, this.weights) : total = weights.fold(0, (a, b) => a + b);
  final bool foil;
  final List<int> cards;
  final List<int> weights;
  final int total;
}

/// As regras de booster de um set (de MTGJSON): várias composições
/// possíveis, cada uma com um peso, e as folhas de onde saem as cartas.
class SetBoosters {
  SetBoosters._(this.info, this.prints, this._sheets, this._configs)
      : _configTotal = _configs.fold(0, (a, c) => a + c.$1);

  final BoosterSetInfo info;
  final List<BoosterPrint> prints;
  final Map<String, _Sheet> _sheets;
  final List<(int, Map<String, int>)> _configs;
  final int _configTotal;

  static SetBoosters fromJson(BoosterSetInfo info, Map<String, dynamic> j, List<String> oracles) {
    final prints = [
      for (final p in (j['prints'] as List).cast<List<dynamic>>())
        BoosterPrint.fromJson(p, oracles, info.code),
    ];
    final sheets = <String, _Sheet>{
      for (final MapEntry(:key, :value) in (j['sheets'] as Map<String, dynamic>).entries)
        key: _Sheet(
          value['foil'] == 1,
          [for (final c in (value['cards'] as List).cast<List<dynamic>>()) (c[0] as num).toInt()],
          [for (final c in (value['cards'] as List).cast<List<dynamic>>()) (c[1] as num).toInt()],
        ),
    };
    final configs = [
      for (final c in (j['configs'] as List).cast<List<dynamic>>())
        ((c[0] as num).toInt(), (c[1] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt()))),
    ];
    return SetBoosters._(info, prints, sheets, configs);
  }

  /// Abre um booster: escolhe a composição pelo peso e tira as cartas de
  /// cada folha (pelo peso, sem repetir dentro da mesma folha).
  List<PackCard> open(Random random) {
    var roll = random.nextInt(_configTotal);
    var config = _configs.first.$2;
    for (final (w, c) in _configs) {
      if (roll < w) {
        config = c;
        break;
      }
      roll -= w;
    }
    final out = <PackCard>[];
    final taken = <int>{};
    for (final MapEntry(key: name, value: n) in config.entries) {
      final sheet = _sheets[name];
      if (sheet == null) continue;
      final used = <int>{};
      for (var i = 0; i < n; i++) {
        final idx = _pick(sheet, used, random);
        if (idx == null) break;
        used.add(idx);
        final card = sheet.cards[idx];
        // A mesma carta não sai duas vezes no booster (salvo foil/terreno).
        if (!sheet.foil && taken.contains(card)) continue;
        taken.add(card);
        out.add(PackCard(prints[card], foil: sheet.foil));
      }
    }
    // Raras primeiro, comuns no fim, como quando se abre um booster.
    out.sort((a, b) => b.print.rarityRank.compareTo(a.print.rarityRank));
    return out;
  }

  int? _pick(_Sheet s, Set<int> used, Random random) {
    var total = s.total;
    for (final u in used) {
      total -= s.weights[u];
    }
    if (total <= 0) return null;
    var roll = random.nextInt(total);
    for (var i = 0; i < s.cards.length; i++) {
      if (used.contains(i)) continue;
      if (roll < s.weights[i]) return i;
      roll -= s.weights[i];
    }
    return null;
  }
}

/// Um pacote JumpStart: 20 cartas de um tema, prontas a juntar a outro.
class JumpstartPacket {
  const JumpstartPacket({required this.set, required this.name, required this.theme, required this.cards});

  final String set;

  /// "Goblins 1" (o número é a variante).
  final String name;

  /// "Goblins".
  final String theme;
  final List<(BoosterPrint, int)> cards;

  int get count => cards.fold(0, (n, c) => n + c.$2);

  /// A carta que se mostra antes de escolher: a de raridade mais alta.
  BoosterPrint get featured {
    var best = cards.first.$1;
    for (final (p, _) in cards) {
      if (p.rarityRank > best.rarityRank) best = p;
    }
    return best;
  }

  static JumpstartPacket fromJson(Map<String, dynamic> j, List<String> oracles) => JumpstartPacket(
        set: j['set'] as String,
        name: j['name'] as String,
        // "Elves (2)", "Goblins 1": o tema é sem o número da variante.
        theme: (j['theme'] as String).replaceAll(RegExp(r'\s*(\(\d+\)|\d+)$'), ''),
        cards: [
          for (final c in (j['cards'] as List).cast<List<dynamic>>())
            (BoosterPrint.fromJson(c, oracles, j['set'] as String), (c[4] as num).toInt()),
        ],
      );
}

/// Um "pack" de cubo: [size] cartas tiradas ao acaso da lista, sem repetir
/// entre packs (a lista vai-se gastando).
List<List<String>> cubePacks(List<String> cube, int packs, int size, Random random) {
  final pool = [...cube]..shuffle(random);
  return [
    for (var i = 0; i < packs; i++)
      if (pool.length >= (i + 1) * size) pool.sublist(i * size, (i + 1) * size),
  ];
}
