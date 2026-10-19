import 'dart:convert';
import 'dart:io';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/foundation.dart';
import '../l10n/l10n.dart';

/// Uma carta de booster em JSON (para guardar pools).
Map<String, dynamic> packCardToJson(db.PackCard c) => {
      's': c.print.scryfallId,
      'o': c.print.oracleId,
      'r': c.print.rarity,
      if (c.print.number.isNotEmpty) 'n': c.print.number,
      if (c.print.setCode.isNotEmpty) 'e': c.print.setCode,
      if (c.foil) 'f': 1,
    };

db.PackCard packCardFromJson(Map<String, dynamic> j) => db.PackCard(
      db.BoosterPrint(
          j['s'] as String? ?? '', j['o'] as String, j['r'] as String? ?? 'C', j['n'] as String? ?? '',
          setCode: j['e'] as String? ?? ''),
      foil: j['f'] == 1,
    );

/// Um deck de sealed ou draft por montar: a pool e o que já se escolheu.
/// Fica guardado enquanto se monta, para continuar depois (ou se a app fechar).
class LimitedBuild {
  LimitedBuild({
    required this.id,
    required this.title,
    required this.pool,
    this.commander = false,
    this.deck = const {},
    this.lands = const {},
    this.cmdPool = const [],
    this.cmdExtra = const [],
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();

  final String id;
  final String title;
  final bool commander;
  final List<db.PackCard> pool;

  /// Índices da pool que estão no deck.
  final Set<int> deck;

  /// Terrenos básicos por cor (W, U, B, R, G).
  final Map<String, int> lands;

  /// Comandantes: índices da pool e Oracle IDs dos que não vêm da pool.
  final List<int> cmdPool;
  final List<String> cmdExtra;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (commander) 'cmd': true,
        'pool': [for (final c in pool) packCardToJson(c)],
        'deck': deck.toList(),
        'lands': lands,
        'cmdPool': cmdPool,
        'cmdExtra': cmdExtra,
        'at': savedAt.millisecondsSinceEpoch,
      };

  static LimitedBuild fromJson(Map<String, dynamic> j) => LimitedBuild(
        id: j['id'] as String,
        title: j['title'] as String? ?? tr('Deck'),
        commander: j['cmd'] == true,
        pool: [for (final c in (j['pool'] as List).cast<Map>()) packCardFromJson(c.cast<String, dynamic>())],
        deck: {for (final i in (j['deck'] as List? ?? const []).cast<num>()) i.toInt()},
        lands: (j['lands'] as Map? ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toInt())),
        cmdPool: [for (final i in (j['cmdPool'] as List? ?? const []).cast<num>()) i.toInt()],
        cmdExtra: (j['cmdExtra'] as List? ?? const []).cast<String>(),
        savedAt: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
      );
}

/// Os decks por montar, num ficheiro da app (do mais recente para o mais antigo).
class LimitedBuildStore extends ChangeNotifier {
  LimitedBuildStore(String path) : _file = File(path) {
    try {
      if (_file.existsSync()) {
        _builds = [
          for (final b in (jsonDecode(_file.readAsStringSync()) as List).cast<Map>())
            LimitedBuild.fromJson(b.cast<String, dynamic>()),
        ];
      }
    } catch (_) {
      _builds = [];
    }
  }

  /// Mais do que isto e o mais antigo sai.
  static const keep = 6;

  final File _file;
  List<LimitedBuild> _builds = [];

  List<LimitedBuild> get builds => List.unmodifiable(_builds);

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  void put(LimitedBuild b) {
    final isNew = !_builds.any((x) => x.id == b.id);
    _builds = [b, ..._builds.where((x) => x.id != b.id)].take(keep).toList();
    _write();
    if (isNew) notifyListeners();
  }

  void remove(String id) {
    final before = _builds.length;
    _builds = _builds.where((x) => x.id != id).toList();
    if (_builds.length == before) return;
    _write();
    notifyListeners();
  }

  /// Avisa quem mostra a lista (depois de sair do ecrã de montar).
  void refresh() => notifyListeners();

  void _write() {
    final tmp = File('${_file.path}.tmp')
      ..writeAsStringSync(jsonEncode([for (final b in _builds) b.toJson()]), flush: true);
    tmp.renameSync(_file.path);
  }
}
