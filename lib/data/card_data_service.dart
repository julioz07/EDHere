import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:card_db/card_db.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../net/discovery.dart' as net;
import 'app_paths.dart';
import 'scryfall.dart';
import '../l10n/l10n.dart';

enum DataPhase { idle, checking, downloading, importing, error }

/// Gere a base de cartas local: abrir, verificar novidades, descarregar
/// o bulk do Scryfall e convertê-lo noutro isolate.
class CardDataService extends ChangeNotifier {
  CardDataService(this.paths, [this.prefs]) {
    _repo = CardRepository.open(paths.cardsDb);
    net.cardDbVersion = localDate ?? 'none';
  }

  final AppPaths paths;
  final SharedPreferences? prefs;

  static const cardLangKey = 'card_lang';

  /// Língua em que o utilizador quer as cartas: a escolhida, ou a da app.
  String get wantedCardLang => prefs?.getString(cardLangKey) ?? L10n.lang.code;

  /// Língua das cartas que está na base ("en" = só inglês).
  String get cardLang => _repo?.cardLang ?? 'en';

  /// Cartas traduzidas na base.
  int get localizedCount => int.tryParse(meta['card_lang_count'] ?? '') ?? 0;

  /// A base está noutra língua da escolhida (falta descarregar).
  bool get languagePending => hasData && cardLang != wantedCardLang;

  /// Muda a língua das cartas e descarrega-a (ou volta ao inglês).
  Future<void> setCardLang(String code) async {
    await prefs?.setString(cardLangKey, code);
    notifyListeners();
    if (!hasData) return;
    // A meio de outra tarefa (a verificar novidades…): fica para o fim dela.
    if (busy) {
      _syncAfter = true;
      return;
    }
    await syncLanguage();
  }

  CardRepository? _repo;
  DataPhase phase = DataPhase.idle;

  /// 0..1 durante a descarga e a conversão; null quando indeterminado.
  double? progress;
  String message = '';
  BulkFile? remoteOracle;
  BulkFile? remoteRulings;
  bool _cancel = false;

  /// Contador que muda sempre que a base é substituída.
  int generation = 0;

  CardRepository? get repo => _repo;
  bool get hasData => _repo != null;
  bool get busy =>
      phase == DataPhase.checking || phase == DataPhase.downloading || phase == DataPhase.importing;

  Map<String, String> get meta => _repo?.meta ?? const {};
  String? get localDate => meta['bulk_updated_at'];
  int get cardCount => int.tryParse(meta['card_count'] ?? '') ?? 0;
  bool get hasRulings => meta['rulings'] == '1';

  bool get updateAvailable => remoteOracle != null && remoteOracle!.updatedAt != localDate;

  bool _syncAfter = false;

  void _set(DataPhase p, {double? progress, String? message}) {
    phase = p;
    this.progress = progress;
    if (message != null) this.message = message;
    notifyListeners();
    if (!busy && _syncAfter) {
      _syncAfter = false;
      if (languagePending) Future.microtask(syncLanguage);
    }
  }

  /// Consulta o Scryfall para saber se há dados novos.
  Future<void> checkRemote() async {
    if (busy) return;
    _set(DataPhase.checking, message: tr('A verificar o Scryfall…'));
    try {
      final idx = await fetchBulkIndex();
      remoteOracle = idx['oracle_cards'];
      remoteRulings = idx['rulings'];
      _set(DataPhase.idle,
          message: updateAvailable ? tr('Há dados novos no Scryfall.') : tr('A base está atualizada.'));
    } catch (e) {
      _set(DataPhase.error, message: tr('Sem ligação ao Scryfall ({e}).', {'e': e}));
    }
  }

  void cancel() => _cancel = true;

