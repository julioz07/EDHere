import 'package:edhoff/bot/forge_table.dart';
import 'package:edhoff/l10n/l10n.dart';
import 'package:edhoff/ui/bot/bot_table_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o possessivo inglês do Forge fica em português', () {
    expect(forgeText("Goblin Lackey\nEscolhe a carta de você's mão"), 'Goblin Lackey\nEscolhe a carta da tua mão');
    expect(forgeText("Escolhe a carta de Bot 1's cemitério"), 'Escolhe a carta do cemitério de Bot 1');
  });

  test('a descrição da carta a pagar fica só com o nome', () {
    expect(forgeText('Goblin Lackey - Criatura 1 / 1\nPaga: {R}'), 'Goblin Lackey\nPaga: {R}');
    expect(forgeText('Sol Ring está na pilha.'), 'Sol Ring está na pilha.');
  });

  test('sem ids nem a causa dos gatilhos entre parênteses retos', () {
    expect(forgeStrip('Sol Ring (12) - Añade {C}{C}. [Cambia de zona: Sol Ring (12)]'), 'Sol Ring - Añade {C}{C}.');
    expect(forgeStrip('Bloodthirsty Blade - draw a card [Player: Jose, Lost Amount: 2]'),
        'Bloodthirsty Blade - draw a card');
    // parênteses retos sem "chave: valor" ficam (podem ser texto da carta)
    expect(forgeStrip('Choose [one]'), 'Choose [one]');
  });

  test('sem os filtros internos do Forge', () {
    expect(forgeStrip('returns up to one Creature.YouCtrl or Land.YouCtrl card'),
        'returns up to one Creature or Land card');
    expect(forgeStrip('target Instant.YouCtrl+cmcLE3 or Sorcery.YouCtrl+cmcLE3'), 'target Instant or Sorcery');
    expect(forgeStrip('Mr. House, President and CEO'), 'Mr. House, President and CEO');
  });

  test('a vida que fica negativa também se traduz', () {
    expect(logLine('Life: Bot 2 10 > -3'), isNot(contains('Life:')));
  });

  test('o que resolveu, marcado com a carta, fica "Carta resolveu" fora do inglês', () {
    const line = '\u0001Iron Mastiff\u0001Whenever Iron Mastiff attacks, roll a d20.';
    L10n.use(AppLang.pt);
    expect(logLine(line), 'Iron Mastiff resolveu');
    L10n.use(AppLang.en);
    expect(logLine(line), 'Whenever Iron Mastiff attacks, roll a d20.');
    L10n.use(AppLang.pt);
  });

  test('o mill, que o Forge escreve em inglês', () {
    expect(logLine('Maria milled Sol Ring (12), Island (3) and Forest (4)'),
        'Maria fez mill de Sol Ring, Island, Forest');
  });
}
