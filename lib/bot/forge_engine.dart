import 'dart:async';
import 'dart:io';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';

/// Dificuldade do bot (ver ForgeBots.java).
enum BotLevel {
  easy('easy'),
  normal('normal'),
  hard('hard');

  const BotLevel(this.id);
  final String id;

  String get label => switch (this) {
        BotLevel.easy => tr('Fácil'),
        BotLevel.normal => tr('Normal'),
        BotLevel.hard => tr('Difícil'),
      };
}

/// A velocidade do bot: a base das pausas depois de cada jogada dele (ms).
enum BotSpeed {
  slow('slow', 1600),
  normal('normal', 1000),
  fast('fast', 500);

  const BotSpeed(this.id, this.paceMs);
  final String id;
  final int paceMs;

  String get label => switch (this) {
        BotSpeed.slow => tr('Lenta'),
        BotSpeed.normal => tr('Normal'),
        BotSpeed.fast => tr('Rápida'),
      };

  static const prefKey = 'bot_speed';
  static BotSpeed byId(String? id) => values.where((s) => s.id == id).firstOrNull ?? normal;
}

/// Onde o jogo pára à minha espera, por segmento da barra de fases (0 início,
/// 1 principal 1, 2 combate, 3 principal 2, 4 fim). Como as paragens do Arena.
class BotStops {
  BotStops({required this.mine, required this.theirs, this.full = false});

  /// Por defeito: as minhas fases principais; o ataque e o fim do turno do bot.
  factory BotStops.defaults() => BotStops(mine: {1, 3}, theirs: {2, 4});

  final Set<int> mine;
  final Set<int> theirs;

  /// Controlo total: pára em todas as fases e nunca passa sozinho.
  bool full;

  static List<String> phases(int segment, {required bool mine}) => switch (segment) {
        0 => ['UPKEEP', 'DRAW'],
        1 => ['MAIN1'],
        2 => mine ? ['COMBAT_BEGIN'] : ['COMBAT_DECLARE_ATTACKERS'],
        3 => ['MAIN2'],
        _ => ['END_OF_TURN'],
      };

  static const _kMine = 'bot_stops_mine', _kTheirs = 'bot_stops_theirs', _kFull = 'bot_full_control';

  static BotStops load(SharedPreferences p) {
    final d = BotStops.defaults();
    Set<int> read(String k, Set<int> def) => p.getStringList(k)?.map(int.parse).toSet() ?? def;
    return BotStops(mine: read(_kMine, d.mine), theirs: read(_kTheirs, d.theirs), full: p.getBool(_kFull) ?? false);
  }

  void save(SharedPreferences p) {
    p.setStringList(_kMine, [for (final i in mine) '$i']);
    p.setStringList(_kTheirs, [for (final i in theirs) '$i']);
    p.setBool(_kFull, full);
  }
}

/// Um lugar na partida contra o bot: quem joga e com que deck.
class ForgeSeat {
  const ForgeSeat({required this.name, required this.deck, this.bot});

  final String name;
  final db.Deck deck;

  /// null = pessoa; senão, a dificuldade do bot.
  final BotLevel? bot;

  /// O deck como o Forge o recebe: nomes Oracle (ingleses) e quantidades.
  Map<String, Object?> toChannel(db.CardRepository repo) {
    final entries = deck.entries.where((e) => e.board != db.Board.maybe).toList();
    final cards = repo.getMany(entries.map((e) => e.oracleId));
    return {
      'name': name,
      'bot': bot?.id,
      'deck': [
        for (final e in entries)
          if (cards[e.oracleId] != null) {'n': cards[e.oracleId]!.name, 'q': e.qty, 'b': e.board.id},
      ],
    };
  }
}

/// O motor do Forge, que corre no lado Android (MainActivity e o pacote forge).
abstract final class ForgeEngine {
  static const _ch = MethodChannel('edhere/forge');
  static const _ev = EventChannel('edhere/forge/events');
  static Stream<Map<String, dynamic>>? _events;

  /// Estados da mesa e eventos ("state", "over", "error") da partida a correr.
  static Stream<Map<String, dynamic>> get events =>
      _events ??= _ev.receiveBroadcastStream().map((e) => Map<String, dynamic>.from(e as Map)).asBroadcastStream();

  /// O bot só existe no Android 8.0 ou mais recente.
  static Future<bool> supported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('supported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// A memória total do aparelho em MB (null se não se souber): com muitos bots, avisa-se.
  static Future<int?> memoryMb() async {
    try {
      return await _ch.invokeMethod<int>('memoryMb');
    } on Exception {
      return null;
    }
  }

  /// Prepara os dados (da primeira vez) e arranca o motor; pode demorar alguns segundos.
  static Future<void> init() async {
    final res = await _ch.invokeMapMethod<String, dynamic>('init', {'language': _forgeLanguage()});
    if (res?['state'] != 'ready') {
      throw ForgeError(res?['error'] as String? ?? 'init');
    }
  }

  /// Cartas de cada lugar que o Forge ainda não sabe jogar (por lugar, pela ordem dada).
  static Future<List<List<String>>> checkDecks(List<ForgeSeat> seats, db.CardRepository repo) async {
    final res = await _ch.invokeMapMethod<String, dynamic>('checkDecks', {
      'seats': [for (final s in seats) s.toChannel(repo)],
    });
    return [
      for (var i = 0; i < seats.length; i++) [for (final n in (res?['$i'] as List? ?? const [])) n as String],
    ];
  }

  /// Começa uma partida; o estado chega por [events].
  /// [paceMs] abranda o bot para se ver o que fez (0 = à velocidade do motor).
  static Future<void> start({
    required List<ForgeSeat> seats,
    required db.CardRepository repo,
    required bool commander,
    int paceMs = 1000,
  }) =>
      _ch.invokeMethod('start', {
        'format': commander ? 'commander' : 'constructed',
        'pace': paceMs,
        'seats': [for (final s in seats) s.toChannel(repo)],
      });

  static Future<void> stop() => _ch.invokeMethod('stop');

  /// Muda a velocidade do bot a meio da partida.
  static Future<void> setPace(int ms) => _ch.invokeMethod('pace', {'ms': ms});

  /// Um toque da pessoa: [kind] é card, player, stack, ok, cancel ou concede.
  static Future<void> act(String kind, [int? id]) => _ch.invokeMethod('act', {'kind': kind, if (id != null) 'id': id});

  /// As paragens: fases (PhaseType) onde o Forge espera por mim, no meu turno e no do bot.
  static Future<void> setStops(BotStops stops) => _ch.invokeMethod('stops', {
        'mine': [for (final i in stops.mine) ...BotStops.phases(i, mine: true)],
        'theirs': [for (final i in stops.theirs) ...BotStops.phases(i, mine: false)],
        'full': stops.full,
      });

  /// A resposta a uma pergunta ("ask") do Forge.
  static Future<void> answer(int id, Object? value) => _ch.invokeMethod('answer', {'id': id, 'value': value});

  /// As línguas do Forge que temos (as mensagens do registo de jogo).
  static String _forgeLanguage() => switch (L10n.lang) {
        AppLang.pt => 'pt-BR',
        AppLang.es => 'es-ES',
        AppLang.it => 'it-IT',
        AppLang.en => 'en-US',
      };
}

class ForgeError implements Exception {
  ForgeError(this.message);
  final String message;
  @override
  String toString() => 'ForgeError: $message';
}
