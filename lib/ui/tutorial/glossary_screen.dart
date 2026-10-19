import 'package:flutter/material.dart';

import '../widgets/responsive.dart';
import 'tutorial_screen.dart';

/// Termos do Magic e do Commander, com o nome em inglês (o das cartas).
const glossary = <(String, String, String)>[
  (
    'Artefacto',
    'Artifact',
    'Carta que fica em campo com um efeito. As incolores entram em qualquer baralho.'
  ),
  (
    'Aura',
    'Aura',
    'Encantamento que se lança sobre uma carta e fica anexado a ela. Se a carta sair do campo, '
        'a aura vai para o cemitério.'
  ),
  (
    'Background',
    'Background',
    'Encantamento lendário que pode ser o segundo comandante de uma lenda com '
        '"Choose a Background".'
  ),
  (
    'Batalha',
    'Battle',
    'Permanente que entra do lado de um adversário com contadores de defesa. Derrotada, vira-se e '
        'dá uma recompensa a quem a atacou.'
  ),
  (
    'Bloquear',
    'Block',
    'Pôr uma criatura desvirada à frente de uma criatura que te ataca. As duas dão dano uma à '
        'outra.'
  ),
  (
    'Bracket',
    'Bracket',
    'Nível de força do baralho, de 1 (Exhibition) a 5 (cEDH), para combinar jogos '
        'equilibrados.'
  ),
  ('Cemitério', 'Graveyard', 'Onde vão as cartas usadas, destruídas ou descartadas.'),
  (
    'Comandante',
    'Commander',
    'A criatura lendária que lidera o baralho. Começa na zona de comando e define as '
        'cores permitidas.'
  ),
  (
    'Contador +1/+1',
    '+1/+1 counter',
    'Marcador que dá +1 de poder e +1 de resistência a uma criatura, para '
        'sempre.'
  ),
  ('Criatura', 'Creature', 'Carta que fica em campo, ataca e bloqueia. Tem poder/resistência.'),
  (
    'Custo de mana',
    'Mana cost',
    'O que pagas para jogar a carta. {1}{G} = uma mana verde e uma de qualquer cor.'
  ),
  (
    'Dano de comandante',
    'Commander damage',
    'Dano de combate dado por um comandante. Com 21 do mesmo comandante, '
        'perdes o jogo.'
  ),
  ('Deathtouch', 'Deathtouch', 'Qualquer dano desta criatura a outra criatura mata-a.'),
  (
    'Enjoo de invocação',
    'Summoning sickness',
    'Uma criatura que entrou neste turno não pode atacar nem usar '
        'habilidades com {T}.'
  ),
  ('Encantamento', 'Enchantment', 'Carta que fica em campo com um efeito duradouro.'),
  (
    'Equipamento',
    'Equipment',
    'Artefacto que se anexa a uma criatura tua pagando o custo de Equip (só no teu turno). Se a '
        'criatura morrer, o equipamento fica no campo.'
  ),
  ('Exílio', 'Exile', 'Cartas removidas do jogo. O comandante exilado pode voltar à zona de comando.'),
  ('Feitiço', 'Sorcery', 'Faz o efeito e vai para o cemitério. Só no teu turno, na fase principal.'),
  ('Flash', 'Flash', 'Pode lançar-se a qualquer momento, como um instantâneo.'),
  ('Flying', 'Flying', 'Voa: só pode ser bloqueada por criaturas com Flying ou Reach.'),
  (
    'Game Changer',
    'Game Changer',
    'Carta da lista oficial de cartas muito fortes, que contam para o bracket.'
  ),
  ('Grimório', 'Library', 'O teu baralho, virado para baixo. Perdes se tiveres de comprar com ele vazio.'),
  ('Haste', 'Haste', 'Pressa: pode atacar e virar-se no turno em que entra.'),
  (
    'Identidade de cor',
    'Color identity',
    'As cores de todos os símbolos de mana no custo e no texto do comandante. '
        'Todas as cartas do baralho têm de caber nela.'
  ),
  (
    'Instantâneo',
    'Instant',
    'Faz o efeito e vai para o cemitério. Pode lançar-se a qualquer momento, até no turno '
        'dos outros.'
  ),
  (
    'Lealdade',
    'Loyalty',
    'A "vida" de um planeswalker. As habilidades +1 sobem-na, as −N gastam-na; com 0 vai para o '
        'cemitério.'
  ),
  (
    'Lendário',
    'Legendary',
    'Só podes ter uma carta lendária com o mesmo nome no campo. Se entrar outra, escolhes uma.'
  ),
  ('Lifelink', 'Lifelink', 'O dano que esta criatura dá também te dá vida.'),
  (
    'Mulligan',
    'Mulligan',
    'Baralhar a mão inicial e comprar outra. No Commander a vários, o primeiro é grátis.'
  ),
  ('Partner', 'Partner', 'Duas lendas com Partner podem ser comandantes juntas.'),
  (
    'Pilha',
    'Stack',
    'Onde esperam os feitiços e habilidades. Resolve-se de cima para baixo: o último é o '
        'primeiro.'
  ),
  (
    'Planeswalker',
    'Planeswalker',
    'Aliado com lealdade, que usa uma habilidade por turno e pode ser atacado.'
  ),
  ('Regra zero', 'Rule 0', 'Combinar antes do jogo o tipo de jogo e qualquer mudança às regras.'),
  (
    'Saga',
    'Saga',
    'Encantamento com capítulos: ganha um contador por turno e faz o capítulo seguinte. Depois do '
        'último vai para o cemitério.'
  ),
  (
    'Singleton',
    'Singleton',
    'Uma cópia de cada carta, exceto terrenos básicos. É a regra do baralho de Commander.'
  ),
  (
    'Taxa de comandante',
    'Commander tax',
    '{2} a mais por cada vez que já lançaste o comandante da zona de '
        'comando.'
  ),
  ('Terreno', 'Land', 'Dá mana. Um por turno, de graça.'),
  (
    'Token',
    'Token',
    'Uma "carta" criada por um efeito (por exemplo, um Goblin 1/1). Desaparece se sair do campo.'
  ),
  ('Trample', 'Trample', 'O dano que sobra depois de matar o bloqueador passa para o jogador.'),
  (
    'Tripular',
    'Crew',
    'Virar criaturas tuas com poder total N ou mais para um veículo ser uma criatura até ao fim do turno.'
  ),
  (
    'Ultimate',
    'Ultimate',
    'A habilidade de lealdade mais cara de um planeswalker, normalmente a mais forte.'
  ),
  ('Veículo', 'Vehicle', 'Artefacto que só ataca e bloqueia quando é tripulado (Crew).'),
  ('Vigilance', 'Vigilance', 'Ataca sem se virar.'),
  ('Virar (tap)', 'Tap', 'Rodar a carta de lado para usar: dar mana, atacar ou usar uma habilidade {T}.'),
  (
    'Zona de comando',
    'Command zone',
    'Onde o comandante começa e para onde pode voltar. Lança-se de lá como da '
        'mão.'
  ),
];

/// O glossário, com pesquisa.
class GlossaryScreen extends StatefulWidget {
  const GlossaryScreen({super.key});

  @override
  State<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends State<GlossaryScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _q.toLowerCase();
    final shown =
        glossary.where((g) => q.isEmpty || '${g.$1} ${g.$2} ${g.$3}'.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Glossário')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Procurar um termo'),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          for (final (pt, en, text) in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: pt, style: theme.textTheme.titleMedium),
                  if (en != pt)
                    TextSpan(
                        text: '  ·  $en',
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ])),
                const SizedBox(height: 2),
                RichLesson(text, style: theme.textTheme.bodyMedium),
              ]),
            ),
          if (shown.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Nenhum termo encontrado.')),
        ]),
      ),
    );
  }
}
