import 'dart:async';
import 'dart:io';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';

/// Dificuldade do bot (ver ForgeBots.java).
enum BotLevel {
  easy('easy', 'Fácil'),
  normal('normal', 'Normal'),
  hard('hard', 'Difícil');

  const BotLevel(this.id, this._label);
  final String id;
  final String _label;
  String get label => tr(_label);
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
    int paceMs = 700,
  }) =>
      _ch.invokeMethod('start', {
        'format': commander ? 'commander' : 'constructed',
        'pace': paceMs,
        'seats': [for (final s in seats) s.toChannel(repo)],
      });

  static Future<void> stop() => _ch.invokeMethod('stop');

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
