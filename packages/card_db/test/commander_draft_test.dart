import 'package:card_db/card_db.dart';
import 'package:test/test.dart';

Card _legend(String name, int colors, {String text = ''}) => Card(
      oracleId: name,
      name: name,
      typeLine: 'Legendary Creature — Human',
      oracleText: text,
      colorMask: colors,
      identityMask: colors,
    );

Card _spell(String name, int colors) =>
    Card(oracleId: name, name: name, typeLine: 'Creature — Elf', colorMask: colors, identityMask: colors);

List<DeckIssue> _check(List<Card> commanders, List<Card> main, {int fill = 0}) {
  const forest = Card(oracleId: 'forest', name: 'Forest', typeLine: 'Basic Land — Forest');
  final cards = {for (final c in [...commanders, ...main, forest]) c.oracleId: c};
  final deck = Deck(name: 't', format: 'commanderdraft', entries: [
    for (final c in commanders) DeckEntry(oracleId: c.oracleId, qty: 1, board: Board.command),
    for (final c in main) DeckEntry(oracleId: c.oracleId, qty: 2, board: Board.main),
    if (fill > 0) DeckEntry(oracleId: 'forest', qty: fill, board: Board.main),
  ]);
  return validateDeck(deck, GameFormat.commanderDraft, cards, const {})
      .where((i) => i.level == IssueLevel.error)
      .toList();
}

void main() {
  test('formato: 60 cartas, vida 40, sem singleton e sem banidas', () {
    final f = GameFormat.byId('commanderdraft');
    expect(f, GameFormat.commanderDraft);
    expect(f.startingLife, 40);
    expect(f.minDeck, 60);
    expect(f.isSingleton, isFalse);
    expect(f.legalityKey, isNull);
    expect(f.isLimited, isTrue);
  });

  test('deck de 60 com cópias repetidas é válido', () {
    final cmd = _legend('Elf King', ManaColors.g);
    final issues = _check([cmd], [_spell('Elf', ManaColors.g)], fill: 57);
    expect(issues, isEmpty);
  });

  test('menos de 60 e fora da identidade dão erro', () {
    final cmd = _legend('Elf King', ManaColors.g);
    final issues = _check([cmd], [_spell('Goblin', ManaColors.r)], fill: 10);
    expect(issues.map((i) => i.message).join('\n'), allOf(contains('60'), contains('identidade')));
  });

  test('duas lendas monocolores podem ser comandantes juntas', () {
    final a = _legend('Elf King', ManaColors.g);
    final b = _legend('Goblin King', ManaColors.r);
    expect(_check([a, b], [_spell('Elf', ManaColors.g), _spell('Goblin', ManaColors.r)], fill: 54), isEmpty);
  });

  test('uma lenda bicolor não junta com outra sem Partner', () {
    final a = _legend('Gruul Boss', ManaColors.g | ManaColors.r);
    final b = _legend('Bird', ManaColors.w);
    expect(_check([a, b], const [], fill: 58).map((i) => i.message).join(), contains('não podem ser comandantes'));
  });

  test('The Prismatic Piper deixa mais uma cor à escolha', () {
    final piper = _legend('The Prismatic Piper', 0, text: 'Partner');
    final elf = _legend('Elf King', ManaColors.g, text: 'Partner');
    expect(_check([piper, elf], [_spell('Bird', ManaColors.w)], fill: 56), isEmpty);
    // Duas cores a mais já não.
    final issues = _check([piper, elf], [_spell('Bird', ManaColors.w), _spell('Bat', ManaColors.b)], fill: 54);
    expect(issues.map((i) => i.message).join(), contains('identidade'));
  });
}
