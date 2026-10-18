import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'colors.dart';
import 'schema.dart';
import 'text_norm.dart';

/// Layouts que não são cartas de jogo nem tokens úteis na mesa.
const _skipLayouts = {'art_series'};

/// Layouts que existem fora do baralho: tokens, emblemas, Planechase,
/// Archenemy, Vanguard.
const _extraLayouts = {
  'token', 'double_faced_token', 'emblem', 'planar', 'scheme', 'vanguard',
  'front_card',
};

/// Converte o bulk "Oracle Cards" do Scryfall (JSONL) numa base SQLite.
///
/// Escreve numa base nova em [path]. Quem chama decide quando a troca pela
/// antiga, para que a antiga continue a servir se algo falhar a meio.
class CardImporter {
  CardImporter(this.path);

  final String path;
  late final Database _db;
  late final PreparedStatement _insCard;
  late final PreparedStatement _insName;
  late final PreparedStatement _insLegal;
  int imported = 0;
  int skipped = 0;

  void open() {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
    _db = sqlite3.open(path);
    _db.execute('PRAGMA journal_mode = OFF');
    _db.execute('PRAGMA synchronous = OFF');
    for (final stmt in cardSchema) {
      _db.execute(stmt);
    }
    _insCard = _db.prepare('''
      INSERT OR REPLACE INTO cards(
        oracle_id, name, name_norm, mana_cost, mv, type_line, oracle_text,
        power, toughness, loyalty, defense, color_mask, color_count,
        identity_mask, identity_count, layout, keywords, rarity, set_code,
        collector_number, print_id, artist, released_at, img_small, img_normal,
        faces_json, produced_mana, is_token, is_extra, is_paper, game_changer,
        reserved, edhrec_rank
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''');
    _insName = _db.prepare('INSERT OR IGNORE INTO card_names VALUES (?, ?)');
    _insLegal = _db.prepare('INSERT OR REPLACE INTO legalities VALUES (?, ?, ?)');
    _db.execute('BEGIN');
  }

