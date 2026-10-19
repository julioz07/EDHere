import 'dart:async';
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:flutter/foundation.dart';

import 'app_paths.dart';
import 'scryfall.dart';
import '../l10n/l10n.dart';

/// Pacote de imagens: uma lista de cartas calculada a partir da base local.
/// As imagens guardam-se uma vez por carta; os pacotes só as listam.
class ImagePack {
  const ImagePack(this.id, this._label, this._description, this.where);
  final String id;
  final String _label;
  final String _description;

  String get label => tr(_label);
  String get description => tr(_description);

  /// Condição SQL sobre `cards`; null = cartas dos meus decks.
  final String? where;

  static String _legal(String f) => "EXISTS (SELECT 1 FROM legalities l WHERE l.oracle_id = cards.oracle_id "
      "AND l.format = '$f' AND l.status IN ('legal','restricted'))";
  static const _base = 'is_extra = 0 AND is_paper = 1';

  static final all = [
    const ImagePack('mine', 'As minhas cartas', 'Todas as cartas dos meus decks', null),
    ImagePack('commander', 'Commander', 'Cartas legais em Commander', '$_base AND ${_legal('commander')}'),
    ImagePack('commander_modern', 'Commander + Modern', 'Legais em Commander ou Modern',
        '$_base AND (${_legal('commander')} OR ${_legal('modern')})'),
    ImagePack('modern', 'Modern', 'Cartas legais em Modern', '$_base AND ${_legal('modern')}'),
    ImagePack('pioneer', 'Pioneer', 'Cartas legais em Pioneer', '$_base AND ${_legal('pioneer')}'),
    ImagePack('standard', 'Standard', 'Cartas legais em Standard', '$_base AND ${_legal('standard')}'),
    ImagePack('pauper', 'Pauper', 'Cartas legais em Pauper', '$_base AND ${_legal('pauper')}'),
    ImagePack('legacy', 'Legacy', 'Cartas legais em Legacy', '$_base AND ${_legal('legacy')}'),
    const ImagePack('tokens', 'Tokens e emblemas', 'Todos os tokens oficiais', 'is_token = 1'),
    const ImagePack('all', 'Tudo', 'Todas as cartas, uma impressão por carta', _base),
  ];
}

/// Tamanho médio medido no Scryfall (outubro de 2026).
const Map<String, int> avgImageBytes = {'small': 15 * 1024, 'normal': 108 * 1024};

class PackStatus {
  const PackStatus(this.total, this.missing);
  final int total;
  final int missing;
  int estimateBytes(String size) => missing * avgImageBytes[size]!;
}

class PackJob {
  PackJob(this.pack, this.size, this.total);
  final ImagePack pack;
  final String size;
  final int total;
  int done = 0;
  int failed = 0;
  bool cancelled = false;
}

/// Imagens no disco e descarga de pacotes a partir de cards.scryfall.io.
class ImageService extends ChangeNotifier {
  ImageService(this.paths) {
    _scan();
  }

  final AppPaths paths;
  final Map<String, Set<String>> _have = {'small': {}, 'normal': {}};
  PackJob? job;
  String? lastError;

