import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../l10n/l10n.dart';

/// O Scryfall pede um User-Agent próprio e um Accept explícito.
const scryfallHeaders = {
  'User-Agent': 'EDHere/0.1 (app offline sem fins lucrativos)',
  'Accept': 'application/json;q=0.9,*/*;q=0.8',
};

/// Um ficheiro bulk publicado pelo Scryfall.
class BulkFile {
  const BulkFile({
    required this.type,
    required this.updatedAt,
    required this.url,
    required this.compressedSize,
  });

  final String type;
  final String updatedAt;
  final String url;
  final int compressedSize;
}

HttpClient newHttpClient() => HttpClient()
  ..connectionTimeout = const Duration(seconds: 15)
  ..idleTimeout = const Duration(seconds: 15);

/// Lista os ficheiros bulk (`GET https://api.scryfall.com/bulk-data`).
Future<Map<String, BulkFile>> fetchBulkIndex() async {
  final client = newHttpClient();
  try {
    final req = await client.getUrl(Uri.parse('https://api.scryfall.com/bulk-data'));
    scryfallHeaders.forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw HttpException(tr('Scryfall respondeu {statusCode}', {'statusCode': res.statusCode}));
    }
    final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    return {
      for (final d in (body['data'] as List).cast<Map<String, dynamic>>())
        d['type'] as String: BulkFile(
          type: d['type'] as String,
          updatedAt: d['updated_at'] as String,
          url: (d['jsonl_download_uri'] ?? d['download_uri']) as String,
          compressedSize: (d['compressed_size'] ?? d['size'] ?? 0) as int,
        ),
    };
  } finally {
    client.close();
  }
}

/// Descarrega [url] para [path], chamando [onProgress] com os bytes recebidos.
Future<void> downloadFile(
  String url,
  String path, {
  void Function(int received, int total)? onProgress,
  bool Function()? cancelled,
}) async {
  final client = newHttpClient();
  final tmp = File('$path.part');
  try {
    final req = await client.getUrl(Uri.parse(url));
    scryfallHeaders.forEach(req.headers.set);
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException(tr('HTTP {statusCode} em {url}', {'statusCode': res.statusCode, 'url': url}));
    }
    final total = res.contentLength;
    final sink = tmp.openWrite();
    var received = 0;
    try {
      await for (final chunk in res) {
        if (cancelled?.call() ?? false) throw const DownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
    await tmp.rename(path);
  } catch (_) {
    if (tmp.existsSync()) tmp.deleteSync();
    rethrow;
  } finally {
    client.close(force: true);
  }
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => tr('Cancelado');
}
