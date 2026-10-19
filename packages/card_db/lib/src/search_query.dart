import 'colors.dart';
import 'text_norm.dart';

/// Pesquisa traduzida para SQL sobre a tabela `cards`.
class CompiledQuery {
  const CompiledQuery({
    required this.where,
    required this.args,
    required this.orderBy,
    this.orderArgs = const [],
    required this.errors,
    required this.isEmpty,
  });

  final String where;
  final List<Object?> args;
  final String orderBy;

  /// Valores dos `?` em [orderBy] (vêm depois de [args]).
  final List<Object?> orderArgs;

  /// Filtros que não foram percebidos (mostrados ao utilizador).
  final List<String> errors;
  final bool isEmpty;
}

class _Sql {
  const _Sql(this.sql, [this.args = const []]);
  final String sql;
  final List<Object?> args;
}

/// Traduz uma pesquisa no estilo Scryfall. Suporta:
///
/// - palavras soltas e "frases" no nome; `!"Nome exato"`
/// - `t:` tipo, `o:` texto, `k:` palavra-chave
/// - `c:`/`id:` cores e identidade (letras wubrg, `c` incolor, `m` multicor,
///   nomes como `azorius`), com `:`, `=`, `>=`, `<=`, `>`, `<`, `!=`
/// - `mv`/`cmc`, `pow`, `tou`, `loy` com comparações numéricas
/// - `f:` formato legal, `banned:`, `restricted:`, `r:` raridade, `s:` set
/// - `is:commander|token|dfc|split|gamechanger|reserved|legendary`
/// - `-` para negar, `or` entre termos, `order:name|mv|edhrec|power`
/// - `include:extras` (tokens, planos...) e `include:digital`
CompiledQuery compileSearch(String input, {bool localized = false}) {
  final tokens = _tokenize(input);
  final errors = <String>[];
  // Ordena pelo nome que se vê: o traduzido, quando há.
  final nk = localized ? 'coalesce(l_name_norm, name_norm)' : 'name_norm';
  String? orderBy;
  String? firstName;
  var includeExtras = false;
  var includeDigital = false;

  final groups = <List<_Sql>>[[]];
  for (final raw in tokens) {
    if (raw.toLowerCase() == 'or') {
      if (groups.last.isNotEmpty) groups.add([]);
      continue;
    }
    var tok = raw;
    var negate = false;
    if (tok.startsWith('-') && tok.length > 1) {
      negate = true;
      tok = tok.substring(1);
    }

    final kv = _splitKey(tok);
    if (kv != null) {
      final (key, op, value) = kv;
      final k = key.toLowerCase();
      if (k == 'order') {
        orderBy = switch (value.toLowerCase()) {
          'mv' || 'cmc' => 'mv, $nk',
          'edhrec' => 'edhrec_rank IS NULL, edhrec_rank, $nk',
          'power' || 'pow' => 'CAST(power AS REAL) DESC, $nk',
          'rarity' => '${_rarityRank('rarity')} DESC, $nk',
          _ => nk,
        };
        continue;
      }
      if (k == 'include') {
        if (value == 'extras') includeExtras = true;
        if (value == 'digital') includeDigital = true;
        continue;
      }
      if (k == 'is' && (value == 'token' || value == 'extra')) includeExtras = true;
      if ((k == 't' || k == 'type') &&
          RegExp(r'token|emblem|plane|scheme|vanguard', caseSensitive: false)
              .hasMatch(value)) {
        includeExtras = true;
      }
      final sql = _keyTerm(k, op, value);
      if (sql == null) {
        errors.add(tok);
        continue;
      }
      groups.last.add(negate ? _Sql('NOT (${sql.sql})', sql.args) : sql);
      continue;
    }

    // Palavra solta, "frase" ou !"nome exato".
    var exact = false;
    var text = tok;
    if (text.startsWith('!')) {
      exact = true;
      text = text.substring(1);
    }
    text = _unquote(text);
    if (text.isEmpty) continue;
    final norm = normalizeName(text);
    if (!exact && !negate) firstName ??= norm;
    final sql = exact
        ? (localized
            ? _Sql('(cards.oracle_id IN (SELECT oracle_id FROM card_names WHERE name_norm = ?) OR l_name_norm = ?)',
                [norm, norm])
            : _Sql('cards.oracle_id IN (SELECT oracle_id FROM card_names WHERE name_norm = ?)', [norm]))
        : (localized
            ? _Sql(r"(name_norm LIKE ? ESCAPE '\' OR l_name_norm LIKE ? ESCAPE '\')",
                ['%${_escapeLike(norm)}%', '%${_escapeLike(norm)}%'])
            : _Sql(r"name_norm LIKE ? ESCAPE '\'", ['%${_escapeLike(norm)}%']));
    groups.last.add(negate ? _Sql('NOT (${sql.sql})', sql.args) : sql);
  }

  final nonEmpty = groups.where((g) => g.isNotEmpty).toList();
  final parts = <String>[];
  final args = <Object?>[];
  if (nonEmpty.isNotEmpty) {
    final ors = <String>[];
    for (final g in nonEmpty) {
      ors.add(g.map((s) => '(${s.sql})').join(' AND '));
      for (final s in g) {
        args.addAll(s.args);
      }
    }
    parts.add(ors.length == 1 ? ors.single : ors.map((o) => '($o)').join(' OR '));
  }
  if (!includeExtras) parts.add('is_extra = 0');
  if (!includeDigital) parts.add('is_paper = 1');

  // Sem order: explícito, o nome igual ao pesquisado vem primeiro, depois os
  // que começam por ele ("relampago" -> Relámpago antes de Relámpago arco).
  final orderArgs = <Object?>[];
  if (orderBy == null && firstName != null) {
    final starts = '${_escapeLike(firstName)}%';
    orderBy = localized
        ? "(name_norm = ? OR l_name_norm = ?) DESC, (name_norm LIKE ? ESCAPE '\\' OR l_name_norm LIKE ? ESCAPE '\\') DESC, $nk"
        : "(name_norm = ?) DESC, (name_norm LIKE ? ESCAPE '\\') DESC, $nk";
    orderArgs.addAll(localized ? [firstName, firstName, starts, starts] : [firstName, starts]);
  }

  return CompiledQuery(
    where: parts.isEmpty ? '1' : parts.map((p) => '($p)').join(' AND '),
    args: args,
    orderBy: orderBy ?? nk,
    orderArgs: orderArgs,
    errors: errors,
    isEmpty: nonEmpty.isEmpty,
  );
}