  void _scan() {
    for (final size in _have.keys) {
      final dir = Directory(paths.imagesDir(size));
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync()) {
        final name = f.uri.pathSegments.last;
        if (name.endsWith('.jpg')) _have[size]!.add(name.substring(0, name.length - 4));
      }
    }
  }

  int count(String size) => _have[size]!.length;

  bool has(String size, String key) => _have[size]!.contains(key);

  /// Ficheiro da imagem, ou null se não estiver descarregada.
  File? file(String size, String key) => has(size, key) ? File(paths.image(size, key)) : null;

  /// A melhor imagem disponível: a do tamanho pedido ou a outra.
  File? best(String key, {bool preferNormal = false}) =>
      preferNormal ? file('normal', key) ?? file('small', key) : file('small', key) ?? file('normal', key);

  final Map<String, List<ImageRef>> _refCache = {};
  CardRepository? _refRepo;

  /// Imagens de um pacote. As listas dos pacotes por formato só mudam
  /// quando a base de cartas muda, por isso ficam em cache.
  /// [mine]: as cartas dos decks já com a versão escolhida em cada deck (o
  /// pacote "As minhas cartas" descarrega essas, não as versões por defeito).
  List<ImageRef> refsFor(ImagePack pack, CardRepository repo, Set<String> deckIds, {List<Card>? mine}) {
    if (!identical(repo, _refRepo)) {
      _refCache.clear();
      _refRepo = repo;
    }
    if (pack.where == null) {
      final cards = mine ?? repo.getMany(deckIds).values.toList();
      final seen = <String>{};
      return [
        for (final c in cards)
          for (final r in ImageRef.allOf(c))
            if (seen.add(r.key)) r,
      ];
    }
    return _refCache.putIfAbsent(pack.id, () => repo.imageRefs(pack.where!));
  }

  PackStatus status(List<ImageRef> refs, String size) =>
      PackStatus(refs.length, refs.where((r) => !has(size, r.key)).length);

  /// Descarrega as imagens em falta. Corre até ao fim, a não ser que se
  /// cancele; falhas individuais são contadas e saltadas.
  Future<void> download(ImagePack pack, String size, List<ImageRef> refs, {void Function()? onDone}) async {
    if (job != null) return;
    final todo = refs.where((r) => !has(size, r.key)).toList();
    final j = job = PackJob(pack, size, todo.length);
    lastError = null;
    notifyListeners();
    final client = newHttpClient()..maxConnectionsPerHost = 8;
    var next = 0;
    var lastNotify = DateTime.now();

    Future<void> worker() async {
      while (!j.cancelled && next < todo.length) {
        final ref = todo[next++];
        final url = size == 'small' ? ref.small : ref.normal;
        if (url == null) {
          j.done++;
          continue;
        }
        try {
          await _fetch(client, url, paths.image(size, ref.key));
          _have[size]!.add(ref.key);
        } catch (e) {
          j.failed++;
          lastError = '$e';
        }
        j.done++;
        if (DateTime.now().difference(lastNotify).inMilliseconds > 250) {
          lastNotify = DateTime.now();
          notifyListeners();
        }
      }
    }

    await Future.wait(List.generate(8, (_) => worker()));
    client.close(force: true);
    job = null;
    notifyListeners();
    if (!j.cancelled) onDone?.call();
  }

  void cancel() => job?.cancelled = true;

  Future<void> _fetch(HttpClient client, String url, String path) async {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', scryfallHeaders['User-Agent']!);
    final res = await req.close().timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('HTTP ${res.statusCode}');
    }
    final tmp = File('$path.part');
    await res.pipe(tmp.openWrite());
    await tmp.rename(path);
  }

  /// Descarrega em silêncio as imagens de algumas cartas (as de um deck).
  Future<void> ensure(Iterable<Card> cards) => ensureRefs(cards.expand(ImageRef.allOf));

  /// Descarrega em silêncio as imagens em falta (das duas resoluções, ou só
  /// das indicadas em [sizes]). Devolve as que ficaram por descarregar.
  Future<List<ImageRef>> ensureRefs(Iterable<ImageRef> refs,
      {List<String> sizes = const ['small', 'normal']}) async {
    final todo = refs.where((r) => sizes.any((s) => !has(s, r.key))).toList();
    if (todo.isEmpty) return const [];
    final failed = <ImageRef>[];
    final client = newHttpClient();
    try {
      var offline = false;
      for (final r in todo) {
        for (final size in sizes) {
          final url = size == 'small' ? r.small : r.normal;
          if (has(size, r.key)) continue;
          if (url == null || offline) {
            if (!failed.contains(r)) failed.add(r);
            continue;
          }
          try {
            await _fetch(client, url, paths.image(size, r.key));
            _have[size]!.add(r.key);
          } catch (_) {
            // Sem rede: não vale a pena tentar as restantes.
            offline = true;
            if (!failed.contains(r)) failed.add(r);
          }
        }
      }
    } finally {
      client.close(force: true);
      notifyListeners();
    }
    return failed;
  }

  /// Bytes de uma imagem guardada (para a enviar a outro dispositivo).
  Future<List<int>?> readBytes(String size, String key) async {
    final f = file(size, key);
    return f?.readAsBytes();
  }

  /// Guarda uma imagem recebida de outro dispositivo.
  Future<void> writeBytes(String size, String key, List<int> bytes) async {
    // Só nomes simples: uma chave vinda da rede não pode sair da pasta.
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key) || (size != 'small' && size != 'normal')) return;
    final f = File(paths.image(size, key));
    await f.writeAsBytes(bytes, flush: true);
    _have[size]!.add(key);
    notifyListeners();
  }

  Future<int> diskUsage(String size) async {
    var total = 0;
    final dir = Directory(paths.imagesDir(size));
    if (!dir.existsSync()) return 0;
    await for (final f in dir.list()) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  Future<void> deleteAll(String size) async {
    final dir = Directory(paths.imagesDir(size));
    if (dir.existsSync()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    _have[size]!.clear();
    notifyListeners();
  }
}
