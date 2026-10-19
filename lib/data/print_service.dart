import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:flutter/foundation.dart';

import 'image_service.dart';
import 'scryfall.dart';
import '../l10n/l10n.dart';

/// Versões alternativas (impressões) das cartas.
///
/// A lista de versões vem da API do Scryfall (só com rede). As versões
/// vistas ou escolhidas ficam guardadas na base do utilizador, por isso a
/// arte escolhida continua a aparecer offline.
class PrintService extends ChangeNotifier {
  PrintService(this.store, this.images) : _preferred = store.preferredPrints();

  final DeckStore store;
  final ImageService images;
  Map<String, String> _preferred;
  final Map<String, PrintInfo> _cache = {};
  final Map<String, List<PrintInfo>> _online = {};
  DateTime _lastRequest = DateTime(2000);

  /// Progresso do pacote "versões dos meus decks" (null = parado).
  ({int done, int total, int images})? packProgress;
  bool _cancelPack = false;

  String? preferredFor(String oracleId) => _preferred[oracleId];

  // Impressões que não estão na base (para não voltar a perguntar).
  final Set<String> _unknown = {};

  PrintInfo? info(String printId) {
    final hit = _cache[printId];
    if (hit != null) return hit;
    if (_unknown.contains(printId)) return null;
    final p = store.printInfo(printId);
    if (p == null) {
      _unknown.add(printId);
      return null;
    }
    return _cache[printId] = p;
  }

  /// A carta com a impressão escolhida: [printId] (a do deck) ou, sem ela,
  /// a versão preferida. Sem dados dessa impressão, fica a por defeito.
  Card resolve(Card base, {String? printId}) {
    final id = printId ?? _preferred[base.oracleId];
    if (id == null || id == base.printId) return base;
    final p = info(id);
    return p == null ? base : base.withPrint(p);
  }

  /// Impressão efetiva de uma entrada de deck (para a mesa).
  String? effectivePrint(String oracleId, String? deckPrintId) => deckPrintId ?? _preferred[oracleId];

  /// Guarda impressões recebidas (de outro jogador, por exemplo).
  void remember(Iterable<PrintInfo> prints) {
    final list = prints.toList();
    if (list.isEmpty) return;
    store.savePrints(list);
    for (final p in list) {
      _cache[p.printId] = p;
      _unknown.remove(p.printId);
    }
    notifyListeners();
  }

  /// Todas as versões de uma carta. Com rede, pergunta ao Scryfall; sem
  /// rede, devolve as que já se conhecem (e [offline] fica a true).
  Future<({List<PrintInfo> prints, bool offline})> versions(String oracleId) async {
    final hit = _online[oracleId];
    if (hit != null) return (prints: hit, offline: false);
    try {
      final list = await _fetchAll(oracleId);
      _online[oracleId] = list;
      remember(list);
      return (prints: list, offline: false);
    } catch (_) {
      return (prints: store.printsOf(oracleId), offline: true);
    }
  }

  Future<List<PrintInfo>> _fetchAll(String oracleId) async {
    var url = Uri.https('api.scryfall.com', '/cards/search', {
      'q': 'oracleid:$oracleId',
      'unique': 'prints',
      'order': 'released',
      'dir': 'desc',
      'include_extras': 'true',
      'include_variations': 'true',
    }).toString();
    final out = <PrintInfo>[];
    final client = newHttpClient();
    try {
      while (true) {
        // O Scryfall pede no máximo ~10 pedidos por segundo.
        final wait = const Duration(milliseconds: 110) - DateTime.now().difference(_lastRequest);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        _lastRequest = DateTime.now();
        final req = await client.getUrl(Uri.parse(url));
        scryfallHeaders.forEach(req.headers.set);
        final res = await req.close().timeout(const Duration(seconds: 20));
        final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
        if (res.statusCode != 200) {
          throw StateError(tr('Scryfall {statusCode}', {'statusCode': res.statusCode}));
        }
        for (final c in (body['data'] as List).cast<Map<String, dynamic>>()) {
          if (c['lang'] == 'en' || c['lang'] == null) out.add(PrintInfo.fromScryfall(c));
        }
        if (body['has_more'] != true) break;
        url = body['next_page'] as String;
      }
    } finally {
      client.close(force: true);
    }
    return out;
  }

  /// Escolhe uma versão: guarda-a e descarrega só as imagens dela.
  Future<void> use(Card base, PrintInfo p) async {
    remember([p]);
    await images.ensureRefs(ImageRef.allOf(base.withPrint(p)));
  }

  /// Versão preferida em todo o lado (null volta à por defeito).
  Future<void> setPreferred(Card base, PrintInfo? p) async {
    store.setPreferredPrint(base.oracleId, p?.printId);
    _preferred = store.preferredPrints();
    notifyListeners();
    if (p != null) await use(base, p);
  }

