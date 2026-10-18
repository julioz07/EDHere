import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'deck.dart';
import 'prints.dart';

/// Base do utilizador (`user.sqlite`): decks e definições.
/// Nunca é apagada nas atualizações da base de cartas.
class DeckStore {
  DeckStore._(this._db);

  static DeckStore open(String path) {
    final db = sqlite3.open(path);
    db.execute('PRAGMA foreign_keys = ON');
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version < 1) {
      db.execute('''
        CREATE TABLE decks(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          format TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )''');
      db.execute('''
        CREATE TABLE deck_cards(
          deck_id INTEGER NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
          oracle_id TEXT NOT NULL,
          qty INTEGER NOT NULL,
          board TEXT NOT NULL,
          category TEXT,
          PRIMARY KEY(deck_id, oracle_id, board)
        )''');
      db.execute('''
        CREATE TABLE installed_packs(
          pack_id TEXT NOT NULL,
          resolution TEXT NOT NULL,
          installed_at INTEGER NOT NULL,
          PRIMARY KEY(pack_id, resolution)
        )''');
      db.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
      db.execute('PRAGMA user_version = 1');
    }
    if (version < 2) {
      db.execute('''
        CREATE TABLE games(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          format TEXT NOT NULL,
          players_json TEXT NOT NULL,
          winner TEXT,
          my_deck_id INTEGER,
          my_won INTEGER NOT NULL DEFAULT 0,
          turns INTEGER NOT NULL,
          duration_s INTEGER NOT NULL,
          network INTEGER NOT NULL DEFAULT 0,
          played_at INTEGER NOT NULL
        )''');
      db.execute('PRAGMA user_version = 2');
    }
    if (version < 3) {
      // Versões alternativas: impressão por entrada de deck, impressões
      // conhecidas (para funcionar offline) e versão preferida por carta.
      db.execute('ALTER TABLE deck_cards ADD COLUMN print_id TEXT');
      db.execute('''
        CREATE TABLE prints(
          print_id TEXT PRIMARY KEY,
          oracle_id TEXT NOT NULL,
          json TEXT NOT NULL
        )''');
      db.execute('CREATE INDEX prints_card ON prints(oracle_id)');
      db.execute('''
        CREATE TABLE preferred_prints(
          oracle_id TEXT PRIMARY KEY,
          print_id TEXT NOT NULL
        )''');
      db.execute('PRAGMA user_version = 3');
    }
    if (version < 4) {
      // As minhas cartas: só quantidades indicativas, sem inventário.
      db.execute('''
        CREATE TABLE IF NOT EXISTS collection(
          oracle_id TEXT PRIMARY KEY,
          qty INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )''');
      db.execute('PRAGMA user_version = 4');
    }
    return DeckStore._(db);
  }

  final Database _db;

  void close() => _db.dispose();

  List<Deck> listDecks() {
    final rows = _db.select('SELECT * FROM decks ORDER BY updated_at DESC');
    return [for (final r in rows) _deckFrom(r, _entries(r['id'] as int))];
  }

  Deck? getDeck(int id) {
    final rows = _db.select('SELECT * FROM decks WHERE id = ?', [id]);
    return rows.isEmpty ? null : _deckFrom(rows.first, _entries(id));
  }

  /// Grava o deck (cria se não tiver id) e devolve-o com id.
  Deck save(Deck deck) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute('BEGIN');
    try {
      int id;
      if (deck.id == null) {
        _db.execute(
            'INSERT INTO decks(name, format, notes, created_at, updated_at) VALUES (?,?,?,?,?)',
            [deck.name, deck.format, deck.notes, now, now]);
        id = _db.lastInsertRowId;
      } else {
        id = deck.id!;
        _db.execute('UPDATE decks SET name=?, format=?, notes=?, updated_at=? WHERE id=?',
            [deck.name, deck.format, deck.notes, now, id]);
        _db.execute('DELETE FROM deck_cards WHERE deck_id = ?', [id]);
      }
      final ins = _db.prepare(
          'INSERT OR REPLACE INTO deck_cards(deck_id, oracle_id, qty, board, category, print_id) '
          'VALUES (?,?,?,?,?,?)');
      for (final e in deck.entries) {
        ins.execute([id, e.oracleId, e.qty, e.board.id, e.category, e.printId]);
      }
      ins.dispose();
      _db.execute('COMMIT');
      return getDeck(id)!;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteDeck(int id) => _db.execute('DELETE FROM decks WHERE id = ?', [id]);

  /// Todas as cartas de todos os decks (para o pacote "As minhas cartas").
  Set<String> allDeckOracleIds() => {
        for (final r in _db.select('SELECT DISTINCT oracle_id FROM deck_cards'))
          r['oracle_id'] as String,
      };

  void saveGame(GameRecord g) => _db.execute(
      'INSERT INTO games(format, players_json, winner, my_deck_id, my_won, turns, duration_s, '
      'network, played_at) VALUES (?,?,?,?,?,?,?,?,?)',
      [
        g.format,
        jsonEncode([for (final p in g.players) p.toJson()]),
        g.winner,
        g.myDeckId,
        g.myWon ? 1 : 0,
        g.turns,
        g.duration.inSeconds,
        g.network ? 1 : 0,
        g.playedAt.millisecondsSinceEpoch,
      ]);

  List<GameRecord> listGames() => [
        for (final r in _db.select('SELECT * FROM games ORDER BY played_at DESC'))
          GameRecord(
            id: r['id'] as int,
            format: r['format'] as String,
            players: [
              for (final p in jsonDecode(r['players_json'] as String) as List)
                GamePlayer.fromJson((p as Map).cast<String, dynamic>()),
            ],
            winner: r['winner'] as String?,
            myDeckId: r['my_deck_id'] as int?,
            myWon: r['my_won'] == 1,
            turns: r['turns'] as int,
            duration: Duration(seconds: r['duration_s'] as int),
            network: r['network'] == 1,
            playedAt: DateTime.fromMillisecondsSinceEpoch(r['played_at'] as int),
          ),
      ];

  void deleteGame(int id) => _db.execute('DELETE FROM games WHERE id = ?', [id]);

  // ---------------------------------------------------------------------
  // Impressões (versões alternativas)
  // ---------------------------------------------------------------------

  void savePrints(Iterable<PrintInfo> prints) {
    final ins = _db.prepare('INSERT OR REPLACE INTO prints VALUES (?, ?, ?)');
    _db.execute('BEGIN');
    for (final p in prints) {
      ins.execute([p.printId, p.oracleId, jsonEncode(p.toJson())]);
    }
    _db.execute('COMMIT');
    ins.dispose();
  }

  PrintInfo? printInfo(String printId) {
    final rows = _db.select('SELECT json FROM prints WHERE print_id = ?', [printId]);
    return rows.isEmpty
        ? null
        : PrintInfo.fromJson(jsonDecode(rows.first['json'] as String) as Map<String, dynamic>);
  }

  /// Impressões conhecidas de uma carta (as que já foram vistas online).
  List<PrintInfo> printsOf(String oracleId) => [
        for (final r in _db.select('SELECT json FROM prints WHERE oracle_id = ?', [oracleId]))
          PrintInfo.fromJson(jsonDecode(r['json'] as String) as Map<String, dynamic>),
      ]..sort((a, b) => b.releasedAt.compareTo(a.releasedAt));

  Map<String, String> preferredPrints() => {
        for (final r in _db.select('SELECT oracle_id, print_id FROM preferred_prints'))
          r['oracle_id'] as String: r['print_id'] as String,
      };

  void setPreferredPrint(String oracleId, String? printId) => printId == null
      ? _db.execute('DELETE FROM preferred_prints WHERE oracle_id = ?', [oracleId])
      : _db.execute('INSERT OR REPLACE INTO preferred_prints VALUES (?, ?)', [oracleId, printId]);

  // ---------------------------------------------------------------------
  // As minhas cartas
  // ---------------------------------------------------------------------

  /// Quantidade de cada carta que tenho (oracleId -> qty).
  Map<String, int> collection() => {
        for (final r in _db.select('SELECT oracle_id, qty FROM collection'))
          r['oracle_id'] as String: r['qty'] as int,
      };

  int owned(String oracleId) {
    final rows = _db.select('SELECT qty FROM collection WHERE oracle_id = ?', [oracleId]);
    return rows.isEmpty ? 0 : rows.first['qty'] as int;
  }

  /// Fixa a quantidade (0 ou menos tira a carta da coleção).
  void setOwned(String oracleId, int qty) => qty <= 0
      ? _db.execute('DELETE FROM collection WHERE oracle_id = ?', [oracleId])
      : _db.execute('INSERT OR REPLACE INTO collection VALUES (?, ?, ?)',
          [oracleId, qty, DateTime.now().millisecondsSinceEpoch]);

  /// Junta cartas à coleção. Com [atLeast], só sobe até essa quantidade
  /// (não soma): útil para "tenho este deck físico".
  void addOwned(Map<String, int> cards, {bool atLeast = false}) {
    final current = collection();
    _db.execute('BEGIN');
    for (final MapEntry(key: id, value: n) in cards.entries) {
      final have = current[id] ?? 0;
      final qty = atLeast ? (n > have ? n : have) : have + n;
      setOwned(id, qty);
    }
    _db.execute('COMMIT');
  }

  /// Decks onde uma carta aparece, com quantas cópias (principal + comando).
  List<(Deck deck, int qty)> decksWith(String oracleId) {
    final rows = _db.select(
        "SELECT deck_id, SUM(qty) AS n FROM deck_cards WHERE oracle_id = ? "
        "AND board IN ('main','command','side') GROUP BY deck_id",
        [oracleId]);
    return [
      for (final r in rows)
        if (getDeck(r['deck_id'] as int) case final d?) (d, r['n'] as int),
    ];
  }

  String? setting(String key) {
    final rows = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  void setSetting(String key, String? value) => value == null
      ? _db.execute('DELETE FROM settings WHERE key = ?', [key])
      : _db.execute('INSERT OR REPLACE INTO settings VALUES (?, ?)', [key, value]);

  Set<String> installedPacks(String resolution) => {
        for (final r in _db.select(
            'SELECT pack_id FROM installed_packs WHERE resolution = ?', [resolution]))
          r['pack_id'] as String,
      };

  void markPackInstalled(String packId, String resolution) => _db.execute(
      'INSERT OR REPLACE INTO installed_packs VALUES (?, ?, ?)',
      [packId, resolution, DateTime.now().millisecondsSinceEpoch]);

  void unmarkPack(String packId, String resolution) => _db.execute(
      'DELETE FROM installed_packs WHERE pack_id = ? AND resolution = ?',
      [packId, resolution]);

  List<DeckEntry> _entries(int deckId) => [
        for (final r in _db.select(
            'SELECT * FROM deck_cards WHERE deck_id = ? ORDER BY rowid', [deckId]))
          DeckEntry(
            oracleId: r['oracle_id'] as String,
            qty: r['qty'] as int,
            board: Board.byId(r['board'] as String),
            category: r['category'] as String?,
            printId: r['print_id'] as String?,
          ),
      ];

  Deck _deckFrom(Row r, List<DeckEntry> entries) => Deck(
        id: r['id'] as int,
        name: r['name'] as String,
        format: r['format'] as String,
        notes: r['notes'] as String,
        entries: entries,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      );
}

class GamePlayer {
  const GamePlayer({required this.name, this.deckName, this.commanders = const [], this.me = false});

  factory GamePlayer.fromJson(Map<String, dynamic> j) => GamePlayer(
        name: j['name'] as String,
        deckName: j['deck'] as String?,
        commanders: (j['cmd'] as List? ?? const []).cast<String>(),
        me: j['me'] == true,
      );

  final String name;
  final String? deckName;
  final List<String> commanders;

  /// Um lugar controlado por este dispositivo.
  final bool me;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (deckName != null) 'deck': deckName,
        'cmd': commanders,
        if (me) 'me': true,
      };
}

/// Uma partida terminada, guardada só neste dispositivo.
class GameRecord {
  const GameRecord({
    this.id,
    required this.format,
    required this.players,
    this.winner,
    this.myDeckId,
    this.myWon = false,
    required this.turns,
    required this.duration,
    this.network = false,
    required this.playedAt,
  });

  final int? id;
  final String format;
  final List<GamePlayer> players;

  /// Nome do vencedor; null = sem vencedor (empate, desistência).
  final String? winner;
  final int? myDeckId;
  final bool myWon;
  final int turns;
  final Duration duration;
  final bool network;
  final DateTime playedAt;
}
