import 'package:card_db/card_db.dart';
import 'package:test/test.dart';

void main() {
  test('lê os tokens criados pelo texto de regras', () {
    expect(
        tokenHintsIn(
            '{T}: Create X 1/1 red Goblin creature tokens, where X is the number of Goblins you control.'),
        [const TokenHint('Goblin', pt: '1/1')]);
    expect(tokenHintsIn('When this enters, create a Treasure token.'), [const TokenHint('Treasure')]);
    expect(tokenHintsIn('Create two 2/2 black Zombie Knight creature tokens with menace.'),
        [const TokenHint('Zombie Knight', pt: '2/2')]);
    expect(
        tokenHintsIn('Create a 1/1 colorless Thopter artifact creature token with flying and a Clue token.'),
        [const TokenHint('Thopter', pt: '1/1')]);
    expect(tokenHintsIn("Create a token that's a copy of target creature."), isEmpty);
    expect(tokenHintsIn('Draw a card.'), isEmpty);
  });

  test('o CSV da coleção guarda a coleção e o número de cada carta', () {
    const csv = 'Name,Set code,Set name,Collector number,Quantity\n'
        '"Krenko, Mob Boss",DDT,Duel Decks,52,1\n'
        'Sol Ring,C21,Commander 2021,263,3\n';
    final lines = parseCollectionText(csv);
    expect(lines.map((l) => (l.name, l.setCode, l.collectorNumber, l.qty)), [
      ('Krenko, Mob Boss', 'ddt', '52', 1),
      ('Sol Ring', 'c21', '263', 3),
    ]);
  });
}
