import 'package:mesa_core/mesa_core.dart';

import 'chapters_commander.dart';
import 'tutorial.dart';
import 'tutorial_runner.dart';

const solRing = 'Sol Ring';
const anthem = 'Glorious Anthem';
const cultivate = 'Cultivate';

List<String> _many(String name, int n) => List.filled(n, name);

/// "Nunca joguei": o Magic do zero, antes dos capítulos de Commander.
final basicsChapters = <Chapter>[
  const Chapter(
    id: 'mtg-cards',
    title: 'O que é o Magic e as cartas',
    summary: 'O objetivo do jogo, como ler uma carta e os tipos de carta',
    minutes: 4,
    pages: [
      TPage(
        'O objetivo',
        'No **Magic: The Gathering** cada jogador tem um baralho e começa com uma quantidade de **vida**. '
            'Ganha quem deixar os adversários sem vida (há outras formas, que vês mais à frente).\n\n'
            'Jogas **terrenos** para ter **mana**, e com a mana lanças **criaturas** e **feitiços** para atacar, '
            'defender e atrapalhar os outros.',
      ),
      TPage(
        'Como ler uma carta',
        '• **Nome**, em cima à esquerda.\n'
            '• **Custo de mana**, em cima à direita: o que pagas para a jogar.\n'
            '• **Linha de tipo**, a meio: diz o que a carta é (Creature — Bear, Instant…).\n'
            '• **Texto**: o que a carta faz. O texto em itálico é só história.\n'
            '• **Poder/Resistência** (só criaturas), em baixo à direita: 2/2 quer dizer que dá 2 de dano e '
            'morre com 2 de dano.',
        cards: [TCard(bears, caption: 'Custa {1}{G}, é uma 2/2')],
      ),
      TPage(
        'Os tipos de carta',
        '• **Land** (terreno): dá mana. Joga-se de graça, um por turno.\n'
            '• **Creature** (criatura): fica em campo, ataca e bloqueia.\n'
            '• **Instant** (instantâneo): faz o efeito e vai para o cemitério. Pode lançar-se a qualquer momento.\n'
            '• **Sorcery** (feitiço): como o instantâneo, mas só no teu turno, na fase principal.\n'
            '• **Artifact** e **Enchantment**: ficam em campo com um efeito.\n'
            '• **Planeswalker**: um aliado poderoso com lealdade, que usa uma habilidade por turno.',
        cards: [
          TCard(forest, caption: 'Land'),
          TCard(bears, caption: 'Creature'),
          TCard(giantGrowth, caption: 'Instant'),
          TCard(cultivate, caption: 'Sorcery'),
          TCard(solRing, caption: 'Artifact'),
          TCard(anthem, caption: 'Enchantment'),
        ],
      ),
      TPage(
        'As zonas',
        'As cartas andam por vários sítios, as **zonas**:\n\n'
            '• **Grimório** (biblioteca): o teu baralho, virado para baixo.\n'
            '• **Mão**: as cartas que compraste e ainda não jogaste.\n'
            '• **Campo de batalha**: o que está em jogo.\n'
            '• **Cemitério**: cartas usadas ou destruídas.\n'
            '• **Exílio**: cartas removidas do jogo.\n\n'
            'Na app, o campo está ao meio, a mão em baixo e o grimório, cemitério e exílio por baixo do campo.',
      ),
    ],
  ),
  Chapter(
    id: 'mtg-mana',
    title: 'Terrenos e mana',
    summary: 'Um terreno por turno, virar para ter mana e pagar custos',
    minutes: 5,
    pages: const [
      TPage(
        'Mana',
        'Há cinco cores de mana: **branco** {W}, **azul** {U}, **preto** {B}, **vermelho** {R} e **verde** {G}, '
            'mais a mana **incolor** {C}.\n\n'
            'Cada terreno básico dá uma cor: Plains (branco), Island (azul), Swamp (preto), Mountain '
            '(vermelho) e Forest (verde).\n\n'
            'Para usar um terreno, **viras-o** (tap): fica de lado e dá uma mana. Só volta a ficar direito no '
            'início do teu próximo turno.',
        cards: [TCard(forest), TCard(mountain), TCard(plains)],
      ),
      TPage(
        'Pagar um custo',
        'O custo {1}{G} quer dizer: **uma mana verde** e **uma mana de qualquer cor**.\n\n'
            '• Só podes jogar **um terreno por turno**, no teu turno.\n'
            '• A mana que não usares desaparece no fim de cada passo do turno.\n'
            '• Algumas criaturas também dão mana, como o Elvish Mystic.',
        cards: [TCard(bears, caption: '{1}{G}'), TCard(mystic, caption: '{G}, e dá {G}')],
      ),
    ],
    setup: TSetup(
      seats: [
        TSeat(
          name: 'Tu',
          commander: marwyn,
          hand: [forest, mystic, forest, bears, forest, warrior, baloth],
          library: [forest, visionary, ..._many(forest, 6)],
        ),
        TSeat(name: 'Bruno', commander: krenko, hand: _many(mountain, 7), library: _many(mountain, 8)),
        TSeat(name: 'Carla', commander: isamaru, hand: _many(plains, 7), library: _many(plains, 8)),
      ],
    ),
    steps: [
      TStep(
        'É o teu primeiro turno. Joga um **Forest**: toca nele na tua mão (em baixo) e escolhe **Jogar para o '
        'campo**.',
        allow: Allow.play(forest),
        done: Done.onField(forest),
        hint: 'Toca num Forest na tua mão e escolhe "Jogar para o campo".',
      ),
      TStep(
        'O Elvish Mystic custa {G}. Vira o Forest para teres essa mana: toca nele e escolhe **Virar (tap)**.',
        allow: Allow.tap([forest]),
        done: Done.tapped(forest),
        hint: 'Toca no Forest que está em campo e escolhe "Virar (tap)".',
      ),
      TStep(
        'Agora joga o **Elvish Mystic** da mão.',
        allow: Allow.play(mystic),
        done: Done.onField(mystic),
        hint: 'Toca no Elvish Mystic na tua mão e escolhe "Jogar para o campo".',
      ),
      const TStep(
        'O Elvish Mystic dá mana quando se vira, mas acabou de entrar: uma criatura que entrou neste turno '
        'não pode virar-se nem atacar (chama-se **enjoo de invocação**). No próximo turno já pode.',
        focus: [mystic],
      ),
      TStep(
        'Já não podes fazer mais nada. Passa a vez com **Passar turno**.',
        allow: Allow.passTurn,
        done: Done.turnOf(bruno),
        hint: 'Toca em "Passar turno".',
      ),
      TStep(
        'É outra vez a tua vez. No início do turno, as tuas cartas viradas **desviram-se** sozinhas. Depois '
        '**compras uma carta**: toca uma vez no teu **Grimório** (por baixo do campo).',
        run: const [
          Play(bruno, mountain, say: 'O Bruno joga uma Mountain e passa.'),
          PassTurn(),
          Play(carla, plains, say: 'A Carla joga um Plains e passa.'),
          PassTurn(say: 'A vez volta para ti.'),
        ],
        allow: Allow.draw,
        done: Done.handAtLeast(0, 6),
        hint: 'Toca uma vez no teu Grimório (por baixo do campo): compras uma carta.',
      ),
      TStep(
        'Joga outro **Forest**.',
        allow: Allow.play(forest),
        done: (t) => t.cardsNamed(forest, zone: Zone.battlefield, seat: 0).length >= 2,
        hint: 'Toca num Forest na tua mão e escolhe "Jogar para o campo".',
      ),
      TStep(
        'O Grizzly Bears custa {1}{G}: duas mana. Vira os **dois Forests** (ou um Forest e o Elvish Mystic, que '
        'já pode).',
        allow: Allow.tap([forest, mystic]),
        done: (t) =>
            t.cardsNamed(forest, zone: Zone.battlefield, seat: 0).where((c) => c.tapped).length +
                t.cardsNamed(mystic, zone: Zone.battlefield, seat: 0).where((c) => c.tapped).length >=
            2,
        hint: 'Vira duas cartas que dão mana: os Forests ou o Elvish Mystic.',
      ),
      TStep(
        'Joga o **Grizzly Bears**.',
        allow: Allow.play(bears),
        done: Done.onField(bears),
        hint: 'Toca no Grizzly Bears na tua mão e escolhe "Jogar para o campo".',
      ),
      const TStep('Muito bem: pagaste {1}{G} com duas mana. É sempre assim que se lançam as cartas.'),
    ],
  ),
  const Chapter(
    id: 'mtg-turn',
    title: 'As fases do turno',
    summary: 'Desvirar, comprar, fase principal, combate e fim',
    minutes: 3,
    pages: [
      TPage(
        'O turno, por ordem',
        '1. **Início**: desviras as tuas cartas, acontecem os efeitos de "no início da manutenção" e '
            'compras uma carta.\n'
            '2. **Fase principal**: jogas um terreno e lanças criaturas e feitiços.\n'
            '3. **Combate**: atacas com as tuas criaturas.\n'
            '4. **Segunda fase principal**: mais uma oportunidade de jogar cartas.\n'
            '5. **Fim**: se tiveres mais de 7 cartas na mão, descartas até ficares com 7. O dano nas criaturas '
            'desaparece.',
      ),
      TPage(
        'Na app',
        'A app não obriga a seguir as fases: é uma mesa, como a da tua casa. O botão no topo mostra a fase '
            'em que estás, se quiseres marcá-la para os outros.\n\n'
            '• Ao **passar o turno**, as cartas do jogador seguinte desviram-se sozinhas.\n'
            '• Para comprar, toca no **Grimório**. Mantendo o dedo no Grimório abres mais opções (baralhar, '
            'scry, mulligan…).',
      ),
    ],
  ),
  Chapter(
    id: 'mtg-combat',
    title: 'Criaturas e combate',
    summary: 'Atacar, bloquear para te defender, o dano e as habilidades',
    minutes: 5,
    pages: const [
      TPage(
        'Atacar',
        'No combate, escolhes que criaturas atacam e **viras-as**. Cada uma ataca um jogador.\n\n'
            '• Uma criatura que entrou neste turno não pode atacar (enjoo de invocação), a não ser que tenha '
            '**Haste**.\n'
            '• O jogador atacado escolhe se **bloqueia** com as criaturas dele que estão desviradas.\n'
            '• Se ninguém bloqueia, o atacante dá o seu **poder** em dano ao jogador.',
      ),
      TPage(
        'O dano',
        'Quando há bloqueio, as duas criaturas dão dano uma à outra ao mesmo tempo. Uma criatura morre se o '
            'dano for igual ou maior que a sua **resistência** (o segundo número).\n\n'
            'Exemplo: um Grizzly Bears (2/2) bloqueado por um Goblin Piker (2/1): os dois levam 2, e morrem os '
            'dois.\n\n'
            'Criaturas mortas vão para o **cemitério**.',
        cards: [TCard(bears, caption: '2/2'), TCard(piker, caption: '2/1')],
      ),
      TPage(
        'Habilidades comuns',
        '• **Flying** (voar): só pode ser bloqueada por criaturas com Flying ou Reach.\n'
            '• **Haste** (pressa): pode atacar no turno em que entra.\n'
            '• **Vigilance**: ataca sem se virar.\n'
            '• **Trample**: o dano que sobra do bloqueador passa para o jogador.\n'
            '• **Deathtouch**: qualquer dano dela mata.\n'
            '• **Lifelink**: o dano que dá também te dá vida.',
      ),
    ],
    setup: TSetup(
      turn: 4,
      seats: [
        TSeat(
          name: 'Tu',
          commander: marwyn,
          battlefield: [..._many(forest, 3), bears, warrior, baloth],
          hand: [forest],
          library: _many(forest, 8),
        ),
        TSeat(
          name: 'Bruno',
          commander: krenko,
          battlefield: [..._many(mountain, 3), piker],
          hand: [raging, mountain],
          library: _many(mountain, 8),
        ),
        TSeat(
          name: 'Carla',
          commander: isamaru,
          battlefield: _many(plains, 3),
          hand: [plains, plains],
          library: _many(plains, 8),
        ),
      ],
    ),
    steps: [
      const TStep(
        'Tens o **Grizzly Bears** (2/2), o **Elvish Warrior** (2/3) e o **Leatherback Baloth** (4/5) em campo '
        'desde turnos anteriores, por isso podem atacar. O Bruno tem um **Goblin Piker** (2/1) desvirado, que '
        'pode bloquear.',
      ),
      TStep(
        'Ataca o Bruno com o **Grizzly Bears** e o **Elvish Warrior**: vira os dois. O **Baloth fica em casa** '
        'para te defender no turno do Bruno (uma criatura virada não pode bloquear).',
        allow: Allow.tap([bears, warrior]),
        done: Done.all([Done.tapped(bears), Done.tapped(warrior)]),
        hint: 'Toca no Grizzly Bears e no Elvish Warrior e escolhe "Virar (tap)". O Baloth fica desvirado.',
        focus: [bears, warrior],
      ),
      TStep(
        'O Bruno bloqueou o Grizzly Bears com o Goblin Piker. Cada um deu 2 de dano ao outro: o Goblin Piker '
        '(resistência 1) morreu, e o Grizzly Bears (resistência 2) também. Põe o **Grizzly Bears** no '
        '**cemitério**: toca nele e escolhe **Para o cemitério**.',
        run: const [
          Pause(say: 'O Bruno decide bloquear…', ms: 1200),
          MoveCard(bruno, piker, Zone.graveyard, say: 'O Goblin Piker bloqueou o Grizzly Bears e morreu.'),
        ],
        allow: Allow.move(bears, Zone.graveyard),
        done: Done.inZone(bears, Zone.graveyard),
        hint: 'Toca no Grizzly Bears e escolhe "Para o cemitério".',
        focus: [bears],
      ),
      TStep(
        'O Elvish Warrior não foi bloqueado: dá 2 de dano ao Bruno. Toca no cartão do **Bruno** (lá em cima) '
        'e tira-lhe **2 de vida** (o botão **-1**, duas vezes).',
        allow: Allow.life(bruno),
        done: Done.lifeAtMost(bruno, 38),
        hint: 'Toca no cartão do Bruno e usa o -1 da vida, duas vezes.',
      ),
      TStep(
        'Passa a vez. Agora vais ver o outro lado: defender.',
        allow: Allow.passTurn,
        done: Done.turnOf(bruno),
        hint: 'Toca em "Passar turno".',
      ),
      TStep(
        'O Bruno jogou um **Raging Goblin** (1/1) com **Haste** e atacou-te logo. O Warrior está virado (atacou) '
        'e não pode bloquear, mas o **Baloth** ficou em casa. Bloqueia: toca no **Leatherback Baloth** → '
        '**Apontar para…** → **Raging Goblin**.',
        run: const [
          Play(bruno, mountain, say: 'O Bruno joga uma Mountain…'),
          Play(bruno, raging, say: '…e um Raging Goblin, com Haste.'),
          Attack(bruno, raging, 0, say: 'O Raging Goblin ataca-te!'),
        ],
        done: Done.arrow(baloth, raging),
        hint: 'Toca no Leatherback Baloth, escolhe "Apontar para…" e depois o Raging Goblin.',
        focus: [baloth],
      ),
      const TStep(
        'O Baloth dá 4 de dano ao Goblin (resistência 1), que morre. O Goblin dá 1 ao Baloth (resistência 5), '
        'que nem sente. Bloquear bem é tão importante como atacar.',
        run: [
          ClearTargets(bruno),
          ClearTargets(0),
          MoveCard(bruno, raging, Zone.graveyard, say: 'O Raging Goblin morre.'),
        ],
      ),
      const TStep(
        'É assim o combate: atacas, o defensor escolhe os bloqueios e trocam dano. Na app, o bloqueio marca-se '
        'com uma seta, e o dano e as criaturas mortas registam-se à mão, como numa mesa a sério.',
      ),
    ],
  ),
  Chapter(
    id: 'mtg-stack',
    title: 'Instantâneos e a pilha',
    summary: 'Responder a um feitiço do adversário com um instantâneo',
    minutes: 4,
    pages: const [
      TPage(
        'A pilha',
        'Quando alguém lança um feitiço ou usa uma habilidade, ele não acontece logo: vai para a **pilha**. '
            'Todos podem **responder** com instantâneos, que ficam por cima.\n\n'
            'Depois resolve-se de cima para baixo: **o último a entrar é o primeiro a acontecer**.',
      ),
      TPage(
        'Um exemplo',
        'O Bruno lança Lightning Bolt (3 de dano) no teu Elvish Warrior (2/3), que morreria.\n\n'
            'Em resposta, lanças Giant Growth (+3/+3 até ao fim do turno) no Elvish Warrior.\n\n'
            'O Giant Growth entrou por último, por isso acontece primeiro: o Elvish Warrior fica 5/6. Depois o '
            'Lightning Bolt dá-lhe 3 de dano, e ele sobrevive.',
        cards: [TCard(bolt), TCard(giantGrowth), TCard(warrior)],
      ),
    ],
    setup: TSetup(
      turn: 4,
      active: bruno,
      seats: [
        TSeat(
          name: 'Tu',
          commander: marwyn,
          battlefield: [..._many(forest, 3), warrior],
          hand: [giantGrowth, forest, baloth],
          library: _many(forest, 8),
        ),
        TSeat(
          name: 'Bruno',
          commander: krenko,
          battlefield: _many(mountain, 3),
          hand: [bolt, mountain],
          library: _many(mountain, 8),
        ),
        TSeat(
          name: 'Carla',
          commander: isamaru,
          battlefield: _many(plains, 3),
          hand: [plains],
          library: _many(plains, 8),
        ),
      ],
    ),
    steps: [
      TStep(
        'É o turno do Bruno e ele lançou **Lightning Bolt** no teu **Elvish Warrior**. Responde: vira um '
        '**Forest** para pagar {G}.',
        run: const [
          Tap(bruno, [mountain]),
          Target(bruno, warrior, targetSeat: 0),
          Cast(bruno, bolt, say: 'O Bruno lança Lightning Bolt no teu Elvish Warrior!'),
        ],
        allow: Allow.tap([forest]),
        done: Done.tapped(forest),
        hint: 'Toca num Forest e escolhe "Virar (tap)".',
        focus: [warrior],
      ),
      TStep(
        'Agora lança o **Giant Growth**: toca nele na mão e escolhe **Lançar (vai para o cemitério)**.',
        allow: Allow.cast(giantGrowth),
        done: Done.inZone(giantGrowth, Zone.graveyard),
        hint: 'Toca no Giant Growth na tua mão e escolhe "Lançar (vai para o cemitério)".',
      ),
      const TStep(
        'O Giant Growth resolve primeiro: o Elvish Warrior fica 5/6. Depois o Lightning Bolt dá-lhe 3 de dano, '
        'e ele sobrevive! No fim do turno o efeito acaba e o dano desaparece.\n\n'
        'Na app, quando é preciso, marcas o +3/+3 na carta em **Contadores** → modificadores.',
        focus: [warrior],
        run: [ClearTargets(bruno)],
      ),
    ],
  ),
  const Chapter(
    id: 'mtg-win',
    title: 'Ganhar e perder',
    summary: 'As formas de perder um jogo, e o salto para o Commander',
    minutes: 2,
    pages: [
      TPage(
        'Como se perde',
        '• Ficar com **0 de vida** ou menos.\n'
            '• Ter de **comprar uma carta com o grimório vazio**.\n'
            '• Ter **10 marcadores de veneno** (poison).\n'
            '• **Desistir**: podes sempre.\n\n'
            'No Commander há mais uma: levar **21 de dano de combate do mesmo comandante**. Já vais ver.',
      ),
      TPage(
        'E agora, o Commander',
        'Já sabes o essencial do Magic: terrenos e mana, criaturas e combate, instantâneos e a pilha.\n\n'
            'Os próximos capítulos ensinam o que o **Commander** tem de especial. Não te preocupes se ainda '
            'não sabes todas as regras: no Commander aprende-se muito a jogar com amigos.',
      ),
    ],
  ),
];
