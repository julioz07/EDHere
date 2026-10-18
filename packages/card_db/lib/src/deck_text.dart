import 'dart:convert';
import 'dart:io';

import 'card.dart';
import 'deck.dart';

/// Uma linha de uma lista colada, antes de se saber que carta é.
class ParsedLine {
  const ParsedLine(this.qty, this.name, this.board, {this.category, this.line = 0});
  final int qty;
  final String name;
  final Board board;
  final String? category;
  final int line;
}

class ImportResult {
  const ImportResult(this.entries, this.unresolved);
  final List<DeckEntry> entries;

  /// Linhas cujo nome não existe na base local.
  final List<ParsedLine> unresolved;
}

final _header = RegExp(
    r'^(?://\s*|#\s*)?(commanders?|command zone|oathbreaker|signature spell|companions?|'
    r'deck|main ?deck|main ?board|main|sideboard|side|maybe ?board|maybe|considering)'
    r'\s*:?\s*(?:\(\d+\))?$',
    caseSensitive: false);

// "1 Sol Ring", "1x Sol Ring (CMR) 472 *F* [Ramp]", "Sol Ring"
final _cardLine = RegExp(
    r'^(?:(\d+)\s*[xX]?\s+)?(.+?)'
    r'(?:\s+\(([A-Za-z0-9]+)\)(?:\s+[A-Za-z0-9★\-]+)?)?'
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
    final category = m.group(4)?.split(',').first.trim();
    blocks.last.add(ParsedLine(
      int.tryParse(m.group(1) ?? '') ?? 1,
      name,
      lineBoard,
      category: category == null || category.isEmpty ? null : category,
      line: i + 1,
    ));
  }

  final nonEmpty = blocks.where((b) => b.isNotEmpty).toList();
  if (hasHeaders || nonEmpty.length < 2) return nonEmpty.expand((b) => b).toList();

  // Formato MTGO: o último bloco é o sideboard (ou os comandantes).
  final last = nonEmpty.last;
  final lastBoard = hasCommandZone && last.length <= 2 ? Board.command : Board.side;
  return [
    for (final b in nonEmpty.sublist(0, nonEmpty.length - 1)) ...b,
    for (final p in last)
      ParsedLine(p.qty, p.name, lastBoard, category: p.category, line: p.line),
  ];
}

/// Resolve os nomes contra a base local.
ImportResult resolveDeckText(List<ParsedLine> lines, Card? Function(String name) find) {
  var deck = const Deck(name: '', format: 'free');
  final unresolved = <ParsedLine>[];
  for (final l in lines) {
    final card = find(l.name) ??
        // "Fire // Ice" escrito só com uma barra, ou com o nome da frente.
        (l.name.contains('/') ? find(l.name.split('/').first.trim()) : null);
    if (card == null) {
      unresolved.add(l);
    } else {
      deck = deck.add(card.oracleId, qty: l.qty, board: l.board, category: l.category);
    }
  }
  return ImportResult(deck.entries, unresolved);
}

enum ExportStyle {
  /// Secções com cabeçalho; aceite pelo Moxfield e pelo Archidekt.
  sections,

  /// Deck, linha em branco, sideboard (comandantes vão no sideboard).
  mtgo,
}

String exportDeckText(Deck deck, Map<String, Card> cards,
    {ExportStyle style = ExportStyle.sections}) {
  String line(DeckEntry e) => '${e.qty} ${cards[e.oracleId]?.name ?? e.oracleId}';
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
