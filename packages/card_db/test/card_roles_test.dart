import 'package:card_db/card_db.dart';
import 'package:test/test.dart';

void main() {
  Set<CardRole> roles(String text, {bool land = false, bool mana = false, bool permanent = true}) =>
      CardRoles.ofText(text.toLowerCase(), isLand: land, producesMana: mana, permanent: permanent);

  test('rampa', () {
    expect(roles('{T}: Add {C}{C}.', mana: true), {CardRole.ramp}); // Sol Ring
    expect(
        roles('Search your library for up to two basic land cards, reveal those cards, put one onto the '
            'battlefield tapped and the other into your hand, then shuffle.',
            permanent: false),
        {CardRole.ramp}); // Cultivate
    expect(roles('You may play an additional land on each of your turns.'), {CardRole.ramp}); // Exploration
    expect(roles('When this creature enters, create a Treasure token.'), {CardRole.ramp});
    // um ritual não é rampa; um terreno também não
    expect(roles('Add {B}{B}{B}.', mana: true, permanent: false), isEmpty);
    expect(roles('{T}: Add {G}.', land: true, mana: true), isEmpty);
  });

  test('compra', () {
    expect(roles('When this creature enters, draw a card.'), {CardRole.draw}); // Elvish Visionary
    expect(roles('Whenever an opponent casts a spell, you may draw a card unless that player pays {1}.'),
        {CardRole.draw}); // Rhystic Study
    expect(roles('Draw cards equal to the greatest power among creatures you control.'), {CardRole.draw});
  });

  test('remoção e limpezas de mesa', () {
    expect(roles('Lightning Bolt deals 3 damage to any target.', permanent: false), {CardRole.removal});
    expect(roles('Exile target creature. Its controller gains life equal to its power.', permanent: false),
        {CardRole.removal}); // Swords to Plowshares
    expect(roles('Counter target spell.', permanent: false), {CardRole.removal});
    expect(roles("Return target nonland permanent to its owner's hand.", permanent: false), {CardRole.removal});
    expect(roles('Destroy all creatures. They can\'t be regenerated.', permanent: false), {CardRole.wipe});
    expect(roles('Exile all nonland permanents.', permanent: false), {CardRole.wipe});
    expect(roles('This spell deals 2 damage to each creature.', permanent: false), {CardRole.wipe});
    // destruir terrenos é outra conversa (o bracket), não uma limpeza de mesa
    expect(roles('Destroy all lands.', permanent: false), isEmpty);
    // exilar do cemitério não é remoção
    expect(roles('Exile target card from a graveyard.', permanent: false), isEmpty);
  });

  test('tutores', () {
    expect(roles('Search your library for a card, put that card into your hand, then shuffle. You lose 2 life.',
        permanent: false), {CardRole.tutor}); // Demonic Tutor
    expect(roles('Search your library for a creature card, reveal it, then shuffle and put that card on top.',
        permanent: false), {CardRole.tutor}); // Worldly Tutor
    expect(roles('Search your library for a basic land card, put it onto the battlefield tapped, then shuffle.',
        permanent: false), {CardRole.ramp}); // Rampant Growth
    expect(roles('Search your library for a nonland card, put it into your hand.', permanent: false),
        {CardRole.tutor});
    expect(roles('{G}{G}, {T}: Search your library for a card named Elvish Clancaller, put it onto the battlefield.'),
        isEmpty);
  });
}
