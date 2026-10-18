import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Onde a app guarda as bases e as imagens.
class AppPaths {
  AppPaths._(this.root, this.cache);

  static Future<AppPaths> resolve() async {
    final docs = await getApplicationSupportDirectory();
    final cache = await getTemporaryDirectory();
    final paths = AppPaths._(docs.path, cache.path);
    for (final d in [paths.imagesDir('small'), paths.imagesDir('normal')]) {
      Directory(d).createSync(recursive: true);
    }
    return paths;
  }

  /// Para testes: tudo dentro de [root].
  factory AppPaths.forTest(String root) {
    final p = AppPaths._(root, root);
    for (final d in [p.imagesDir('small'), p.imagesDir('normal')]) {
      Directory(d).createSync(recursive: true);
    }
    return p;
  }

  final String root;
  final String cache;

  String get cardsDb => p.join(root, 'cards.sqlite');
  String get cardsDbNew => p.join(root, 'cards.sqlite.new');
  String get userDb => p.join(root, 'user.sqlite');
  String imagesDir(String size) => p.join(root, 'images', size);
  String image(String size, String key) => p.join(imagesDir(size), '$key.jpg');
  String download(String name) => p.join(cache, name);
}
