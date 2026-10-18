@Tags(['bulk'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Importa o ficheiro real do Scryfall indicado em `EDHERE_ORACLE`
/// (oracle-cards-*.jsonl.gz). Sem a variável, o teste é ignorado.
void main() {
  final src = Platform.environment['EDHERE_ORACLE'];

  test('importa o Oracle Cards real e pesquisa depressa', () async {
    setUpSqlite();
    final dir = Directory.systemTemp.createTempSync('bulk');
    final path = '${dir.path}/cards.sqlite';
    final sw = Stopwatch()..start();
    final imp = CardImporter(path)..open();
    await imp.importLines(File(src!)
        .openRead()
        .transform(gzip.decoder)
        .transform(utf8.decoder)
        .transform(const LineSplitter()));
    imp.finish({'bulk_updated_at': 'real'});
    final importMs = sw.elapsedMilliseconds;
    final size = File(path).lengthSync();

    final repo = CardRepository.open(path)!;
    sw.reset();
    final queries = [
      'sol ring', 'id:esper t:creature mv<=3', 'o:"draw a card" f:commander',
      'is:commander c:m', 't:dragon pow>=5', 'k:flying r:mythic order:edhrec',
    ];
    final counts = {for (final q in queries) q: repo.search(q).total};
    final searchMs = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('import ${importMs}ms, ${imp.imported} cartas, ${size ~/ 1024 ~/ 1024} MB; '
        '${queries.length} pesquisas em ${searchMs}ms; $counts');

    expect(imp.imported, greaterThan(30000));
    expect(repo.findByName('Sol Ring'), isNotNull);
    expect(repo.findByName("Atraxa, Praetors' Voice")!.canBeCommander, isTrue);
    expect(counts.values.every((n) => n > 0), isTrue);
    expect(repo.search('is:token t:treasure').total, greaterThan(0));
  }, skip: src == null ? 'EDHERE_ORACLE não definido' : false,
      timeout: const Timeout(Duration(minutes: 5)));
}
