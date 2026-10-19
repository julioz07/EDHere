import 'package:card_db/card_db.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'helpers.dart';

/// Cartas noutra língua: o texto impresso e a impressão com imagens nessa
/// língua, por cima da base inglesa.
void main() {
  late String path;

  setUpAll(() async {
    setUpSqlite();
    path = await buildFixtureDb();
    final imp = LocalizedImporter(path)..begin('it');
    imp.add({
      'id': 'it-bolt',
      'oracle_id': 'oid-Lightning Bolt',
      'name': 'Lightning Bolt',
      'printed_name': 'Fulmine',
      'printed_type_line': 'Istantaneo',
      'printed_text': 'Fulmine infligge 3 danni a un qualsiasi bersaglio.',
      'set': 'm10',
      'collector_number': '146',
      'image_uris': {'small': 'https://img/small/fulmine.jpg', 'normal': 'https://img/normal/fulmine.jpg'},
    });
    imp.add({
      'id': 'it-delver',
      'oracle_id': 'oid-Delver of Secrets // Insectile Aberration',
      'name': 'Delver of Secrets // Insectile Aberration',
      'card_faces': [
        {
          'name': 'Delver of Secrets',
          'printed_name': 'Cercatore di Segreti',
          'printed_type_line': 'Creatura — Mago Umano',
          'printed_text': 'All\'inizio del tuo mantenimento…',
          'image_uris': {'small': 's0', 'normal': 'n0'},
        },
        {
          'name': 'Insectile Aberration',
          'printed_name': 'Aberrazione Insettoide',
          'image_uris': {'small': 's1', 'normal': 'n1'},
        },
      ],
    });
    imp.add({
      'id': 'it-ring',
      'oracle_id': 'oid-Sol Ring',
      'printed_name': 'Anello del Sole',
      'image_status': 'placeholder',
      'image_uris': {'small': 'placeholder', 'normal': 'placeholder'},
    });
    imp.finish();
  });

  test('sem imagem na língua: o nome traduzido, a imagem inglesa', () {
    final repo = CardRepository.open(path)!;
    final ring = repo.findByName('Sol Ring')!;
    expect(ring.displayName, 'Anello del Sole');
    expect(ring.printId, 'print-Sol Ring');
    expect(ring.imgSmall, 'https://img/small/Sol Ring.jpg');
    repo.close();
  });

  test('o nome, o tipo e o texto vêm da língua; o nome Oracle fica', () {
    final repo = CardRepository.open(path)!;
    expect(repo.cardLang, 'it');
    final bolt = repo.findByName('Lightning Bolt')!;
    expect(bolt.name, 'Lightning Bolt');
    expect(bolt.displayName, 'Fulmine');
    expect(bolt.displayFrontName, 'Fulmine');
    expect(bolt.displayTypeOf(), 'Istantaneo');
    expect(bolt.displayTextOf(), startsWith('Fulmine infligge'));
    expect(bolt.oracleText, startsWith('Lightning Bolt deals'));
    // A impressão por defeito passa a ser a italiana (as imagens também).
    expect(bolt.printId, 'it-bolt');
    expect(bolt.basePrintId, 'print-Lightning Bolt');
    expect(bolt.imgSmall, 'https://img/small/fulmine.jpg');
    expect(ImageRef.allOf(bolt).single.key, 'it-bolt');
    repo.close();
  });

  test('pesquisa e procura pelo nome na língua', () {
    final repo = CardRepository.open(path)!;
    expect(repo.search('fulmine').cards.map((c) => c.name), ['Lightning Bolt']);
    expect(repo.search('!"Fulmine"').cards.map((c) => c.name), ['Lightning Bolt']);
    expect(repo.search('bolt').cards.map((c) => c.name), ['Lightning Bolt']);
    expect(repo.findByName('fulmine')?.name, 'Lightning Bolt');
    expect(repo.suggest('fulm').map((c) => c.name), ['Lightning Bolt']);
    // Uma carta sem tradução continua igual.
    final rats = repo.findByName('Relentless Rats')!;
    expect(rats.displayName, 'Relentless Rats');
    expect(rats.printId, 'print-Relentless Rats');
    repo.close();
  });

  test('a ordem segue o nome traduzido; o nome igual vem primeiro', () {
    final repo = CardRepository.open(path)!;
    final names = repo.search('e order:name', limit: 200).cards.map((c) => normalizeName(c.displayName)).toList();
    expect(names, [...names]..sort());
    expect(names, contains('anello del sole'));
    // Sem order:, o nome que começa pelo texto vem antes dos que só o contêm.
    final bolt = repo.search('bolt').cards.map((c) => c.name).toList();
    expect(bolt.first, 'Lightning Bolt');
    repo.close();
  });

  test('cartas de duas faces: nomes e imagens de cada face', () {
    final repo = CardRepository.open(path)!;
    final d = repo.findByName('Delver of Secrets')!;
    expect(d.displayNameOf(0), 'Cercatore di Segreti');
    expect(d.displayNameOf(1), 'Aberrazione Insettoide');
    expect(d.displayFrontName, 'Cercatore di Segreti');
    expect(d.faces[1].imgNormal, 'n1');
    expect(ImageRef.allOf(d).map((r) => r.key), ['it-delver_0', 'it-delver_1']);
    repo.close();
  });

  test('de várias impressões fica a que tem o texto traduzido', () async {
    final p = await buildFixtureDb();
    final imp = LocalizedImporter(p)..begin('es');
    imp.add({'id': 'es-1', 'oracle_id': 'oid-Lightning Bolt', 'printed_name': 'Relámpago', 'set': 'tle'});
    imp.add({
      'id': 'es-2',
      'oracle_id': 'oid-Lightning Bolt',
      'printed_name': 'Relámpago',
      'printed_type_line': 'Instantáneo',
      'printed_text': 'El Relámpago hace 3 puntos de daño a cualquier objetivo.',
      'set': 'm10',
    });
    imp.add({'id': 'es-3', 'oracle_id': 'oid-Lightning Bolt', 'printed_name': 'Relámpago', 'set': 'sld'});
    imp.finish();
    final repo = CardRepository.open(p)!;
    final bolt = repo.findByName('relampago')!;
    expect(bolt.displayTypeOf(), 'Instantáneo');
    expect(bolt.printId, 'es-2');
    expect(imp.imported, 1);
    repo.close();
  });

  test('voltar ao inglês apaga a língua', () async {
    final p = await buildFixtureDb();
    final imp = LocalizedImporter(p)..begin('es');
    imp.add({'id': 'es-bolt', 'oracle_id': 'oid-Lightning Bolt', 'printed_name': 'Rayo'});
    imp.finish();
    expect(CardRepository.open(p)!.findByName('rayo')?.name, 'Lightning Bolt');
    LocalizedImporter.clear(p);
    final repo = CardRepository.open(p)!;
    expect(repo.cardLang, 'en');
    expect(repo.findByName('Lightning Bolt')!.displayName, 'Lightning Bolt');
    expect(repo.findByName('rayo'), isNull);
    // Sem impressão na língua (só o nome), a imagem continua a inglesa.
    repo.close();
  });
}