  /// Importa todas as linhas. [onProgress] recebe o número de cartas lidas.
  Future<void> importLines(Stream<String> lines,
      {void Function(int count)? onProgress}) async {
    await for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty || t == '[' || t == ']') continue;
      // Aceita também o formato antigo (array JSON com uma carta por linha).
      final json = t.endsWith(',') ? t.substring(0, t.length - 1) : t;
      addCard(jsonDecode(json) as Map<String, dynamic>);
      if (onProgress != null && imported % 500 == 0) onProgress(imported);
    }
    onProgress?.call(imported);
  }

  void addCard(Map<String, dynamic> c) {
    final layout = c['layout'] as String? ?? 'normal';
    final rawFaces = (c['card_faces'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final oracleId = c['oracle_id'] as String? ??
        (rawFaces.isNotEmpty ? rawFaces.first['oracle_id'] as String? : null);
    if (_skipLayouts.contains(layout) || oracleId == null) {
      skipped++;
      return;
    }

    final name = c['name'] as String;
    final typeLine = c['type_line'] as String? ??
        rawFaces.map((f) => f['type_line'] ?? '').join(' // ');
    String? first(String key) =>
        c[key] as String? ?? (rawFaces.isNotEmpty ? rawFaces.first[key] as String? : null);

    final manaCost = c['mana_cost'] as String? ??
        rawFaces.map((f) => f['mana_cost'] as String? ?? '').where((s) => s.isNotEmpty).join(' // ');
    final oracleText = c['oracle_text'] as String? ??
        rawFaces.map((f) => f['oracle_text'] as String? ?? '').join('\n//\n');

    final colorLetters = (c['colors'] as List?)?.cast<String>() ??
        rawFaces.expand((f) => (f['colors'] as List?)?.cast<String>() ?? const <String>[]);
    final colorMask = ManaColors.maskOf(colorLetters);
    final identityMask =
        ManaColors.maskOf((c['color_identity'] as List?)?.cast<String>() ?? const []);

    final topImgs = (c['image_uris'] as Map?)?.cast<String, dynamic>();
    final firstFaceImgs = rawFaces.isNotEmpty
        ? (rawFaces.first['image_uris'] as Map?)?.cast<String, dynamic>()
        : null;
    final imgs = topImgs ?? firstFaceImgs;

    final faces = [
      for (final f in rawFaces)
        {
          'name': f['name'],
          if ((f['mana_cost'] as String?)?.isNotEmpty ?? false) 'mana_cost': f['mana_cost'],
          if (f['type_line'] != null) 'type_line': f['type_line'],
          if ((f['oracle_text'] as String?)?.isNotEmpty ?? false) 'oracle_text': f['oracle_text'],
          if (f['power'] != null) 'power': f['power'],
          if (f['toughness'] != null) 'toughness': f['toughness'],
          if (f['loyalty'] != null) 'loyalty': f['loyalty'],
          if (f['defense'] != null) 'defense': f['defense'],
          if (f['artist'] != null) 'artist': f['artist'],
          if (f['image_uris'] is Map) ...{
            'img_small': (f['image_uris'] as Map)['small'],
            'img_normal': (f['image_uris'] as Map)['normal'],
          },
        },
    ];

    final isToken = layout == 'token' ||
        layout == 'double_faced_token' ||
        layout == 'emblem' ||
        typeLine.startsWith('Token') ||
        typeLine.contains(' Token ') ||
        typeLine.startsWith('Emblem');
    final isExtra = isToken || _extraLayouts.contains(layout);
    final games = (c['games'] as List?)?.cast<String>() ?? const ['paper'];

    _insCard.execute([
      oracleId,
      name,
      normalizeName(name),
      manaCost,
      (c['cmc'] as num?)?.toDouble() ?? 0,
      typeLine,
      oracleText,
      first('power'),
      first('toughness'),
      first('loyalty'),
      first('defense'),
      colorMask,
      ManaColors.count(colorMask),
      identityMask,
      ManaColors.count(identityMask),
      layout,
      jsonEncode(c['keywords'] ?? const []),
      c['rarity'],
      c['set'],
      c['collector_number'],
      c['id'],
      c['artist'] ?? first('artist'),
      c['released_at'],
      imgs?['small'],
      imgs?['normal'],
      faces.isEmpty ? null : jsonEncode(faces),
      jsonEncode(c['produced_mana'] ?? const []),
      isToken ? 1 : 0,
      isExtra ? 1 : 0,
      games.contains('paper') ? 1 : 0,
      c['game_changer'] == true ? 1 : 0,
      c['reserved'] == true ? 1 : 0,
      c['edhrec_rank'],
    ]);

    final names = {
      normalizeName(name),
      for (final f in rawFaces)
        if (f['name'] is String) normalizeName(f['name'] as String),
    };
    for (final n in names) {
      _insName.execute([n, oracleId]);
    }

    final legal = (c['legalities'] as Map?)?.cast<String, dynamic>() ?? const {};
    legal.forEach((format, status) {
      if (status != 'not_legal') _insLegal.execute([format, oracleId, status]);
    });
    imported++;
  }

  /// Importa o bulk "Rulings" (JSONL). Pode correr depois das cartas.
  Future<int> importRulings(Stream<String> lines) async {
    final ins = _db.prepare('INSERT INTO rulings VALUES (?, ?, ?, ?)');
    var n = 0;
    await for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty || t == '[' || t == ']') continue;
      final r = jsonDecode(t.endsWith(',') ? t.substring(0, t.length - 1) : t)
          as Map<String, dynamic>;
      ins.execute([r['oracle_id'], r['published_at'], r['source'], r['comment']]);
      n++;
    }
    ins.dispose();
    return n;
  }

  /// Fecha a transação, grava os metadados e compacta a base.
  void finish(Map<String, String> meta) {
    final insMeta = _db.prepare('INSERT OR REPLACE INTO meta VALUES (?, ?)');
    meta.forEach((k, v) => insMeta.execute([k, v]));
    insMeta.execute(['schema_version', '$cardSchemaVersion']);
    insMeta.execute(['card_count', '$imported']);
    insMeta.dispose();
    _db.execute('COMMIT');
    _insCard.dispose();
    _insName.dispose();
    _insLegal.dispose();
    _db.execute('ANALYZE');
    _db.execute('VACUUM');
    _db.dispose();
  }

  /// Desiste e apaga a base parcial.
  void abort() {
    try {
      _db.dispose();
    } catch (_) {}
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }
}