  /// Descarrega e converte a base. A antiga só é substituída no fim.
  Future<void> update({bool includeRulings = false}) async {
    if (busy) return;
    _cancel = false;
    try {
      if (remoteOracle == null) {
        _set(DataPhase.checking, message: tr('A verificar o Scryfall…'));
        final idx = await fetchBulkIndex();
        remoteOracle = idx['oracle_cards'];
        remoteRulings = idx['rulings'];
      }
      final oracle = remoteOracle!;
      final oraclePath = paths.download('oracle.jsonl.gz');
      final rulingsPath = paths.download('rulings.jsonl.gz');
      final rulings = includeRulings ? remoteRulings : null;
      final totalBytes = oracle.compressedSize + (rulings?.compressedSize ?? 0);

      _set(DataPhase.downloading, progress: 0, message: tr('A descarregar cartas…'));
      await downloadFile(oracle.url, oraclePath,
          cancelled: () => _cancel,
          onProgress: (r, t) => _progress(r / (totalBytes == 0 ? (t <= 0 ? 1 : t) : totalBytes),
              tr('A descarregar cartas… {v} de {v2}', {'v': _mb(r), 'v2': _mb(oracle.compressedSize)})));
      if (rulings != null) {
        await downloadFile(rulings.url, rulingsPath,
            cancelled: () => _cancel,
            onProgress: (r, _) => _progress(
                (oracle.compressedSize + r) / totalBytes, tr('A descarregar rulings… {v}', {'v': _mb(r)})));
      }

      _set(DataPhase.importing, progress: 0, message: tr('A preparar a base offline…'));
      const expected = 38000; // aproximado; só serve para a barra
      await _importInIsolate(
        oraclePath: oraclePath,
        rulingsPath: rulings == null ? null : rulingsPath,
        outPath: paths.cardsDbNew,
        meta: {
          'bulk_updated_at': oracle.updatedAt,
          'rulings': rulings == null ? '0' : '1',
          'imported_at': DateTime.now().toIso8601String(),
        },
        onProgress: (n) =>
            _progress((n / expected).clamp(0, 0.99), tr('A preparar a base offline… {n} cartas', {'n': n})),
      );

      // Troca a base antiga pela nova.
      _repo?.close();
      _repo = null;
      final old = File(paths.cardsDb);
      if (old.existsSync()) old.deleteSync();
      File(paths.cardsDbNew).renameSync(paths.cardsDb);
      _repo = CardRepository.open(paths.cardsDb);
      generation++;
      net.cardDbVersion = localDate ?? 'none';
      for (final f in [oraclePath, rulingsPath]) {
        if (File(f).existsSync()) File(f).deleteSync();
      }
      _set(DataPhase.idle,
          progress: null, message: tr('Base atualizada: {cardCount} cartas.', {'cardCount': cardCount}));
      // A base nova vem só em inglês: volta a juntar a língua escolhida.
      if (wantedCardLang != 'en') await syncLanguage();
    } on DownloadCancelled {
      _set(DataPhase.idle, message: tr('Descarga cancelada.'));
    } catch (e) {
      final partial = File(paths.cardsDbNew);
      if (partial.existsSync()) partial.deleteSync();
      _repo ??= CardRepository.open(paths.cardsDb);
      _set(DataPhase.error, message: tr('Falhou: {e}', {'e': e}));
    }
  }

  /// Põe a base na língua escolhida: descarrega do Scryfall o nome, o texto e
  /// a impressão de cada carta nessa língua (as que existem; as outras ficam
  /// em inglês). Em inglês, apaga a tradução.
  Future<void> syncLanguage() async {
    if (busy || !hasData) return;
    final lang = wantedCardLang;
    _cancel = false;
    final label = langName(lang);
    try {
      if (lang == 'en') {
        _repo?.close();
        _repo = null;
        LocalizedImporter.clear(paths.cardsDb);
      } else {
        _set(DataPhase.downloading,
            progress: 0, message: tr('A descarregar as cartas em {lang}…', {'lang': label}));
        final base =
            'https://api.scryfall.com/cards/search?q=${Uri.encodeQueryComponent('lang:$lang game:paper')}'
            '&unique=cards&order=name';
        // A primeira página diz quantas há; as outras pedem-se várias de cada
        // vez (duas), com pelo menos 150 ms entre pedidos, como o Scryfall pede.
        final first = await _fetchPage(base);
        final total = first['total_cards'] as int? ?? 0;
        final perPage = (first['data'] as List).length;
        final pages = perPage == 0 ? 1 : (total / perPage).ceil();
        final results = <int, List<Map<String, dynamic>>>{1: (first['data'] as List).cast()};
        void report() {
          final n = results.values.fold<int>(0, (a, l) => a + l.length);
          _progress(
              total == 0 ? null : (n / total).clamp(0, 0.99),
              tr('A descarregar as cartas em {lang}… {n} de {total}',
                  {'lang': label, 'n': n, 'total': total}));
        }

        report();
        var next = 2;
        var lastStart = DateTime.now();
        Future<void> worker() async {
          while (next <= pages) {
            if (_cancel) throw const DownloadCancelled();
            final page = next++;
            final wait = const Duration(milliseconds: 150) - DateTime.now().difference(lastStart);
            lastStart = DateTime.now().add(wait.isNegative ? Duration.zero : wait);
            if (!wait.isNegative) await Future<void>.delayed(wait);
            final r = await _fetchPage('$base&page=$page');
            results[page] = (r['data'] as List).cast();
            report();
          }
        }

        await Future.wait([for (var i = 0; i < 2; i++) worker()]);
        final cards = [for (var i = 1; i <= pages; i++) ...?results[i]];
        _set(DataPhase.importing, progress: null, message: tr('A preparar a base offline…'));
        _repo?.close();
        _repo = null;
        final imp = LocalizedImporter(paths.cardsDb)..begin(lang);
        try {
          cards.forEach(imp.add);
          imp.finish();
        } catch (_) {
          imp.cancel();
          rethrow;
        }
      }
      _repo = CardRepository.open(paths.cardsDb);
      generation++;
      _set(DataPhase.idle,
          progress: null,
          message: lang == 'en'
              ? tr('Cartas em inglês.')
              : tr('Cartas em {lang}: {n} traduzidas.', {'lang': label, 'n': localizedCount}));
    } on DownloadCancelled {
      _repo ??= CardRepository.open(paths.cardsDb);
      _set(DataPhase.idle, progress: null, message: tr('Descarga cancelada.'));
    } catch (e) {
      _repo ??= CardRepository.open(paths.cardsDb);
      _set(DataPhase.error, progress: null, message: tr('Falhou: {e}', {'e': e}));
    }
  }

