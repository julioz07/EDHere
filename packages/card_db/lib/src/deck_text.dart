import 'dart:convert';
import 'dart:io';

import 'card.dart';
import 'deck.dart';
import 'prints.dart';

/// Uma linha de uma lista colada, antes de se saber que carta é.
class ParsedLine {
  const ParsedLine(this.qty, this.name, this.board,
      {this.category, this.line = 0, this.setCode, this.collectorNumber});
  final int qty;
  final String name;
  final Board board;
  final String? category;
  final int line;

  /// Coleção e número (quando o ficheiro os traz, como o CSV do ManaBox).
  final String? setCode;
  final String? collectorNumber;
}

class ImportResult {
  const ImportResult(this.entries, this.unresolved, [this.printings = const {}]);
  final List<DeckEntry> entries;

  /// Linhas cujo nome não existe na base local.
  final List<ParsedLine> unresolved;

  /// Versões indicadas na lista ("(FDC) 86"), por Oracle ID: a primeira que
  /// aparece para cada carta.
  final Map<String, ({String set, String number})> printings;
}

final _header = RegExp(
    r'^(?://\s*|#\s*)?(commanders?|command zone|oathbreaker|signature spell|companions?|'
    r'deck|main ?deck|main ?board|main|sideboard|side|maybe ?board|maybe|considering)'
    r'\s*:?\s*(?:\(\d+\))?$',
    caseSensitive: false);

// "1 Sol Ring", "1x Sol Ring (CMR) 472 *F* [Ramp]", "Sol Ring"
final _cardLine = RegExp(
    r'^(?:(\d+)\s*[xX]?\s+)?(.+?)'
    r'(?:\s+\(([A-Za-z0-9]+)\)(?:\s+([A-Za-z0-9★\-]+))?)?'
    r'(?:\s+\*[A-Za-z]+\*)*'
    r'(?:\s+\[([^\]]*)\])?'
    r'(?:\s+\^[^\^]*\^)?'
    r'(?:\s+#.*)?$');

Board? _boardFor(String header) {
  final h = header.toLowerCase();
  if (h.startsWith('command') || h == 'oathbreaker' || h == 'signature spell') {
    return Board.command;
  }
  if (h.startsWith('companion') || h.startsWith('side')) return Board.side;
  if (h.startsWith('maybe') || h == 'considering') return Board.maybe;
  return Board.main;
}

/// Lê uma lista em texto (Moxfield, Archidekt, MTGO, MTG Arena).
///
/// Sem cabeçalhos, uma linha em branco separa o deck do sideboard (MTGO).
/// Num formato com zona de comando, um último bloco de 1 ou 2 cartas é
/// tratado como os comandantes.
List<ParsedLine> parseDeckText(String text, {bool hasCommandZone = false}) {
  final lines = text.replaceAll('\r', '').split('\n');
  final hasHeaders = lines.any((l) => _header.hasMatch(l.trim()));
  final blocks = <List<ParsedLine>>[[]];
  var board = Board.main;

  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i].trim();
    if (raw.isEmpty) {
      if (!hasHeaders && blocks.last.isNotEmpty) blocks.add([]);
      // "Commander", o comandante, uma linha em branco e o resto sem
      // cabeçalho "Deck": o resto é o deck, não mais comandantes.
      if (board == Board.command && blocks.last.any((p) => p.board == Board.command)) board = Board.main;
      continue;
    }
    final h = _header.firstMatch(raw);
    if (h != null) {
      board = _boardFor(h.group(1)!) ?? Board.main;
      continue;
    }
    if (raw.startsWith('//') || raw.startsWith('#')) continue;
    // Prefixo "SB:" do MTGO antigo.
    var line = raw;
    var lineBoard = board;
    if (line.toUpperCase().startsWith('SB:')) {
      line = line.substring(3).trim();
      lineBoard = Board.side;
    }
    final m = _cardLine.firstMatch(line);
    if (m == null) continue;
    final name = m.group(2)!.trim();
    if (name.isEmpty) continue;
    // Categorias do Archidekt: "[Commander{top}]", "[Ramp,Commander{top}]",
    // "[Maybeboard{noDeck}{noPrice}]". Uma categoria que é uma zona (Commander,
    // Sideboard, Maybeboard...) põe a carta nessa zona; {noDeck} quer dizer que
    // não conta para o deck (fica no maybeboard). As outras são categorias.
    final cats = [
      for (final c in (m.group(5) ?? '').split(','))
        if (c.trim().isNotEmpty) c.trim(),
    ];
    String plain(String c) => c.replaceAll(RegExp(r'\{[^}]*\}'), '').trim();
    // só os nomes exatos das zonas: uma categoria "Side Effects" não é o sideboard
    Board? zoneOf(String c) => const {
          'commander': Board.command,
          'commanders': Board.command,
          'oathbreaker': Board.command,
          'signature spell': Board.command,
          'sideboard': Board.side,
          'companion': Board.side,
          'maybeboard': Board.maybe,
          'considering': Board.maybe,
        }[plain(c).toLowerCase()];
    final zone = cats.map(zoneOf).whereType<Board>().firstOrNull;
    if (zone != null) {
      lineBoard = zone;
    } else if (cats.any((c) => c.contains('{noDeck}'))) {
      lineBoard = Board.maybe;
    }
    final category = cats.where((c) => zoneOf(c) == null).map(plain).where((c) => c.isNotEmpty).firstOrNull;
    blocks.last.add(ParsedLine(
      int.tryParse(m.group(1) ?? '') ?? 1,
      name,
      lineBoard,
      category: category == null || category.isEmpty ? null : category,
      line: i + 1,
      setCode: m.group(3)?.toLowerCase(),
      collectorNumber: m.group(4),
    ));
  }

  final nonEmpty = blocks.where((b) => b.isNotEmpty).toList();
  if (hasHeaders || nonEmpty.length < 2) return _sanity(nonEmpty.expand((b) => b).toList());

  // Formato MTGO: o último bloco é o sideboard (ou os comandantes).
  final last = nonEmpty.last;
  final lastBoard = hasCommandZone && last.length <= 2 ? Board.command : Board.side;
  return [
    for (final b in nonEmpty.sublist(0, nonEmpty.length - 1)) ...b,
    for (final p in last)
      ParsedLine(p.qty, p.name, lastBoard,
          category: p.category, line: p.line, setCode: p.setCode, collectorNumber: p.collectorNumber),
  ];
}

