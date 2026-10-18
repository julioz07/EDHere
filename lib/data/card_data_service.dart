import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:card_db/card_db.dart';
import 'package:flutter/foundation.dart';

import '../net/discovery.dart' as net;
import 'app_paths.dart';
import 'scryfall.dart';

enum DataPhase { idle, checking, downloading, importing, error }

/// Gere a base de cartas local: abrir, verificar novidades, descarregar
/// o bulk do Scryfall e convertê-lo noutro isolate.
class CardDataService extends ChangeNotifier {
  CardDataService(this.paths) {
    _repo = CardRepository.open(paths.cardsDb);
    net.cardDbVersion = localDate ?? 'none';
  }

  final AppPaths paths;
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
  bool get busy => phase == DataPhase.checking ||
      phase == DataPhase.downloading ||
      phase == DataPhase.importing;

  Map<String, String> get meta => _repo?.meta ?? const {};
  String? get localDate => meta['bulk_updated_at'];
  int get cardCount => int.tryParse(meta['card_count'] ?? '') ?? 0;
  bool get hasRulings => meta['rulings'] == '1';

  bool get updateAvailable =>
      remoteOracle != null && remoteOracle!.updatedAt != localDate;

  void _set(DataPhase p, {double? progress, String? message}) {
    phase = p;
    this.progress = progress;
    if (message != null) this.message = message;
    notifyListeners();
  }

  /// Consulta o Scryfall para saber se há dados novos.
  Future<void> checkRemote() async {
    if (busy) return;
    _set(DataPhase.checking, message: 'A verificar o Scryfall…');
    try {
      final idx = await fetchBulkIndex();
      remoteOracle = idx['oracle_cards'];
      remoteRulings = idx['rulings'];
      _set(DataPhase.idle,
          message: updateAvailable ? 'Há dados novos no Scryfall.' : 'A base está atualizada.');
    } catch (e) {
      _set(DataPhase.error, message: 'Sem ligação ao Scryfall ($e).');
    }
  }

  void cancel() => _cancel = true;

  /// Descarrega e converte a base. A antiga só é substituída no fim.
  Future<void> update({bool includeRulings = false}) async {
    if (busy) return;
    _cancel = false;
    try {
      if (remoteOracle == null) {
        _set(DataPhase.checking, message: 'A verificar o Scryfall…');
        final idx = await fetchBulkIndex();
        remoteOracle = idx['oracle_cards'];
        remoteRulings = idx['rulings'];
      }
      final oracle = remoteOracle!;
      final oraclePath = paths.download('oracle.jsonl.gz');
      final rulingsPath = paths.download('rulings.jsonl.gz');
      final rulings = includeRulings ? remoteRulings : null;
      final totalBytes = oracle.compressedSize + (rulings?.compressedSize ?? 0);

      _set(DataPhase.downloading, progress: 0, message: 'A descarregar cartas…');
      await downloadFile(oracle.url, oraclePath,
          cancelled: () => _cancel,
          onProgress: (r, t) => _progress(r / (totalBytes == 0 ? (t <= 0 ? 1 : t) : totalBytes),
              'A descarregar cartas… ${_mb(r)} de ${_mb(oracle.compressedSize)}'));
      if (rulings != null) {
        await downloadFile(rulings.url, rulingsPath,
            cancelled: () => _cancel,
            onProgress: (r, _) => _progress(
                (oracle.compressedSize + r) / totalBytes, 'A descarregar rulings… ${_mb(r)}'));
      }

      _set(DataPhase.importing, progress: 0, message: 'A preparar a base offline…');
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
        onProgress: (n) => _progress(
            (n / expected).clamp(0, 0.99), 'A preparar a base offline… $n cartas'),
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
      _set(DataPhase.idle, progress: null, message: 'Base atualizada: $cardCount cartas.');
    } on DownloadCancelled {
      _set(DataPhase.idle, message: 'Descarga cancelada.');
    } catch (e) {
      final partial = File(paths.cardsDbNew);
      if (partial.existsSync()) partial.deleteSync();
      _repo ??= CardRepository.open(paths.cardsDb);
      _set(DataPhase.error, message: 'Falhou: $e');
    }
  }

  void _progress(double p, String msg) {
    progress = p;
    message = msg;
    notifyListeners();
  }

  static String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
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
    Stream<String> lines(String path) => File(path)
        .openRead()
        .transform(gzip.decoder)
        .transform(utf8.decoder)
        .transform(const LineSplitter());
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
