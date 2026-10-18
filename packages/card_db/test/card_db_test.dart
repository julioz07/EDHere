import 'package:card_db/card_db.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'helpers.dart';

void main() {
  late CardRepository repo;

  setUpAll(() async {
    setUpSqlite();
    repo = CardRepository.open(await buildFixtureDb())!;
  });

  List<String> names(String q) => repo.search(q, limit: 100).cards.map((c) => c.name).toList();

  group('importação', () {
    test('ignora art_series e conta as restantes', () {
      expect(repo.meta['card_count'], '${fixtureCards.length - 1}');
      expect(repo.findByName('Art Card'), isNull);
    });

    test('cartas de duas faces guardam as faces e as imagens de cada uma', () {
      final d = repo.findByName('delver of secrets')!;
      expect(d.faces.map((f) => f.name), ['Delver of Secrets', 'Insectile Aberration']);
      expect(d.hasFaceImages, isTrue);
      expect(ImageRef.allOf(d).map((r) => r.key), ['${d.printId}_0', '${d.printId}_1']);
      expect(d.frontType, 'Creature — Human Wizard');
      expect(d.manaCost, '{U}');
    });

    test('split junta custos e encontra-se por cada metade', () {
      expect(repo.findByName('Fire // Ice')!.manaCost, '{1}{R} // {1}{U}');
      expect(repo.findByName('ice')!.name, 'Fire // Ice');
    });

    test('nome completo exato ganha a uma face com o mesmo nome', () {
      expect(repo.findByName('Wheel of Fortune')!.name, 'Wheel of Fortune');
      expect(repo.findByName('Naktamun Lorespinner')!.name,
          'Naktamun Lorespinner // Wheel of Fortune');
    });

    test('nomes com acentos e ligaduras', () {
      expect(repo.findByName('Aether Vial')!.name, 'Æther Vial');
      expect(repo.findByName('atraxa, praetors’ voice'), isNotNull);
    });
  });

  group('pesquisa', () {
    test('palavra solta procura no nome', () {
      expect(names('bolt'), ['Lightning Bolt']);
    });

    test('tokens só aparecem quando pedidos', () {
      expect(names('elf'), isNot(contains('Elf Warrior')));
      expect(names('elf is:token'), ['Elf Warrior']);
    });

    test('tipo, texto e mv', () {
      expect(names('t:instant mv<=1'), ['Lightning Bolt']);
      expect(names('o:"add {g}"'), containsAll(['Llanowar Elves', 'Forest']));
      expect(names('t:legendary t:creature mv>=4'), ['Atraxa, Praetors\' Voice']);
    });

    test('cores e identidade', () {
      expect(names('c:r t:instant'), ['Fire // Ice', 'Lightning Bolt']);
      expect(names('c=r t:instant'), ['Lightning Bolt']);
      expect(names('c:c t:artifact'), containsAll(['Sol Ring', 'Mana Crypt']));
      expect(names('id:simic t:creature'),
          ['Delver of Secrets // Insectile Aberration', 'Llanowar Elves', 'Thrasios, Triton Hero',
            'Wilson, Refined Grizzly']);
      expect(names('c:m t:legendary'), ['Atraxa, Praetors\' Voice', 'Thrasios, Triton Hero', 'Tymna the Weaver']);
    });

    test('formato, banidas e raridade', () {
      expect(names('f:modern t:instant'), ['Lightning Bolt']);
      expect(names('banned:commander'), ['Mana Crypt']);
      expect(names('restricted:vintage'), ['Sol Ring']);
      expect(names('r:mythic'), ['Atraxa, Praetors\' Voice']);
    });

    test('negação, or e is:commander', () {
      expect(names('t:instant -c:r'), ['Counterspell']);
      expect(names('bolt or counterspell'), ['Counterspell', 'Lightning Bolt']);
      expect(names('is:commander'),
          ['Atraxa, Praetors\' Voice', 'Thrasios, Triton Hero', 'Tymna the Weaver', 'Wilson, Refined Grizzly']);
    });

    test('nome exato, palavra-chave e poder', () {
      expect(names('!"sol ring"'), ['Sol Ring']);
      expect(names('k:lifelink'), ['Atraxa, Praetors\' Voice', 'Tymna the Weaver']);
      expect(names('pow>=3'), ['Atraxa, Praetors\' Voice']);
    });

    test('filtro desconhecido é reportado', () {
      final r = repo.search('xyz:abc bolt');
      expect(r.errors, ['xyz:abc']);
      expect(r.cards.single.name, 'Lightning Bolt');
    });

    test('ordenação por mv', () {
      expect(names('t:instant order:mv').first, 'Lightning Bolt');
    });
  });

  group('listas em texto', () {
    const moxfield = '''
Commander
1 Atraxa, Praetors' Voice

Deck
1 Sol Ring
1x Lightning Bolt (2X2) 117 *F*
10 Forest
1 Fire/Ice
1 Carta Inventada

Sideboard
1 Counterspell
''';

    test('lê secções, quantidades, edições e cartas divididas', () {
      final parsed = parseDeckText(moxfield);
      final r = resolveDeckText(parsed, repo.findByName);
      expect(r.unresolved.map((l) => l.name), ['Carta Inventada']);
      final byName = {
        for (final e in r.entries) '${repo.get(e.oracleId)!.name}@${e.board.id}': e.qty,
      };
      expect(byName, {
        'Atraxa, Praetors\' Voice@command': 1,
        'Sol Ring@main': 1,
        'Lightning Bolt@main': 1,
        'Forest@main': 10,
        'Fire // Ice@main': 1,
        'Counterspell@side': 1,
      });
    });

    test('MTGO: último bloco curto é o comandante num formato de comando', () {
      const mtgo = '1 Sol Ring\n1 Forest\n\n1 Atraxa, Praetors\' Voice\n';
      final p = parseDeckText(mtgo, hasCommandZone: true);
      expect(p.last.board, Board.command);
      final p2 = parseDeckText(mtgo);
      expect(p2.last.board, Board.side);
    });

    test('partilha por QR: cabe num QR e volta igual', () {
      final r = resolveDeckText(parseDeckText(moxfield), repo.findByName);
      final deck = Deck(name: 'Atraxa', format: 'commander', entries: r.entries);
      final text = exportDeckText(deck, repo.getMany(deck.entries.map((e) => e.oracleId)));
      final code = SharedDeck('Atraxa', 'commander', text).encode();
      expect(code.length, lessThan(2900));
      final back = SharedDeck.tryDecode(code)!;
      expect(back.name, 'Atraxa');
      expect(back.text, text);
      expect(SharedDeck.tryDecode('lixo'), isNull);
    });

    test('categorias do Archidekt', () {
      final p = parseDeckText('1x Sol Ring (cmr) 472 [Ramp,Artifact] ^Have,#37d67a^');
      expect(p.single.name, 'Sol Ring');
      expect(p.single.category, 'Ramp');
    });

    test('exportar e voltar a importar dá o mesmo deck', () {
      final r = resolveDeckText(parseDeckText(moxfield), repo.findByName);
      final deck = Deck(name: 'x', format: 'commander', entries: r.entries);
      final cards = repo.getMany(deck.entries.map((e) => e.oracleId));
      for (final style in ExportStyle.values) {
        // No MTGO, comandante e sideboard partilham o último bloco e não se
        // distinguem; testa-se só o deck sem sideboard.
        final d = style == ExportStyle.mtgo
            ? deck.copyWith(entries: deck.entries.where((e) => e.board != Board.side).toList())
            : deck;
        final text = exportDeckText(d, cards, style: style);
        final again = resolveDeckText(
            parseDeckText(text, hasCommandZone: true), repo.findByName);
        expect(again.unresolved, isEmpty, reason: style.name);
        String sig(List<DeckEntry> es) =>
            (es.map((e) => '${e.oracleId}${e.board.id}${e.qty}').toList()..sort()).join();
        expect(sig(again.entries), sig(d.entries), reason: text);
      }
    });
  });

  group('validação', () {
    List<String> issues(Deck d) {
      final f = GameFormat.byId(d.format);
      final cards = repo.getMany(d.entries.map((e) => e.oracleId));
      return validateDeck(d, f, cards, repo.legalityIn(f.legalityKey ?? '', cards.keys))
          .map((i) => i.message)
          .toList();
    }

    String id(String name) => repo.findByName(name)!.oracleId;

    Deck commanderDeck(List<(String, int)> main, List<String> cmds) {
      var d = const Deck(name: 't', format: 'commander');
      for (final c in cmds) {
        d = d.add(id(c), board: Board.command);
      }
      for (final (n, q) in main) {
        d = d.add(id(n), qty: q);
      }
      return d;
    }

    test('deck de Commander válido com 100 cartas', () {
      final d = commanderDeck([('Sol Ring', 1), ('Forest', 49), ('Island', 49)],
          ['Atraxa, Praetors\' Voice']);
      expect(d.playableCount, 100);
      expect(issues(d), isEmpty);
    });

    test('tamanho, singleton, banidas e identidade de cor', () {
      final d = commanderDeck(
          [('Sol Ring', 2), ('Mana Crypt', 1), ('Lightning Bolt', 1), ('Forest', 10)],
          ['Thrasios, Triton Hero']);
      final msgs = issues(d);
      expect(msgs, contains(startsWith('O deck tem 15 cartas')));
      expect(msgs, contains('Sol Ring: 2 cópias num formato singleton.'));
      expect(msgs, contains('Mana Crypt está banida em Commander.'));
      expect(msgs, contains('Lightning Bolt está fora da identidade de cor do comandante.'));
    });

    test('exceções de cópias: Relentless Rats e Seven Dwarves', () {
      final ok = commanderDeck([('Relentless Rats', 30), ('Forest', 69)], ['Atraxa, Praetors\' Voice']);
      expect(issues(ok).where((m) => m.contains('Rats')), isEmpty);
      final dw = commanderDeck([('Seven Dwarves', 8)], ['Atraxa, Praetors\' Voice']);
      expect(issues(dw), contains('Seven Dwarves: 8 cópias; o máximo é 7.'));
    });

    test('parceiros e backgrounds', () {
      expect(issues(commanderDeck([('Forest', 98)], ['Thrasios, Triton Hero', 'Tymna the Weaver'])),
          isEmpty);
      expect(issues(commanderDeck([('Forest', 98)], ['Wilson, Refined Grizzly', 'Raised by Giants'])),
          isEmpty);
      final bad = issues(commanderDeck([('Forest', 98)], ['Atraxa, Praetors\' Voice', 'Tymna the Weaver']));
      expect(bad, contains(contains('não podem ser comandantes juntos')));
    });

    test('sem comandante e comandante inválido', () {
      expect(issues(commanderDeck([('Forest', 100)], [])), contains('Falta escolher o comandante.'));
      expect(issues(commanderDeck([('Forest', 99)], ['Sol Ring'])),
          contains('Sol Ring não pode ser comandante.'));
    });

    test('Modern: mínimo 60, 4 cópias e legalidade', () {
      var d = const Deck(name: 'm', format: 'modern');
      d = d.add(id('Lightning Bolt'), qty: 5).add(id('Counterspell')).add(id('Forest'), qty: 20);
      final msgs = issues(d);
      expect(msgs, contains('O deck tem 26 cartas; Modern pede pelo menos 60.'));
      expect(msgs, contains('Lightning Bolt: 5 cópias; o máximo é 4.'));
      expect(msgs, contains('Counterspell não é legal em Modern.'));
    });

    test('formato livre não valida', () {
      expect(issues(const Deck(name: 'f', format: 'free')), isEmpty);
    });
  });

  group('estatísticas', () {
    test('curva, terrenos, pips e fontes', () {
      final d = const Deck(name: 's', format: 'commander')
          .add(repo.findByName('Atraxa, Praetors\' Voice')!.oracleId, board: Board.command)
          .add(repo.findByName('Lightning Bolt')!.oracleId)
          .add(repo.findByName('Counterspell')!.oracleId)
          .add(repo.findByName('Forest')!.oracleId, qty: 10);
      final s = DeckStats.of(d, repo.getMany(d.entries.map((e) => e.oracleId)));
      expect(s.lands, 10);
      expect(s.nonLands, 3);
      expect(s.curve[1], 1);
      expect(s.curve[2], 1);
      expect(s.curve[4], 1);
      expect(s.pips['U'], 3);
      expect(s.sources['G'], 10);
      expect(s.types['Instant'], 2);
    });
  });
}