List<String> _tokenize(String input) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQuote = false;
  for (final ch in input.split('')) {
    if (ch == '"') {
      inQuote = !inQuote;
      buf.write(ch);
    } else if (!inQuote && (ch == ' ' || ch == '\t' || ch == '\n')) {
      if (buf.isNotEmpty) out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}

(String, String, String)? _splitKey(String tok) {
  final m = RegExp(r'^([a-zA-Z]+)(>=|<=|!=|:|=|<|>)(.+)$').firstMatch(tok);
  if (m == null) return null;
  return (m.group(1)!, m.group(2)!, _unquote(m.group(3)!));
}

String _unquote(String s) =>
    s.length >= 2 && s.startsWith('"') && s.endsWith('"') ? s.substring(1, s.length - 1) : s.replaceAll('"', '');

String _escapeLike(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

_Sql _like(String column, String value) =>
    _Sql("$column LIKE ? ESCAPE '\\'", ['%${_escapeLike(value)}%']);

_Sql? _keyTerm(String key, String op, String value) {
  switch (key) {
    case 't' || 'type':
      return op == ':' || op == '=' ? _like('type_line', value) : null;
    case 'o' || 'oracle' || 'text':
      return op == ':' || op == '=' ? _like('oracle_text', value) : null;
    case 'k' || 'keyword' || 'kw':
      return op == ':' || op == '=' ? _like('keywords', '"$value"') : null;
    case 'name' || 'n':
      return _like('name_norm', normalizeName(value));
    case 'c' || 'color' || 'colour' || 'cor':
      return _colorTerm('color_mask', 'color_count', op, value, identity: false);
    case 'id' || 'identity' || 'ci' || 'commander':
      return _colorTerm('identity_mask', 'identity_count', op, value, identity: true);
    case 'mv' || 'cmc' || 'manavalue':
      return _numeric('mv', op, value);
    case 'pow' || 'power':
      return _numericText('power', op, value);
    case 'tou' || 'toughness':
      return _numericText('toughness', op, value);
    case 'loy' || 'loyalty':
      return _numericText('loyalty', op, value);
    case 'f' || 'format' || 'legal':
      return _legality(value, const ['legal', 'restricted']);
    case 'banned':
      return _legality(value, const ['banned']);
    case 'restricted':
      return _legality(value, const ['restricted']);
    case 'r' || 'rarity':
      return _rarity(op, value);
    case 's' || 'set' || 'e' || 'edition':
      return _Sql('set_code = ?', [value.toLowerCase()]);
    case 'a' || 'artist':
      return _like('artist', value);
    case 'is':
      return _isTerm(value.toLowerCase());
    default:
      return null;
  }
}

_Sql? _colorTerm(String col, String countCol, String op, String raw,
    {required bool identity}) {
  final v = raw.toLowerCase();
  final n = int.tryParse(v);
  if (n != null) {
    final sqlOp = op == ':' ? '=' : op;
    return _Sql('$countCol $sqlOp ?', [n]);
  }
  if (v == 'm' || v == 'multicolor' || v == 'multi') {
    return _Sql('$countCol >= 2');
  }
  if (v == 'c' || v == 'colorless' || v == 'incolor') {
    return identity && op == ':' ? _Sql('$col = 0') : _Sql('$col ${op == '!=' ? '!=' : '='} 0');
  }
  final letters = ManaColors.named[v] ?? v;
  if (!RegExp(r'^[wubrg]+$').hasMatch(letters)) return null;
  final mask = ManaColors.maskOf(letters.split(''));
  // Em id:, ":" quer dizer "cabe nesta identidade" (como no Scryfall).
  final effective = op == ':' ? (identity ? '<=' : '>=') : op;
  return switch (effective) {
    '>=' => _Sql('($col & ?) = ?', [mask, mask]),
    '>' => _Sql('($col & ?) = ? AND $col != ?', [mask, mask, mask]),
    '=' => _Sql('$col = ?', [mask]),
    '!=' => _Sql('$col != ?', [mask]),
    '<=' => _Sql('($col | ?) = ?', [mask, mask]),
    '<' => _Sql('($col | ?) = ? AND $col != ?', [mask, mask, mask]),
    _ => null,
  };
}

_Sql? _numeric(String col, String op, String value) {
  final n = num.tryParse(value);
  if (n == null) return null;
  final sqlOp = op == ':' ? '=' : op;
  return _Sql('$col $sqlOp ?', [n]);
}

_Sql? _numericText(String col, String op, String value) {
  final n = num.tryParse(value);
  if (n == null) return null;
  final sqlOp = op == ':' ? '=' : op;
  return _Sql("$col GLOB '[0-9]*' AND CAST($col AS REAL) $sqlOp ?", [n]);
}

_Sql _legality(String format, List<String> statuses) => _Sql(
      'EXISTS (SELECT 1 FROM legalities l WHERE l.oracle_id = cards.oracle_id '
      'AND l.format = ? AND l.status IN (${statuses.map((_) => '?').join(',')}))',
      [_formatKey(format), ...statuses],
    );

String _formatKey(String f) => switch (f.toLowerCase()) {
      'edh' || 'cmdr' => 'commander',
      'historicbrawl' => 'brawl',
      'pdh' => 'paupercommander',
      final other => other,
    };

String _rarityRank(String col) =>
    "CASE $col WHEN 'common' THEN 0 WHEN 'uncommon' THEN 1 WHEN 'rare' THEN 2 "
    "WHEN 'mythic' THEN 3 WHEN 'special' THEN 4 WHEN 'bonus' THEN 5 ELSE -1 END";

_Sql? _rarity(String op, String value) {
  const ranks = {
    'c': 0, 'common': 0, 'u': 1, 'uncommon': 1, 'r': 2, 'rare': 2,
    'm': 3, 'mythic': 3, 's': 4, 'special': 4,
  };
  final r = ranks[value.toLowerCase()];
  if (r == null) return null;
  final sqlOp = op == ':' ? '=' : op;
  return _Sql('${_rarityRank('rarity')} $sqlOp ?', [r]);
}

_Sql? _isTerm(String v) => switch (v) {
      'commander' => const _Sql(
          "((type_line LIKE '%Legendary%' AND type_line LIKE '%Creature%') "
          "OR oracle_text LIKE '%can be your commander%') AND EXISTS (SELECT 1 "
          "FROM legalities l WHERE l.oracle_id = cards.oracle_id AND "
          "l.format = 'commander' AND l.status = 'legal')"),
      'token' => const _Sql('is_token = 1'),
      'extra' => const _Sql('is_extra = 1'),
      'dfc' || 'doublefaced' => const _Sql(
          "layout IN ('transform','modal_dfc','meld','reversible_card','double_faced_token')"),
      'mdfc' => const _Sql("layout = 'modal_dfc'"),
      'transform' => const _Sql("layout = 'transform'"),
      'split' => const _Sql("layout = 'split'"),
      'adventure' => const _Sql("layout = 'adventure'"),
      'gamechanger' || 'gc' => const _Sql('game_changer = 1'),
      'reserved' => const _Sql('reserved = 1'),
      'legendary' => const _Sql("type_line LIKE '%Legendary%'"),
      'permanent' => const _Sql(
          "type_line NOT LIKE '%Instant%' AND type_line NOT LIKE '%Sorcery%'"),
      'spell' => const _Sql("type_line NOT LIKE '%Land%'"),
      _ => null,
    };
