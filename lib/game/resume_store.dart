import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// O que é preciso para voltar a um jogo em rede depois de a app fechar:
/// onde está a sala, o token do lugar e a mão e o grimório (que só
/// existem neste dispositivo).
class ResumeInfo {
  const ResumeInfo({
    required this.room,
    required this.hosts,
    required this.port,
    required this.token,
    required this.seat,
    required this.name,
    required this.seq,
    required this.savedAt,
    this.pin,
    this.deckId,
    this.private,
  });

  final String room;
  final List<String> hosts;
  final int port;
  final String? pin;
  final String token;
  final int seat;
  final String name;
  final int? deckId;

  /// Último evento aplicado quando se guardou [private].
  final int seq;

  /// Zonas ocultas do meu lugar (ver `Table.exportPrivate`).
  final Map<String, dynamic>? private;
  final DateTime savedAt;

  /// Jogos com mais de umas horas já não valem a pena.
  bool get fresh => DateTime.now().difference(savedAt) < const Duration(hours: 8);

  Map<String, dynamic> toJson() => {
        'room': room,
        'hosts': hosts,
        'port': port,
        if (pin != null) 'pin': pin,
        'token': token,
        'seat': seat,
        'name': name,
        if (deckId != null) 'deck': deckId,
        'seq': seq,
        if (private != null) 'private': private,
        'at': savedAt.millisecondsSinceEpoch,
      };

  static ResumeInfo fromJson(Map<String, dynamic> j) => ResumeInfo(
        room: j['room'] as String,
        hosts: (j['hosts'] as List).cast<String>(),
        port: (j['port'] as num).toInt(),
        pin: j['pin'] as String?,
        token: j['token'] as String,
        seat: (j['seat'] as num).toInt(),
        name: j['name'] as String,
        deckId: (j['deck'] as num?)?.toInt(),
        seq: (j['seq'] as num).toInt(),
        private: (j['private'] as Map?)?.cast<String, dynamic>(),
        savedAt: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
      );
}

/// Guarda o [ResumeInfo] do jogo em curso (um de cada vez).
class ResumeStore extends ChangeNotifier {
  ResumeStore(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'resume_game';

  ResumeInfo? get current {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      final info = ResumeInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return info.fresh ? info : null;
    } catch (_) {
      return null;
    }
  }

  void save(ResumeInfo info) {
    final hadNone = _prefs.getString(_key) == null;
    _prefs.setString(_key, jsonEncode(info.toJson()));
    if (hadNone) notifyListeners();
  }

  void clear() {
    if (_prefs.getString(_key) == null) return;
    _prefs.remove(_key);
    notifyListeners();
  }
}
