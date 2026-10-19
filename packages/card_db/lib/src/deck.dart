import 'i18n.dart';

const Object _keep = Object();

/// Onde uma carta está no deck.
enum Board {
  command('command', 'Comando'),
  main('main', 'Deck'),
  side('side', 'Sideboard'),
  maybe('maybe', 'Talvez');

  const Board(this.id, this._label);
  final String id;
  final String _label;

  /// O nome da secção na língua da app.
  String get label => cardDbTr(_label);

  static Board byId(String id) =>
      values.firstWhere((b) => b.id == id, orElse: () => main);
}

class DeckEntry {
  const DeckEntry({
    required this.oracleId,
    required this.qty,
    this.board = Board.main,
    this.category,
    this.printId,
  });

  final String oracleId;
  final int qty;
  final Board board;
  final String? category;

  /// Impressão escolhida para esta entrada (null = a por defeito).
  final String? printId;

  DeckEntry copyWith({int? qty, Board? board, String? category, Object? printId = _keep}) => DeckEntry(
        oracleId: oracleId,
        qty: qty ?? this.qty,
        board: board ?? this.board,
        category: category ?? this.category,
        printId: identical(printId, _keep) ? this.printId : printId as String?,
      );
}

class Deck {
  const Deck({
    this.id,
    required this.name,
    required this.format,
    this.notes = '',
    this.entries = const [],
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String name;
  final String format;
  final String notes;
  final List<DeckEntry> entries;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Iterable<DeckEntry> inBoard(Board b) => entries.where((e) => e.board == b);
  int count(Board b) => inBoard(b).fold(0, (n, e) => n + e.qty);

  /// Cartas que contam para o tamanho do deck: principal + zona de comando.
  int get playableCount => count(Board.main) + count(Board.command);

  Deck copyWith({String? name, String? format, String? notes, List<DeckEntry>? entries}) =>
      Deck(
        id: id,
        name: name ?? this.name,
        format: format ?? this.format,
        notes: notes ?? this.notes,
        entries: entries ?? this.entries,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Junta [qty] cópias de uma carta (ou soma às que já lá estão).
  Deck add(String oracleId, {int qty = 1, Board board = Board.main, String? category, String? printId}) {
    final list = [...entries];
    final i = list.indexWhere((e) => e.oracleId == oracleId && e.board == board);
    if (i >= 0) {
      list[i] = list[i].copyWith(qty: list[i].qty + qty);
    } else {
      list.add(DeckEntry(
          oracleId: oracleId, qty: qty, board: board, category: category, printId: printId));
    }
    return copyWith(entries: list);
  }

  /// Muda a quantidade; 0 ou menos remove a carta.
  Deck setQty(String oracleId, Board board, int qty) {
    final list = <DeckEntry>[];
    for (final e in entries) {
      if (e.oracleId == oracleId && e.board == board) {
        if (qty > 0) list.add(e.copyWith(qty: qty));
      } else {
        list.add(e);
      }
    }
    return copyWith(entries: list);
  }

  Deck move(String oracleId, Board from, Board to) {
    final e = entries.where((e) => e.oracleId == oracleId && e.board == from).firstOrNull;
    if (e == null || from == to) return this;
    return setQty(oracleId, from, 0)
        .add(oracleId, qty: e.qty, board: to, category: e.category, printId: e.printId);
  }

  /// Escolhe a impressão de uma carta (null volta à por defeito).
  Deck setPrint(String oracleId, Board board, String? printId) => copyWith(entries: [
        for (final x in entries)
          if (x.oracleId == oracleId && x.board == board) x.copyWith(printId: printId) else x,
      ]);

  Deck setCategory(String oracleId, Board board, String? category) => copyWith(entries: [
        for (final x in entries)
          if (x.oracleId == oracleId && x.board == board)
            DeckEntry(
                oracleId: x.oracleId, qty: x.qty, board: x.board, category: category, printId: x.printId)
          else
            x,
      ]);
}
