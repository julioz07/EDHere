import 'dart:convert';

import 'prints.dart';
import 'deck.dart';
import 'deck_store.dart';
import 'i18n.dart';

/// Ficheiro de backup do EDHere: decks, coleção, histórico e versões
/// escolhidas, num JSON que se pode guardar onde se quiser (Drive, PC…) e
/// enviar a outra pessoa. As cartas vão por Oracle ID e também pelo nome,
/// para continuarem a ser encontradas noutra versão da base de cartas.
class Backup {
  Backup({
    this.decks = const [],
    this.collection = const {},
    this.games = const [],
    this.preferredPrints = const {},
    this.prints = const [],
    this.names = const {},
    DateTime? exportedAt,
  }) : exportedAt = exportedAt ?? DateTime.now();

  static const kind = 'edhere-backup';
  static const version = 1;

  final List<Deck> decks;
  final Map<String, int> collection;
  final List<GameRecord> games;
  final Map<String, String> preferredPrints;
  final List<PrintInfo> prints;

  /// Oracle ID -> nome, para recuperar cartas cujo Oracle ID não exista.
  final Map<String, String> names;
  final DateTime exportedAt;

  bool get isEmpty => decks.isEmpty && collection.isEmpty && games.isEmpty;

  /// Junta o que está no [store]. [deckIds] null = todos os decks.
  static Backup collect(
    DeckStore store, {
    Iterable<int>? deckIds,
    bool collection = true,
    bool games = true,
    String? Function(String oracleId)? nameOf,
  }) {
    final decks = deckIds == null
        ? store.listDecks()
        : [for (final id in deckIds) store.getDeck(id)].whereType<Deck>().toList();
    final coll = collection ? store.collection() : const <String, int>{};
    final prefs = store.preferredPrints();
    final printIds = {
      for (final d in decks)
        for (final e in d.entries)
          if (e.printId != null) e.printId!,
      ...prefs.values,
    };
    final names = <String, String>{};
    if (nameOf != null) {
      for (final id in {
        for (final d in decks) ...d.entries.map((e) => e.oracleId),
        ...coll.keys,
      }) {
        if (nameOf(id) case final n?) names[id] = n;
      }
    }
    return Backup(
      decks: decks,
      collection: coll,
      games: games ? store.listGames() : const [],
      preferredPrints: prefs,
      prints: [for (final id in printIds) store.printInfo(id)].whereType<PrintInfo>().toList(),
      names: names,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'version': version,
        'exported': exportedAt.toIso8601String(),
        'decks': [
          for (final d in decks)
            {
              'id': d.id,
              'name': d.name,
              'format': d.format,
              if (d.notes.isNotEmpty) 'notes': d.notes,
              if (d.createdAt != null) 'created': d.createdAt!.toIso8601String(),
              'cards': [
                for (final e in d.entries)
                  {
                    'o': e.oracleId,
                    if (names[e.oracleId] != null) 'name': names[e.oracleId],
                    'n': e.qty,
                    if (e.board != Board.main) 'b': e.board.id,
                    if (e.category != null) 'c': e.category,
                    if (e.printId != null) 'p': e.printId,
                  },
              ],
            },
        ],
        if (collection.isNotEmpty)
          'collection': [
            for (final MapEntry(key: o, value: n) in collection.entries)
              {'o': o, if (names[o] != null) 'name': names[o], 'n': n},
          ],
        if (games.isNotEmpty)
          'games': [
            for (final g in games)
              {
                'format': g.format,
                'players': [for (final p in g.players) p.toJson()],
                if (g.winner != null) 'winner': g.winner,
                if (g.myDeckId != null) 'deck': g.myDeckId,
                'won': g.myWon,
                'turns': g.turns,
                'seconds': g.duration.inSeconds,
                'network': g.network,
                'at': g.playedAt.toIso8601String(),
              },
          ],
        if (preferredPrints.isNotEmpty) 'preferred': preferredPrints,
        if (prints.isNotEmpty) 'prints': [for (final p in prints) p.toJson()],
      };

  String encode() => const JsonEncoder.withIndent(' ').convert(toJson());

  /// Lê um backup. Lança [FormatException] se não for um ficheiro do EDHere.
  static Backup decode(String text) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      throw FormatException(cardDbTr('Este ficheiro não é um backup do EDHere.'));
    }
    if (raw is! Map || raw['kind'] != kind) {
      throw FormatException(cardDbTr('Este ficheiro não é um backup do EDHere.'));
    }
    final j = raw.cast<String, dynamic>();
    if ((j['version'] as num? ?? 1) > version) {
      throw FormatException(cardDbTr('Backup de uma versão mais recente da app. Atualiza o EDHere.'));
    }
    final names = <String, String>{};
    List<Map<String, dynamic>> list(String k) =>
        [for (final x in (j[k] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    DateTime? date(Object? s) => s is String ? DateTime.tryParse(s) : null;
    return Backup(
      exportedAt: date(j['exported']),
      decks: [
        for (final d in list('decks'))
          Deck(
            id: (d['id'] as num?)?.toInt(),
            name: d['name'] as String? ?? cardDbTr('Deck'),
            format: d['format'] as String? ?? 'free',
            notes: d['notes'] as String? ?? '',
            createdAt: date(d['created']),
            entries: [
              for (final c in (d['cards'] as List? ?? const []).cast<Map>())
                if (c['o'] is String)
                  () {
                    if (c['name'] is String) names[c['o'] as String] = c['name'] as String;
                    return DeckEntry(
                      oracleId: c['o'] as String,
                      qty: (c['n'] as num?)?.toInt() ?? 1,
                      board: Board.byId(c['b'] as String? ?? 'main'),
                      category: c['c'] as String?,
                      printId: c['p'] as String?,
                    );
                  }(),
            ],
          ),
      ],
      collection: {
        for (final c in list('collection'))
          if (c['o'] is String) c['o'] as String: (c['n'] as num?)?.toInt() ?? 1,
      },
      games: [
        for (final g in list('games'))
          GameRecord(
            format: g['format'] as String? ?? 'free',
            players: [
              for (final p in (g['players'] as List? ?? const []))
                GamePlayer.fromJson((p as Map).cast<String, dynamic>()),
            ],
            winner: g['winner'] as String?,
            myDeckId: (g['deck'] as num?)?.toInt(),
            myWon: g['won'] == true,
            turns: (g['turns'] as num?)?.toInt() ?? 0,
            duration: Duration(seconds: (g['seconds'] as num?)?.toInt() ?? 0),
            network: g['network'] == true,
            playedAt: date(g['at']) ?? DateTime.now(),
          ),
      ],
      preferredPrints: (j['preferred'] as Map? ?? const {}).cast<String, String>(),
      prints: [for (final p in list('prints')) PrintInfo.fromJson(p)],
      names: {
        ...names,
        for (final c in list('collection'))
          if (c['o'] is String && c['name'] is String) c['o'] as String: c['name'] as String,
      },
    );
  }
}

/// O que um import fez (para mostrar ao utilizador).
class BackupResult {
  int decksAdded = 0;
  int decksSkipped = 0;
  int cardsAdded = 0;
  int gamesAdded = 0;

  /// Cartas que não existem nesta base (nem pelo Oracle ID, nem pelo nome).
  final Set<String> missing = {};
}

/// Junta um backup ao que já existe, sem apagar nada:
/// - decks iguais (mesmo nome, ou o mesmo com "(importado)", e mesmas cartas)
///   não se repetem; com o mesmo nome e cartas diferentes entram como "(importado)";
/// - nos decks, as cartas que esta base não conhece ficam (e contam em [missing]);
/// - na coleção fica a quantidade maior;
/// - partidas já existentes (mesma data e formato) não se repetem.
/// [resolve] diz se uma carta existe nesta base, e procura pelo nome quando
/// o Oracle ID não existe (devolve o Oracle ID a usar, ou null).
BackupResult importBackup(
  DeckStore store,
  Backup b, {
  bool decks = true,
  bool collection = true,
  bool games = true,
  String? Function(String oracleId, String? name)? resolve,
}) {
  final r = BackupResult();
  String? fix(String oracleId) {
    if (resolve == null) return oracleId;
    final id = resolve(oracleId, b.names[oracleId]);
    if (id == null) r.missing.add(b.names[oracleId] ?? oracleId);
    return id;
  }

  if (b.prints.isNotEmpty) store.savePrints(b.prints);
  final deckIds = <int, int>{};
  if (decks) {
    final existing = store.listDecks();
    String sig(Deck d) => ([
          for (final e in d.entries) '${e.oracleId}|${e.board.id}|${e.qty}',
        ]..sort())
            .join(';');
    for (final d in b.decks) {
      final entries = <DeckEntry>[];
      for (final e in d.entries) {
        // a carta que esta base não conhece fica no deck com o Oracle ID do
        // backup: a validação avisa e ela aparece quando a base for atualizada
        // (deitá-la fora perdia-a, e importar de novo criava outro deck)
        final id = fix(e.oracleId) ?? e.oracleId;
        final i = entries.indexWhere((x) => x.oracleId == id && x.board == e.board);
        if (i >= 0) {
          entries[i] = entries[i].copyWith(qty: entries[i].qty + e.qty);
        } else {
          entries.add(DeckEntry(
              oracleId: id, qty: e.qty, board: e.board, category: e.category, printId: e.printId));
        }
      }
      final incoming = Deck(name: d.name, format: d.format, notes: d.notes, entries: entries);
      // o mesmo deck pode já ter entrado como "X (importado)" numa importação anterior
      final same = existing.where((x) => x.name == d.name || x.name == '${d.name} (importado)').toList();
      final twin = same.where((x) => sig(x) == sig(incoming)).firstOrNull;
      if (twin != null) {
        r.decksSkipped++;
        if (d.id != null) deckIds[d.id!] = twin.id!;
        continue;
      }
      final saved = store.save(same.isEmpty ? incoming : incoming.copyWith(name: '${d.name} (importado)'));
      existing.add(saved);
      if (d.id != null) deckIds[d.id!] = saved.id!;
      r.decksAdded++;
    }
  }
  if (collection && b.collection.isNotEmpty) {
    final have = store.collection();
    final add = <String, int>{};
    for (final MapEntry(key: o, value: n) in b.collection.entries) {
      final id = fix(o);
      if (id == null) continue;
      add[id] = (add[id] ?? 0) + n;
    }
    r.cardsAdded = add.entries.where((e) => e.value > (have[e.key] ?? 0)).length;
    store.addOwned(add, atLeast: true);
  }
  if (games && b.games.isNotEmpty) {
    final seen = {for (final g in store.listGames()) '${g.playedAt.millisecondsSinceEpoch}|${g.format}'};
    for (final g in b.games) {
      if (!seen.add('${g.playedAt.millisecondsSinceEpoch}|${g.format}')) continue;
      store.saveGame(GameRecord(
        format: g.format,
        players: g.players,
        winner: g.winner,
        myDeckId: g.myDeckId == null ? null : deckIds[g.myDeckId],
        myWon: g.myWon,
        turns: g.turns,
        duration: g.duration,
        network: g.network,
        playedAt: g.playedAt,
      ));
      r.gamesAdded++;
    }
  }
  for (final MapEntry(key: o, value: p) in b.preferredPrints.entries) {
    if (!store.preferredPrints().containsKey(o)) store.setPreferredPrint(o, p);
  }
  return r;
}