/// Salvaguarda: mais de dois comandantes e nada no deck é uma lista sem o
/// cabeçalho do deck. Só a primeira carta fica na zona de comando.
List<ParsedLine> _sanity(List<ParsedLine> lines) {
  final command = lines.where((p) => p.board == Board.command).toList();
  if (command.length <= 2 || lines.any((p) => p.board == Board.main)) return lines;
  return [
    for (final p in lines)
      p.board == Board.command && !identical(p, command.first)
          ? ParsedLine(p.qty, p.name, Board.main,
              category: p.category, line: p.line, setCode: p.setCode, collectorNumber: p.collectorNumber)
          : p,
  ];
}

/// Resolve os nomes contra a base local.
ImportResult resolveDeckText(List<ParsedLine> lines, Card? Function(String name) find) {
  var deck = const Deck(name: '', format: 'free');
  final unresolved = <ParsedLine>[];
  final printings = <String, ({String set, String number})>{};
  for (final l in lines) {
    final card = find(l.name) ??
        // "Fire // Ice" escrito só com uma barra, ou com o nome da frente.
        (l.name.contains('/') ? find(l.name.split('/').first.trim()) : null);
    if (card == null) {
      unresolved.add(l);
    } else {
      deck = deck.add(card.oracleId, qty: l.qty, board: l.board, category: l.category);
      if (l.setCode != null && l.collectorNumber != null) {
        printings.putIfAbsent(card.oracleId, () => (set: l.setCode!, number: l.collectorNumber!));
      }
    }
  }
  return ImportResult(deck.entries, unresolved, printings);
}

enum ExportStyle {
  /// Secções com cabeçalho; aceite pelo Moxfield e pelo Archidekt.
  sections,

  /// Deck, linha em branco, sideboard (comandantes vão no sideboard).
  mtgo,
}

/// [printOf] acrescenta a versão escolhida ("(FDC) 86") às cartas que a
/// têm; sem ele, só nomes (mais curto, para o QR).
String exportDeckText(Deck deck, Map<String, Card> cards,
    {ExportStyle style = ExportStyle.sections, PrintInfo? Function(String printId)? printOf}) {
  String line(DeckEntry e) {
    final base = '${e.qty} ${cards[e.oracleId]?.name ?? e.oracleId}';
    final p = e.printId == null || printOf == null ? null : printOf(e.printId!);
    return p == null || p.setCode.isEmpty || p.collectorNumber.isEmpty
        ? base
        : '$base (${p.setCode.toUpperCase()}) ${p.collectorNumber}';
  }
  List<DeckEntry> sorted(Board b) => deck.inBoard(b).toList()
    ..sort((a, b) => (cards[a.oracleId]?.name ?? '').compareTo(cards[b.oracleId]?.name ?? ''));

  final out = StringBuffer();
  if (style == ExportStyle.mtgo) {
    for (final e in sorted(Board.main)) {
      out.writeln(line(e));
    }
    final side = [...sorted(Board.command), ...sorted(Board.side)];
    if (side.isNotEmpty) {
      out.writeln();
      for (final e in side) {
        out.writeln(line(e));
      }
    }
    return out.toString().trimRight();
  }

  void section(String title, Board b) {
    final list = sorted(b);
    if (list.isEmpty) return;
    if (out.isNotEmpty) out.writeln();
    out.writeln(title);
    for (final e in list) {
      out.writeln(line(e));
    }
  }

  section('Commander', Board.command);
  section('Deck', Board.main);
  section('Sideboard', Board.side);
  section('Maybeboard', Board.maybe);
  return out.toString().trimRight();
}

