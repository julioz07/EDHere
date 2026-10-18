import 'package:sqlite3/sqlite3.dart';

import 'card.dart';
import 'schema.dart';
import 'search_query.dart';
import 'text_norm.dart';

class SearchResult {
  const SearchResult(this.cards, this.total, this.errors);
  final List<Card> cards;
  final int total;
  final List<String> errors;
}

class Ruling {
  const Ruling(this.publishedAt, this.source, this.comment);
  final String publishedAt;
  final String source;
  final String comment;
}

/// Acesso só de leitura a `cards.sqlite`.
class CardRepository {
  CardRepository._(this._db);

  /// Abre a base em [path]. Devolve null se não existir ou for de um
  /// esquema antigo.
  static CardRepository? open(String path) {
    final Database db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
    } on SqliteException {
      return null;
    }
    try {
      final v = db.select("SELECT value FROM meta WHERE key = 'schema_version'");
      if (v.isEmpty || v.first['value'] != '$cardSchemaVersion') {
        db.dispose();
        return null;
      }
    } on SqliteException {
      db.dispose();
      return null;
    }
    return CardRepository._(db);
  }

  final Database _db;
  final Map<String, Card> _cache = {};

  void close() => _db.dispose();

  Map<String, String> get meta => {
        for (final r in _db.select('SELECT key, value FROM meta'))
          r['key'] as String: r['value'] as String,
      };

  SearchResult search(String query, {int limit = 60, int offset = 0}) {
    final q = compileSearch(query);
    if (q.isEmpty) return SearchResult(const [], 0, q.errors);
    final total = _db
        .select('SELECT COUNT(*) AS n FROM cards WHERE ${q.where}', q.args)
        .first['n'] as int;
    final rows = _db.select(
      'SELECT * FROM cards WHERE ${q.where} ORDER BY ${q.orderBy} LIMIT ? OFFSET ?',
      [...q.args, limit, offset],
    );
    return SearchResult([for (final r in rows) _remember(Card.fromRow(r))], total, q.errors);
  }

  Card? get(String oracleId) {
    final hit = _cache[oracleId];
    if (hit != null) return hit;
    final rows = _db.select('SELECT * FROM cards WHERE oracle_id = ?', [oracleId]);
    return rows.isEmpty ? null : _remember(Card.fromRow(rows.first));
  }

  Map<String, Card> getMany(Iterable<String> oracleIds) {
    final out = <String, Card>{};
    final missing = <String>[];
    for (final id in oracleIds) {
      final hit = _cache[id];
      hit != null ? out[id] = hit : missing.add(id);
    }
    for (var i = 0; i < missing.length; i += 500) {
      final chunk = missing.sublist(i, (i + 500).clamp(0, missing.length));
      final rows = _db.select(
        'SELECT * FROM cards WHERE oracle_id IN (${chunk.map((_) => '?').join(',')})',
        chunk,
      );
      for (final r in rows) {
        final c = _remember(Card.fromRow(r));
        out[c.oracleId] = c;
      }
    }
    return out;
  }

  /// Procura uma carta pelo nome exato (sem diferenciar maiúsculas nem
  /// acentos). Aceita o nome completo ou o de uma face. Prefere cartas de
  /// jogo a tokens com o mesmo nome.
  Card? findByName(String name) {
    final rows = _db.select('''
      SELECT c.* FROM card_names n JOIN cards c ON c.oracle_id = n.oracle_id
      WHERE n.name_norm = ?
      ORDER BY (c.name_norm = n.name_norm) DESC, c.is_extra, c.is_paper DESC
      LIMIT 1''', [normalizeName(name)]);
    return rows.isEmpty ? null : _remember(Card.fromRow(rows.first));
  }

  /// Sugestões rápidas pelo início do nome, para o autocompletar.
  List<Card> suggest(String prefix, {int limit = 8}) {
    final p = normalizeName(prefix);
    if (p.isEmpty) return const [];
    final rows = _db.select(r'''
      SELECT * FROM cards WHERE name_norm LIKE ? ESCAPE '\' AND is_extra = 0
      ORDER BY edhrec_rank IS NULL, edhrec_rank LIMIT ?''',
        ['${p.replaceAll('%', r'\%').replaceAll('_', r'\_')}%', limit]);
    return [for (final r in rows) _remember(Card.fromRow(r))];
  }

  /// Estado da carta em cada formato (`legal`, `banned`, `restricted`).
  /// Formatos ausentes são `not_legal`.
  Map<String, String> legalities(String oracleId) => {
        for (final r in _db.select(
            'SELECT format, status FROM legalities WHERE oracle_id = ?', [oracleId]))
          r['format'] as String: r['status'] as String,
      };

  /// Legalidade de muitas cartas num formato.
  Map<String, String> legalityIn(String format, Iterable<String> oracleIds) {
    final ids = oracleIds.toList();
    final out = <String, String>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, (i + 500).clamp(0, ids.length));
      final rows = _db.select(
        'SELECT oracle_id, status FROM legalities WHERE format = ? '
        'AND oracle_id IN (${chunk.map((_) => '?').join(',')})',
        [format, ...chunk],
      );
      for (final r in rows) {
        out[r['oracle_id'] as String] = r['status'] as String;
      }
    }
    return out;
  }

  List<Ruling> rulings(String oracleId) => [
        for (final r in _db.select(
            'SELECT published_at, source, comment FROM rulings WHERE oracle_id = ? '
            'ORDER BY published_at',
            [oracleId]))
          Ruling(r['published_at'] as String? ?? '', r['source'] as String? ?? '',
              r['comment'] as String? ?? ''),
      ];

  bool get hasRulings =>
      _db.select('SELECT 1 FROM rulings LIMIT 1').isNotEmpty;

  /// Impressões (uma por carta) que correspondem a uma condição SQL sobre
  /// `cards`, para calcular os pacotes de imagens.
  List<ImageRef> imageRefs(String where, [List<Object?> args = const []]) {
    final rows = _db.select(
        'SELECT oracle_id, print_id, img_small, img_normal, faces_json FROM cards '
        'WHERE $where',
        args);
    final out = <ImageRef>[];
    for (final r in rows) {
      final card = Card.fromRow({
        'oracle_id': r['oracle_id'],
        'name': '',
        'print_id': r['print_id'],
        'img_small': r['img_small'],
        'img_normal': r['img_normal'],
        'faces_json': r['faces_json'],
      });
      out.addAll(ImageRef.allOf(card));
    }
    return out;
  }

  Card _remember(Card c) {
    if (_cache.length > 4000) _cache.clear();
    return _cache[c.oracleId] = c;
  }
}

/// Uma imagem a descarregar: a da carta ou a de uma face.
class ImageRef {
  const ImageRef(this.key, this.small, this.normal);

  /// Nome do ficheiro: `<print_id>` ou `<print_id>_<face>`.
  final String key;
  final String? small;
  final String? normal;

  static List<ImageRef> allOf(Card c) {
    if (c.printId.isEmpty) return const [];
    if (c.hasFaceImages) {
      return [
        for (var i = 0; i < c.faces.length; i++)
          if (c.faces[i].hasOwnImage)
            ImageRef('${c.printId}_$i', c.faces[i].imgSmall, c.faces[i].imgNormal),
      ];
    }
    if (c.imgNormal == null && c.imgSmall == null) return const [];
    return [ImageRef(c.printId, c.imgSmall, c.imgNormal)];
  }

  /// Chave da imagem a mostrar para uma face (0 = frente).
  static String keyFor(Card c, [int face = 0]) =>
      c.hasFaceImages ? '${c.printId}_$face' : c.printId;
}
