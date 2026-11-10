import 'package:edhoff/bot/forge_table.dart';
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

  test('a vida que fica negativa também se traduz', () {
    expect(logLine('Life: Bot 2 10 > -3'), isNot(contains('Life:')));
  });
}