const _sharePrefix = 'EDHERE-DECK:1:';

/// Deck partilhado por QR code: nome, formato e lista em texto, comprimidos.
/// Usa nomes (e não IDs) para caber num QR e funcionar com bases um pouco
/// diferentes.
class SharedDeck {
  const SharedDeck(this.name, this.format, this.text);
  final String name;
  final String format;
  final String text;

  String encode() {
    final json = jsonEncode({'n': name, 'f': format, 't': text});
    return _sharePrefix + base64Url.encode(gzip.encode(utf8.encode(json)));
  }

  static SharedDeck? tryDecode(String raw) {
    if (!raw.startsWith(_sharePrefix)) return null;
    try {
      final bytes = gzip.decode(base64Url.decode(raw.substring(_sharePrefix.length).trim()));
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return SharedDeck(j['n'] as String, j['f'] as String, j['t'] as String);
    } catch (_) {
      return null;
    }
  }
}

/// Lê uma lista de coleção: CSV com cabeçalho (ManaBox, Moxfield, Deckbox,
/// Dragon Shield, Archidekt...) ou texto simples ("1 Sol Ring").
/// Devolve uma linha por carta encontrada (as repetidas não se juntam aqui).
List<ParsedLine> parseCollectionText(String text) {
  final lines = text.replaceAll('\r', '').split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return const [];
  final header = _csvRow(lines.first).map((h) => h.trim().toLowerCase()).toList();
  int col(List<String> names) => header.indexWhere(names.contains);
  final nameCol = col(const ['name', 'card name', 'card', 'card_name', 'cardname']);
  final qtyCol = col(const ['quantity', 'count', 'qty', 'amount', 'total quantity', 'quantidade']);
  final setCol = col(const ['set code', 'set_code', 'setcode', 'edition code', 'set']);
  final numCol = col(const ['collector number', 'collector_number', 'card number', 'number', 'cn']);
  if (header.length < 2 || nameCol < 0) {
    // Sem cabeçalho CSV: lista de texto como as de deck.
    return [for (final l in parseDeckText(text)) ParsedLine(l.qty, l.name, Board.main, line: l.line)];
  }
  final out = <ParsedLine>[];
  for (var i = 1; i < lines.length; i++) {
    final row = _csvRow(lines[i]);
    if (nameCol >= row.length) continue;
    final name = row[nameCol].trim();
    if (name.isEmpty) continue;
    final qty = qtyCol >= 0 && qtyCol < row.length ? int.tryParse(row[qtyCol].trim()) ?? 1 : 1;
    if (qty <= 0) continue;
    String? cell(int c) => c >= 0 && c < row.length && row[c].trim().isNotEmpty ? row[c].trim() : null;
    out.add(ParsedLine(qty, name, Board.main,
        line: i + 1, setCode: cell(setCol)?.toLowerCase(), collectorNumber: cell(numCol)));
  }
  return out;
}

/// Uma linha CSV (vírgula ou ponto e vírgula), com aspas.
List<String> _csvRow(String line) {
  final sep = line.split(',').length >= line.split(';').length ? ',' : ';';
  final out = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == sep && !quoted) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString());
  return out;
}

/// Junta as linhas resolvidas por carta (oracleId -> quantidade total).
({Map<String, int> cards, List<ParsedLine> unresolved}) resolveCollection(
    List<ParsedLine> lines, Card? Function(String name) find) {
  final cards = <String, int>{};
  final unresolved = <ParsedLine>[];
  for (final l in lines) {
    final card = find(l.name) ?? (l.name.contains('/') ? find(l.name.split('/').first.trim()) : null);
    if (card == null) {
      unresolved.add(l);
    } else {
      cards[card.oracleId] = (cards[card.oracleId] ?? 0) + l.qty;
    }
  }
  return (cards: cards, unresolved: unresolved);
}
