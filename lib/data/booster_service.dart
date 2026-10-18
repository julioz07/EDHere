import 'dart:convert';
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dados de boosters e JumpStart que vêm dentro da app (gerados a partir do
/// MTGJSON por `tool/boosters/build_boosters.py`). Lê-se tudo dos assets:
/// funciona sem internet. Só as imagens das cartas vêm da rede (ou de outro
/// dispositivo na sala).
class BoosterService {
  static const _dir = 'assets/boosters';

  List<BoosterSetInfo>? _sets;
  List<String>? _oracles;
  List<JumpstartPacket>? _jumpstart;
  final Map<String, SetBoosters> _cache = {};

  /// Sets com boosters, do mais recente para o mais antigo.
  Future<List<BoosterSetInfo>> sets() async {
    final hit = _sets;
    if (hit != null) return hit;
    final j = jsonDecode(await rootBundle.loadString('$_dir/index.json')) as Map<String, dynamic>;
    // Sets anunciados mas ainda não lançados ficam de fora.
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _sets = [
      for (final s in (j['sets'] as List).cast<Map<String, dynamic>>())
        if ((s['date'] as String? ?? '').compareTo(today) <= 0) BoosterSetInfo.fromJson(s),
    ];
  }

  Future<List<String>> _oracleIds() async =>
      _oracles ??= ((await _gz('$_dir/oracles.json.gz')) as List).cast<String>();

  Future<SetBoosters> set(BoosterSetInfo info) async {
    final hit = _cache[info.code];
    if (hit != null) return hit;
    final oracles = await _oracleIds();
    final j = (await _gz('$_dir/set_${info.code.toLowerCase()}.json.gz')) as Map<String, dynamic>;
    return _cache[info.code] = SetBoosters.fromJson(info, j, oracles);
  }

  /// Todos os pacotes JumpStart (de todos os sets que os tiveram).
  Future<List<JumpstartPacket>> jumpstart() async {
    final hit = _jumpstart;
    if (hit != null) return hit;
    final oracles = await _oracleIds();
    final list = (await _gz('$_dir/jumpstart.json.gz')) as List;
    return _jumpstart = [
      for (final p in list.cast<Map<String, dynamic>>()) JumpstartPacket.fromJson(p, oracles),
    ];
  }

  /// Lê e descomprime um asset .json.gz noutro isolate (os ficheiros grandes
  /// demoram e não podem prender a interface).
  static Future<Object?> _gz(String asset) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return compute(_decode, bytes);
  }

  static Object? _decode(Uint8List bytes) => jsonDecode(utf8.decode(gzip.decode(bytes)));
}

final boosterServiceProvider = Provider<BoosterService>((_) => BoosterService());