  /// Pede ao Scryfall as impressões com estas coleções e números, em lotes
  /// de 75 (o máximo da API). Lança se não houver rede.
  Future<List<PrintInfo>> _bySetNumber(List<({String set, String number})> ids,
      {void Function(int done, int total)? onProgress}) async {
    final out = <PrintInfo>[];
    final client = newHttpClient();
    try {
      for (var i = 0; i < ids.length; i += 75) {
        final batch = ids.skip(i).take(75).toList();
        final wait = const Duration(milliseconds: 110) - DateTime.now().difference(_lastRequest);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        _lastRequest = DateTime.now();
        final req = await client.postUrl(Uri.https('api.scryfall.com', '/cards/collection'));
        scryfallHeaders.forEach(req.headers.set);
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({
          'identifiers': [
            for (final e in batch) {'set': e.set, 'collector_number': e.number},
          ],
        }));
        final res = await req.close().timeout(const Duration(seconds: 30));
        final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
        if (res.statusCode != 200) {
          throw StateError(tr('Scryfall {statusCode}', {'statusCode': res.statusCode}));
        }
        out.addAll([
          for (final c in (body['data'] as List).cast<Map<String, dynamic>>()) PrintInfo.fromScryfall(c),
        ]);
        onProgress?.call((i + batch.length).clamp(0, ids.length), ids.length);
      }
    } finally {
      client.close(force: true);
    }
    remember(out);
    return out;
  }

  /// Usa como preferidas as versões que tenho (coleção + número, como vêm
  /// do ManaBox). Pede ao Scryfall em lotes de 75. Devolve quantas ficaram.
  Future<int> preferOwnedPrints(Map<String, ({String set, String number})> owned, Map<String, Card> cards,
      {void Function(int done, int total)? onProgress}) async {
    final ids = owned.entries.where((e) => cards[e.key] != null).toList();
    var applied = 0;
    try {
      final found = await _bySetNumber([for (final e in ids) e.value], onProgress: onProgress);
      for (final p in found) {
        if (cards[p.oracleId] == null) continue;
        store.setPreferredPrint(p.oracleId, p.printId);
        applied++;
      }
    } finally {
      _preferred = store.preferredPrints();
      notifyListeners();
    }
    return applied;
  }

  /// As versões indicadas numa lista importada ("1 Sol Ring (CMR) 472"):
  /// Oracle ID -> impressão a guardar no deck (null = é a versão por defeito).
  /// Primeiro procura nas versões já conhecidas; o resto pede ao Scryfall.
  /// Sem rede, [offline] fica a true e as que faltam ficam na por defeito.
  Future<({Map<String, String?> prints, int missing, bool offline})> listPrints(
      Map<String, ({String set, String number})> wanted, Map<String, Card> cards,
      {void Function(int done, int total)? onProgress}) async {
    bool same(String a, String b) => a.toLowerCase() == b.toLowerCase();
    final out = <String, String?>{};
    final ask = <String, ({String set, String number})>{};
    for (final MapEntry(key: oracle, value: w) in wanted.entries) {
      final base = cards[oracle];
      if (base == null) continue;
      if (same(base.setCode, w.set) && same(base.collectorNumber, w.number)) {
        out[oracle] = null;
        continue;
      }
      final known =
          store.printsOf(oracle).where((p) => same(p.setCode, w.set) && same(p.collectorNumber, w.number));
      if (known.isNotEmpty) {
        out[oracle] = known.first.printId;
      } else {
        ask[oracle] = w;
      }
    }
    var offline = false;
    if (ask.isNotEmpty) {
      try {
        final found = await _bySetNumber(ask.values.toList(), onProgress: onProgress);
        for (final MapEntry(key: oracle, value: w) in ask.entries) {
          final p = found.where(
              (p) => p.oracleId == oracle && same(p.setCode, w.set) && same(p.collectorNumber, w.number));
          if (p.isNotEmpty) out[oracle] = p.first.printId;
        }
      } catch (_) {
        offline = true;
      }
    }
    // Imagens pequenas das versões escolhidas (em silêncio, se houver rede).
    final refs = [
      for (final MapEntry(key: oracle, value: id) in out.entries)
        if (id != null && cards[oracle] != null && info(id) != null)
          ...ImageRef.allOf(cards[oracle]!.withPrint(info(id)!)),
    ];
    if (!offline && refs.isNotEmpty) unawaited(images.ensureRefs(refs, sizes: const ['small']));
    return (prints: out, missing: wanted.length - out.length, offline: offline);
  }

  void cancelPack() => _cancelPack = true;

  /// Pacote "versões alternativas dos meus decks": todas as versões das
  /// cartas dos decks, com as imagens pequenas.
  Future<void> downloadVersionsFor(Map<String, Card> cards) async {
    if (packProgress != null) return;
    _cancelPack = false;
    var images = 0;
    packProgress = (done: 0, total: cards.length, images: 0);
    notifyListeners();
    var done = 0;
    for (final card in cards.values) {
      if (_cancelPack) break;
      final v = await versions(card.oracleId);
      if (v.offline) break;
      final refs = [for (final p in v.prints) ...ImageRef.allOf(card.withPrint(p))];
      await this.images.ensureRefs(refs, sizes: const ['small']);
      images += refs.length;
      done++;
      packProgress = (done: done, total: cards.length, images: images);
      notifyListeners();
    }
    packProgress = null;
    notifyListeners();
  }
}
