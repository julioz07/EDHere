import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'text_norm.dart';

/// Tabela das cartas numa língua (uma por carta): o texto impresso e a
/// impressão nessa língua, com as suas imagens. As colunas têm o prefixo
/// `l_` para se poderem juntar a `cards` sem ambiguidade.
const List<String> localizedSchema = [
  '''
  CREATE TABLE IF NOT EXISTS card_i18n(
    l_oracle_id TEXT PRIMARY KEY,
    l_lang TEXT NOT NULL,
    l_name TEXT,
    l_name_norm TEXT,
    l_type TEXT,
    l_text TEXT,
    l_faces TEXT,
    l_print_id TEXT,
    l_set TEXT,
    l_number TEXT,
    l_artist TEXT,
    l_small TEXT,
    l_normal TEXT
  ) WITHOUT ROWID''',
  'CREATE INDEX IF NOT EXISTS card_i18n_name ON card_i18n(l_name_norm)',
];

/// O texto de uma carta como está impresso noutra língua.
class PrintedText {
  const PrintedText({required this.lang, this.name = '', this.typeLine = '', this.text = '', this.faces = const []});

  final String lang;
  final String name;
  final String typeLine;
  final String text;
  final List<PrintedFace> faces;

  PrintedFace? face(int i) => i >= 0 && i < faces.length ? faces[i] : null;
}

class PrintedFace {
  const PrintedFace({this.name = '', this.typeLine = '', this.text = ''});
  final String name;
  final String typeLine;
  final String text;
}

/// Escreve as cartas de uma língua em `cards.sqlite` (a partir dos objetos
/// `card` da API do Scryfall). [begin] apaga a língua anterior.
class LocalizedImporter {
  LocalizedImporter(this.path);

  final String path;
  late final Database _db;
  late final PreparedStatement _ins;
  int imported = 0;

  void begin(String lang) {
    _db = sqlite3.open(path);
    for (final s in localizedSchema) {
      _db.execute(s);
    }
    _db.execute('BEGIN');
    _db.execute('DELETE FROM card_i18n');
    _db.execute("DELETE FROM meta WHERE key IN ('card_lang', 'card_lang_count')");
    _ins = _db.prepare('INSERT OR REPLACE INTO card_i18n VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)');
    _lang = lang;
  }

  late String _lang;

  /// Uma carta impressa na língua. Se a mesma carta vier duas vezes, fica a
  /// primeira (a pesquisa do Scryfall já devolve uma por carta).
  void add(Map<String, dynamic> c) {
    final faces = (c['card_faces'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final oracle = c['oracle_id'] as String? ?? (faces.isNotEmpty ? faces.first['oracle_id'] as String? : null);
    if (oracle == null) return;
    String? s(Map<String, dynamic> m, String k) => (m[k] as String?)?.trim().isEmpty ?? true ? null : m[k] as String;
    final name = s(c, 'printed_name') ??
        (faces.isNotEmpty && faces.any((f) => s(f, 'printed_name') != null)
            ? faces.map((f) => s(f, 'printed_name') ?? f['name'] ?? '').join(' // ')
            : null);
    final type = s(c, 'printed_type_line') ??
        (faces.any((f) => s(f, 'printed_type_line') != null)
            ? faces.map((f) => s(f, 'printed_type_line') ?? f['type_line'] ?? '').join(' // ')
            : null);
    final text = s(c, 'printed_text') ??
        (faces.any((f) => s(f, 'printed_text') != null)
            ? faces.map((f) => s(f, 'printed_text') ?? '').join('\n//\n')
            : null);
    // Sem imagem própria nessa língua (o Scryfall mostra "Localized Image Not
    // Available"): fica o texto traduzido e a impressão inglesa.
    final status = c['image_status'] as String?;
    if (status == 'placeholder' || status == 'missing') {
      _ins.execute([oracle, _lang, name, name == null ? null : normalizeName(name), type, text,
          _facesJson(faces, s, withImages: false), null, null, null, null, null, null]);
      imported++;
      return;
    }
    final top = (c['image_uris'] as Map?)?.cast<String, dynamic>();
    final faceImgs = faces.any((f) => f['image_uris'] is Map);
    final firstImgs = faces.isNotEmpty ? (faces.first['image_uris'] as Map?)?.cast<String, dynamic>() : null;
    final imgs = top ?? firstImgs;
    _ins.execute([
      oracle,
      _lang,
      name,
      name == null ? null : normalizeName(name),
      type,
      text,
      _facesJson(faces, s, withImages: faceImgs),
      c['id'],
      c['set'],
      c['collector_number'],
      c['artist'],
      imgs?['small'],
      imgs?['normal'],
    ]);
    imported++;
  }

  /// Só os campos que [add] usa (para não guardar as cartas inteiras em
  /// memória enquanto se descarregam as páginas).
  static Map<String, dynamic> slim(Map<String, dynamic> c) {
    Map<String, dynamic>? imgs(Object? m) => m is Map ? {'small': m['small'], 'normal': m['normal']} : null;
    const keep = ['id', 'oracle_id', 'name', 'printed_name', 'printed_type_line', 'printed_text', 'set',
        'collector_number', 'artist', 'image_status'];
    const keepFace = ['oracle_id', 'name', 'type_line', 'printed_name', 'printed_type_line', 'printed_text'];
    return {
      for (final k in keep)
        if (c[k] != null) k: c[k],
      if (imgs(c['image_uris']) != null) 'image_uris': imgs(c['image_uris']),
      if (c['card_faces'] is List)
        'card_faces': [
          for (final f in (c['card_faces'] as List).cast<Map<String, dynamic>>())
            {
              for (final k in keepFace)
                if (f[k] != null) k: f[k],
              if (imgs(f['image_uris']) != null) 'image_uris': imgs(f['image_uris']),
            },
        ],
    };
  }

  static String? _facesJson(List<Map<String, dynamic>> faces, String? Function(Map<String, dynamic>, String) s,
      {required bool withImages}) {
    if (faces.isEmpty) return null;
    return jsonEncode([
      for (final f in faces)
        {
          if (s(f, 'printed_name') != null) 'name': f['printed_name'],
          if (s(f, 'printed_type_line') != null) 'type_line': f['printed_type_line'],
          if (s(f, 'printed_text') != null) 'text': f['printed_text'],
          if (withImages && f['image_uris'] is Map) ...{
            'img_small': (f['image_uris'] as Map)['small'],
            'img_normal': (f['image_uris'] as Map)['normal'],
          },
        },
    ]);
  }

  void finish() {
    _db.execute("INSERT OR REPLACE INTO meta VALUES ('card_lang', ?)", [_lang]);
    _db.execute("INSERT OR REPLACE INTO meta VALUES ('card_lang_count', ?)", ['$imported']);
    _db.execute('COMMIT');
    _ins.dispose();
    _db.dispose();
  }

  void cancel() {
    _db.execute('ROLLBACK');
    _ins.dispose();
    _db.dispose();
  }

  /// Volta ao inglês: apaga a tabela da língua.
  static void clear(String path) {
    final db = sqlite3.open(path);
    try {
      for (final s in localizedSchema) {
        db.execute(s);
      }
      db.execute('DELETE FROM card_i18n');
      db.execute("DELETE FROM meta WHERE key IN ('card_lang', 'card_lang_count')");
    } finally {
      db.dispose();
    }
  }
}