  /// Uma página da pesquisa do Scryfall, com novas tentativas se falhar.
  static Future<Map<String, dynamic>> _fetchPage(String url) async {
    const attempts = 7;
    for (var attempt = 0;; attempt++) {
      final client = newHttpClient();
      var wait = Duration(seconds: 1 << attempt);
      try {
        final req = await client.getUrl(Uri.parse(url));
        scryfallHeaders.forEach(req.headers.set);
        final res = await req.close().timeout(const Duration(seconds: 30));
        final body = await res.transform(utf8.decoder).join();
        if (res.statusCode == 200) {
          return await Isolate.run(() {
            final page = jsonDecode(body) as Map<String, dynamic>;
            return {
              ...page,
              'data': [
                for (final c in (page['data'] as List).cast<Map<String, dynamic>>())
                  LocalizedImporter.slim(c),
              ],
            };
          });
        }
        if (attempt >= attempts || (res.statusCode != 429 && res.statusCode < 500)) {
          throw HttpException(tr('Scryfall respondeu {statusCode}', {'statusCode': res.statusCode}));
        }
        // Demasiados pedidos: espera o que o Scryfall pedir (ou cada vez mais).
        final retry = int.tryParse(res.headers.value('retry-after') ?? '');
        if (retry != null) wait = Duration(seconds: retry + 1);
      } on SocketException {
        if (attempt >= attempts) rethrow;
      } on TimeoutException {
        if (attempt >= attempts) rethrow;
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(wait);
    }
  }

  void _progress(double? p, String msg) {
    progress = p;
    message = msg;
    notifyListeners();
  }

  static String _mb(int bytes) => tr('{v} MB', {'v': (bytes / 1024 / 1024).toStringAsFixed(1)});
}

Future<void> _importInIsolate({
  required String oraclePath,
  required String? rulingsPath,
  required String outPath,
  required Map<String, String> meta,
  required void Function(int) onProgress,
}) async {
  final port = ReceivePort();
  final done = Completer<void>();
  await Isolate.spawn(_importEntry, [port.sendPort, oraclePath, rulingsPath, outPath, meta]);
  port.listen((msg) {
    if (msg is int) {
      onProgress(msg);
    } else if (msg == 'done') {
      done.complete();
      port.close();
    } else if (msg is String) {
      done.completeError(Exception(msg));
      port.close();
    }
  });
  return done.future;
}

Future<void> _importEntry(List<Object?> args) async {
  final send = args[0]! as SendPort;
  final oraclePath = args[1]! as String;
  final rulingsPath = args[2] as String?;
  final outPath = args[3]! as String;
  final meta = (args[4]! as Map).cast<String, String>();
  final imp = CardImporter(outPath);
  try {
    imp.open();
    Stream<String> lines(String path) =>
        File(path).openRead().transform(gzip.decoder).transform(utf8.decoder).transform(const LineSplitter());
    await imp.importLines(lines(oraclePath), onProgress: send.send);
    if (rulingsPath != null) await imp.importRulings(lines(rulingsPath));
    imp.finish(meta);
    send.send('done');
  } catch (e, st) {
    imp.abort();
    if (kDebugMode) debugPrint('$e\n$st');
    send.send('$e');
  }
}
