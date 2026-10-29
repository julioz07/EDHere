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
}
