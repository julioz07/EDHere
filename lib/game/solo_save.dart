import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../l10n/l10n.dart';

/// Um jogo solo (goldfish ou partida de teste neste dispositivo) gravado para
/// continuar depois. Grava-se sozinho enquanto se joga, para não se perder
/// se o Android fechar a app.
class SoloSave {
  const SoloSave({
    required this.deckIds,
    required this.title,
    required this.turn,
    required this.savedAt,
    required this.game,
    this.names,
    this.tablet = false,
    this.openHands = false,
  });

  final List<int> deckIds;

  /// Para mostrar: "Goldfish · Atraxa" ou "Ana vs Rui".
  final String title;
  final int turn;
  final DateTime savedAt;

  /// O que [GameController.saveJson] devolve.
  final Map<String, dynamic> game;

  /// Como o jogo foi aberto (para abrir igual).
  final List<String>? names;
  final bool tablet;
  final bool openHands;

  Map<String, dynamic> toJson() => {
        'decks': deckIds,
        'title': title,
        'turn': turn,
        'at': savedAt.millisecondsSinceEpoch,
        if (names != null) 'names': names,
        if (tablet) 'tablet': true,
        if (openHands) 'open': true,
        'game': game,
      };

  static SoloSave fromJson(Map<String, dynamic> j) => SoloSave(
        deckIds: (j['decks'] as List).cast<num>().map((n) => n.toInt()).toList(),
        title: j['title'] as String? ?? tr('Jogo'),
        turn: (j['turn'] as num?)?.toInt() ?? 1,
        savedAt: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
        names: (j['names'] as List?)?.cast<String>(),
        tablet: j['tablet'] == true,
        openHands: j['open'] == true,
        game: (j['game'] as Map).cast<String, dynamic>(),
      );
}

/// O jogo solo gravado (um de cada vez), num ficheiro da app.
class SoloSaveStore extends ChangeNotifier {
  SoloSaveStore(String path) : _file = File(path) {
    try {
      if (_file.existsSync()) {
        _save = SoloSave.fromJson(jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>);
      }
    } catch (_) {
      // Ficheiro estragado (app fechada a meio de gravar): esquece.
      _save = null;
    }
  }

  final File _file;
  SoloSave? _save;

  SoloSave? get save => _save;

  void write(SoloSave s) {
    final had = _save != null;
    _save = s;
    // Grava num temporário e troca, para nunca ficar meio escrito.
    final tmp = File('${_file.path}.tmp')..writeAsStringSync(jsonEncode(s.toJson()), flush: true);
    tmp.renameSync(_file.path);
    if (!had) notifyListeners();
  }

  void clear() {
    if (_save == null && !_file.existsSync()) return;
    _save = null;
    if (_file.existsSync()) _file.deleteSync();
    notifyListeners();
  }

  /// Avisa quem mostra o cartão "Continuar jogo" (depois de sair da mesa).
  void refresh() => notifyListeners();
}
