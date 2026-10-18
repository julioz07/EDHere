import 'package:mesa_core/mesa_core.dart';

import 'tutorial.dart';
import 'tutorial_runner.dart';

// Regras validadas em outubro de 2026 com a página oficial do formato
// (magic.wizards.com/en/content/commander-format) e as regras completas:
// 99 + comandante, singleton (exceto básicos), identidade de cor, vida 40,
// taxa de {2} por cada lançamento anterior da zona de comando, 21 de dano de
// combate do mesmo comandante, voltar à zona de comando, primeiro mulligan
// grátis a vários, Vehicles/Spacecraft lendários desde 2025, brackets 1–5.

const marwyn = 'Marwyn, the Nurturer';
const krenko = 'Krenko, Mob Boss';
const isamaru = 'Isamaru, Hound of Konda';
const forest = 'Forest';
const mountain = 'Mountain';
const plains = 'Plains';
const mystic = 'Elvish Mystic';
const fyndhorn = 'Fyndhorn Elves';
const warrior = 'Elvish Warrior';
const bears = 'Grizzly Bears';
const visionary = 'Elvish Visionary';
const baloth = 'Leatherback Baloth';
const raging = 'Raging Goblin';
const piker = 'Goblin Piker';
const bolt = 'Lightning Bolt';
const swords = 'Swords to Plowshares';
const lions = 'Savannah Lions';

/// O Bruno (vermelho, goblins) e a Carla (branco) são os adversários.
const bruno = 1, carla = 2;

List<String> _many(String name, int n) => List.filled(n, name);

/// Contador +1/+1 na Marwyn (o jogador põe-no à mão, como na mesa).
bool Function(TableView) _marwynCounters(int n) => (t) => t
    .cardsNamed(marwyn, zone: Zone.battlefield, seat: 0)
    .any((c) => (c.counters[CounterKind.plus] ?? 0) >= n);

/// "Já sei jogar Magic": só o que muda no Commander.
final commanderChapters = <Chapter>[
  const Chapter(
    id: 'cmd-deck',
    title: 'O baralho de Commander',
    summary: '100 cartas, uma de cada, e o comandante que manda nas cores',
    minutes: 3,
    pages: [
      TPage(
        'Um formato para jogar com amigos',
        'O **Commander** (também chamado **EDH**) joga-se normalmente a **quatro**, cada um contra todos. '
            'É o formato mais jogado do mundo em mesas casuais: os jogos são longos, sociais e cheios de '
            'jogadas grandes.\n\n'
            'Cada jogador escolhe uma criatura lendária para ser o seu **comandante**. O baralho inteiro é '
            'construído à volta dela.',
        cards: [TCard(marwyn, caption: 'O teu comandante neste tutorial')],
      ),
      TPage(
        '100 cartas, uma de cada',
        'O baralho tem **exatamente 100 cartas**: o comandante e mais 99.\n\n'
            '• Só pode haver **uma cópia** de cada carta (é um baralho "singleton").\n'
            '• A exceção são os **terrenos básicos**: podes ter quantos quiseres. Também há cartas que '
            'o dizem no texto, como Relentless Rats.\n'
            '• Não há sideboard.',
        cards: [
          TCard(forest, caption: 'Quantos quiseres', ok: true),
          TCard(bears, caption: 'Só uma', ok: true),
        ],
      ),
      TPage(
        'O comandante',
        'O comandante tem de ser uma **criatura lendária**. Também servem:\n\n'
            '• cartas que dizem "**can be your commander**";\n'
            '• desde 2025, **Vehicles** e **Spacecraft** lendários com poder e resistência.\n\n'
            'Algumas lendas permitem **dois comandantes**: as que têm **Partner** (ou "Partner with"), '
            '**Friends forever** ou **Choose a Background** (com um Background).',
        cards: [TCard(marwyn, ok: true), TCard(krenko, ok: true), TCard(isamaru, ok: true)],
      ),
      TPage(
        'Identidade de cor',
        'Todas as cartas do baralho têm de caber na **identidade de cor** do comandante: as cores de todos '
            'os símbolos de mana que aparecem no custo **e no texto** da carta (o texto de lembrete entre '
            'parênteses não conta).\n\n'
            '• A Marwyn é verde: só entram cartas verdes ou incolores.\n'
            '• Um símbolo híbrido (verde/branco) conta as **duas** cores.\n'
            '• Cartas incolores, como Sol Ring, entram em qualquer baralho.',
        cards: [
          TCard(mystic, ok: true),
          TCard('Sol Ring', ok: true),
          TCard(bolt, caption: 'Vermelha', ok: false),
          TCard('Kitchen Finks', caption: 'Híbrida: tem branco', ok: false),
        ],
      ),
    ],
  ),
  Chapter(
    id: 'cmd-start',
    title: 'Começar o jogo',
    summary: 'Vida 40, a zona de comando, o mulligan grátis e a ordem dos turnos',
    minutes: 4,
    pages: const [
      TPage(
        'Antes do primeiro turno',
        '• Cada jogador começa com **40 de vida** (em vez de 20).\n'
            '• O comandante começa na **zona de comando**, à vista de todos, fora do baralho.\n'
            '• Cada um compra **7 cartas**. A vários, o **primeiro mulligan é grátis**: voltas a comprar 7 e '
            'não pões nenhuma no fundo. A partir do segundo, é como no Magic normal.\n'
            '• Sorteia-se quem começa e o jogo segue **para a esquerda** (sentido dos ponteiros do relógio).',
      ),
    ],
    setup: TSetup(
      seats: [
        TSeat(
          name: 'Tu',
          commander: marwyn,
          hand: [forest, forest, mystic, bears, visionary, forest, baloth],
          library: [forest, fyndhorn, forest, warrior, ..._many(forest, 6)],
        ),
        TSeat(
          name: 'Bruno',
          commander: krenko,
          hand: [mountain, raging, mountain, piker, bolt, mountain, mountain],
          library: _many(mountain, 10),
        ),
        TSeat(
          name: 'Carla',
          commander: isamaru,
          hand: [plains, lions, plains, swords, plains, plains, plains],
          library: _many(plains, 10),
        ),
      ],
    ),
    steps: [
      const TStep(
        'Esta é a tua mesa. Tu, o **Bruno** e a **Carla** começam com **40 de vida**: vês nos cartões lá em '
        'cima. Toca no cartão de um jogador para ver o campo dele.',
      ),
      const TStep(
        'O teu comandante, a **Marwyn**, está na **zona de comando**: é a carta com a etiqueta "Comando", por '
        'baixo do campo. Não está na mão nem no grimório: podes lançá-la sempre que tiveres mana para isso.',
        focus: marwyn,
      ),
      const TStep(
        'A tua mão tem terrenos e criaturas baratas, por isso ficas com ela. Se não gostasses, o primeiro '
        'mulligan era grátis.',
      ),
      TStep(
        'Joga um **Forest**: toca nele na mão e escolhe **Jogar para o campo** (ou arrasta-o para o campo).',
        allow: Allow.play(forest),
        done: Done.onField(forest),
        hint: 'Toca num Forest na tua mão e escolhe "Jogar para o campo".',
      ),
      TStep(
        'Agora vira o Forest para teres mana verde (toca nele e **Virar (tap)**) e joga o **Elvish Mystic**.',
        allow: Allow.any([
          Allow.tap([forest]),
          Allow.play(mystic)
        ]),
        done: Done.all([Done.onField(mystic), Done.tapped(forest)]),
        hint: 'Vira o Forest e joga o Elvish Mystic da mão.',
      ),
      TStep(
        'Já está. Passa a vez com **Passar turno**. A vez passa para a esquerda: primeiro o Bruno, depois a '
        'Carla.',
        allow: Allow.passTurn,
        done: Done.turnOf(bruno),
        hint: 'Toca em "Passar turno".',
      ),
      const TStep(
        'No Commander podes atacar **qualquer** jogador. O Bruno escolheu atacar-te: tens agora **39 de vida**.',
        run: [
          Play(bruno, mountain, say: 'O Bruno joga uma Mountain…'),
          Play(bruno, raging, say: '…e um Raging Goblin, que tem pressa (haste): pode atacar logo.'),
          Tap(bruno, [raging], say: 'O Raging Goblin ataca-te!'),
          Life(0, -1),
          PassTurn(say: 'Agora é a vez da Carla.'),
          Play(carla, plains, say: 'A Carla joga um Plains…'),
          Play(carla, lions, say: '…e um Savannah Lions.'),
          PassTurn(say: 'A vez volta para ti.'),
          UntapAll(0),
          Draw(0, 1, 'Desviras tudo e compras uma carta.'),
        ],
      ),
      const TStep(
        'É assim que o jogo anda, sempre para a esquerda. No próximo capítulo lanças o teu comandante.',
      ),
    ],
  ),
  Chapter(
    id: 'cmd-cast',
    title: 'Lançar o comandante e a taxa',
    summary: 'Lançar da zona de comando, voltar a ela e pagar mais 2 de cada vez',
    minutes: 5,
    pages: const [
      TPage(
        'Lançar o comandante',
        'Lanças o comandante a partir da zona de comando **como se estivesse na mão**: pagas o custo, '
            'no teu turno, quando podes lançar uma criatura. Ao entrar, tem enjoo de invocação como '
            'qualquer outra.',
        cards: [TCard(marwyn, caption: 'Custa {2}{G}')],
      ),
      TPage(
        'Quando o comandante sai',
        'Se o comandante **morre** ou é **exilado**, o dono pode pô-lo de volta na **zona de comando**. '
            'Ele morre mesmo (as habilidades de "quando morre" disparam) e só depois volta.\n\n'
            'Se fosse para a **mão** ou para o **grimório**, o dono pode pô-lo na zona de comando em vez '
            'disso.\n\n'
            'Se o deixares no cemitério, não o podes lançar de lá: só se lança da zona de comando.',
      ),
      TPage(
        'A taxa de comandante',
        'Cada vez que lanças o comandante da zona de comando, custa **mais {2}** por cada vez que já o '
            'lançaste antes nesse jogo:\n\n'
            '• 1.ª vez: o custo normal.\n'
            '• 2.ª vez: custo + {2}.\n'
            '• 3.ª vez: custo + {4}, e assim por diante.\n\n'
            'A app conta a taxa sozinha e mostra-a no cartão do comandante.',
      ),
    ],
    setup: TSetup(
      turn: 3,
      seats: [
        TSeat(
          name: 'Tu',
          commander: marwyn,
          battlefield: [forest, forest, mystic],
          hand: [forest, bears, warrior, baloth],
          library: [forest, visionary, ..._many(forest, 6)],
        ),
        TSeat(
          name: 'Bruno',
          commander: krenko,
          battlefield: [mountain, mountain, raging],
          hand: [mountain, piker, bolt],
          library: _many(mountain, 8),
        ),
        TSeat(
          name: 'Carla',
          commander: isamaru,
          battlefield: [plains, plains, lions],
          hand: [plains, swords, plains],
          library: _many(plains, 8),
        ),
      ],
    ),
    steps: [
      TStep(
        'É o teu terceiro turno. Joga um **Forest**.',
        allow: Allow.play(forest),
        done: (t) => t.cardsNamed(forest, zone: Zone.battlefield, seat: 0).length >= 3,
        hint: 'Toca num Forest na tua mão e escolhe "Jogar para o campo".',
      ),
      TStep(
        'A Marwyn custa {2}{G}. Vira os **três Forests** para pagar.',
        allow: Allow.tap([forest]),
        done: Done.tapped(forest, n: 3),
        hint: 'Toca em cada Forest e escolhe "Virar (tap)".',
      ),
      TStep(
        'Agora lança a Marwyn: toca nela na **zona de comando** e escolhe **Para o campo**.',
        allow: Allow.move(marwyn, Zone.battlefield, from: Zone.command),
        done: Done.onField(marwyn),
        hint: 'Toca na Marwyn (por baixo do campo, com a etiqueta "Comando") e escolhe "Para o campo".',
        focus: marwyn,
      ),
      TStep(
        'A Marwyn está em campo. Passa a vez.',
        allow: Allow.passTurn,
        done: Done.turnOf(bruno),
        hint: 'Toca em "Passar turno".',
      ),
      TStep(
        'A Carla exilou a Marwyn com Swords to Plowshares (e tu ganhaste 1 de vida, o poder da Marwyn). '
        'Pela regra do Commander, podes pô-la na zona de comando: abre o **Exílio** (por baixo do campo), '
        'toca na Marwyn e escolhe **Para a zona de comando**.',
        run: const [
          Play(bruno, mountain, say: 'O Bruno joga uma Mountain…'),
          Tap(bruno, [raging], say: '…e ataca a Carla com o Raging Goblin.'),
          Life(carla, -1),
          PassTurn(say: 'Agora é a vez da Carla.'),
          Play(carla, plains, say: 'A Carla joga um Plains…'),
          Cast(carla, swords, say: '…e lança Swords to Plowshares na tua Marwyn!'),
          MoveCard(0, marwyn, Zone.exile),
          Life(0, 1),
        ],
        allow: Allow.move(marwyn, Zone.command),
        done: Done.inZone(marwyn, Zone.command),
        hint: 'Toca no Exílio, depois na Marwyn, e escolhe "Para a zona de comando".',
      ),
      const TStep(
        'A Marwyn voltou à zona de comando. Da próxima vez que a lançares custa **{2} a mais**: 5 mana em vez '
        'de 3. A app já mostra a taxa no cartão dela.',
        focus: marwyn,
        run: [
          PassTurn(say: 'A Carla passa a vez.'),
          UntapAll(0),
          Draw(0, 1, 'Desviras tudo e compras uma carta.'),
        ],
      ),
      TStep(
        'Joga mais um **Forest**.',
        allow: Allow.play(forest),
        done: (t) => t.cardsNamed(forest, zone: Zone.battlefield, seat: 0).length >= 4,
        hint: 'Toca num Forest na tua mão e escolhe "Jogar para o campo".',
      ),
      TStep(
        'Para pagar 5, vira os **quatro Forests** e o **Elvish Mystic**.',
        allow: Allow.tap([forest, mystic]),
        done: Done.all([Done.tapped(forest, n: 4), Done.tapped(mystic)]),
        hint: 'Vira os quatro Forests e o Elvish Mystic.',
      ),
      TStep(
        'Lança outra vez a Marwyn da zona de comando.',
        allow: Allow.move(marwyn, Zone.battlefield, from: Zone.command),
        done: Done.onField(marwyn),
        hint: 'Toca na Marwyn na zona de comando e escolhe "Para o campo".',
        focus: marwyn,
      ),
      const TStep(
        'Pagaste 5: os 3 do custo e 2 de taxa. Se voltar a sair e a lançares de novo, vai custar 7.',
      ),
    ],
  ),
  Chapter(
    id: 'cmd-attack',
    title: 'Atacar e dano de comandante',
    summary: 'Atacar vários jogadores e ganhar com 21 de dano do mesmo comandante',
    minutes: 4,
    pages: const [
      TPage(
        'Atacar quem quiseres',
        'Quando atacas, escolhes **para cada criatura** o jogador (ou planeswalker) que ela ataca. Podes '
            'atacar dois jogadores no mesmo combate.\n\n'
            'Só o jogador atacado pode bloquear as criaturas que o atacam.',
      ),
      TPage(
        'Dano de comandante',
        'Um jogador que leve **21 ou mais de dano de combate do mesmo comandante**, somado ao longo do '
            'jogo, **perde** — mesmo que ainda tenha vida.\n\n'
            '• Conta por comandante: 11 de um e 10 de outro não chegam.\n'
            '• Só conta o dano de **combate**.\n'
            '• Continua a contar mesmo que o comandante tenha voltado à zona de comando.\n\n'
            'Na app, o dano de comandante regista-se no cartão do jogador, e também lhe tira vida.',
      ),
    ],
    setup: TSetup(
      turn: 8,
      seats: [
        TSeat(
          name: 'Tu',
          commander: marwyn,
          battlefield: [..._many(forest, 5), mystic, warrior],
          hand: [forest, baloth],
          library: _many(forest, 8),
        ),
        TSeat(
          name: 'Bruno',
          commander: krenko,
          battlefield: _many(mountain, 4),
          hand: [mountain, bolt],
          library: _many(mountain, 8),
        ),
        TSeat(
          name: 'Carla',
          commander: isamaru,
          battlefield: [..._many(plains, 4), lions],
          hand: [plains, plains],
          library: _many(plains, 8),
          life: 31,
        ),
      ],
      prepare: const [
        CastCommander(0),
        Counter(0, marwyn, CounterKind.plus, 4),
        CastCommander(bruno),
        CastCommander(carla),
        CommanderHit(0, bruno, 16),
      ],
    ),
    steps: [
      const TStep(
        'A Marwyn já tem **4 contadores +1/+1**: é uma 5/5. Em turnos anteriores, o Bruno levou **16 de dano '
        'de comandante** dela: vês no cartão dele.',
        focus: marwyn,
      ),
      TStep(
        'Vais atacar dois jogadores ao mesmo tempo: a **Marwyn** ataca o Bruno e o **Elvish Warrior** ataca a '
        'Carla. Vira as duas criaturas para atacar.',
        allow: Allow.tap([marwyn, warrior]),
        done: Done.all([Done.tapped(marwyn), Done.tapped(warrior)]),
        hint: 'Toca na Marwyn e no Elvish Warrior e escolhe "Virar (tap)".',
      ),
      TStep(
        'Ninguém bloqueia. Regista o dano da Marwyn: toca no cartão do **Bruno** lá em cima e, em **Dano de '
        'comandante**, carrega no + da Marwyn até chegar a **21**.',
        allow: Allow.commanderDamage(bruno),
        done: Done.commanderDamage(bruno, 0, 21),
        hint: 'Toca no cartão do Bruno e usa o + ao lado da Marwyn, em "Dano de comandante".',
      ),
      const TStep(
        'O Bruno ainda tinha vida, mas **21 de dano de combate do mesmo comandante** bastam: perdeu o jogo.',
        run: [Concede(bruno, say: 'O Bruno chegou aos 21 de dano da Marwyn.')],
      ),
      TStep(
        'Falta o dano do Elvish Warrior à Carla: é dano normal (não é de um comandante). Toca no cartão da '
        '**Carla** e tira-lhe **2 de vida**.',
        allow: Allow.life(carla),
        done: Done.lifeAtMost(carla, 29),
        hint: 'Toca no cartão da Carla e usa o − da vida, duas vezes.',
      ),
      const TStep(
        'Quando um jogador perde, as cartas dele saem do jogo. O jogo continua entre ti e a Carla até '
        'sobrar um.',
      ),
    ],
  ),
  const Chapter(
    id: 'cmd-table',
    title: 'Jogar a vários e combinar o jogo',
    summary: 'Política, a regra zero, os brackets e as cartas banidas',
    minutes: 3,
    pages: [
      TPage(
        'Política à mesa',
        'Com quatro jogadores, conversar faz parte do jogo:\n\n'
            '• Podes propor acordos ("não te ataco se não me atacares"), mas **não obrigam** ninguém: são só '
            'palavras.\n'
            '• Vale a pena perceber quem está a ganhar e travar essa pessoa, em vez de atacar quem está fraco.\n'
            '• Não podes dar cartas nem mostrar a mão por acordo; podes mostrar o que quiseres por tua conta.',
      ),
      TPage(
        'A regra zero',
        'Antes de jogar, combina-se o tipo de jogo: há quem jogue baralhos simples e quem jogue baralhos '
            'muito fortes. A "**regra zero**" é essa conversa: qualquer mudança às regras vale se todos '
            'concordarem.\n\n'
            'O objetivo é que todos se divirtam, não só quem ganha.',
      ),
      TPage(
        'Brackets e Game Changers',
        'Para ajudar a combinar, a Wizards criou os **brackets** (ainda em beta), de 1 a 5:\n\n'
            '• **1 Exhibition** e **2 Core**: baralhos temáticos ou de pré-construído, sem Game Changers.\n'
            '• **3 Upgraded**: até 3 Game Changers.\n'
            '• **4 Optimized** e **5 cEDH**: sem limite; o 5 é o competitivo.\n\n'
            'Os **Game Changers** são uma lista oficial de cartas muito fortes. A app mostra no editor de '
            'deck quantas tens e o bracket estimado.',
      ),
      TPage(
        'Cartas banidas',
        'O Commander tem uma **lista oficial de cartas banidas**, diferente da de outros formatos. A app '
            'avisa na validação do deck se tiveres alguma.\n\n'
            'Já sabes tudo o que precisas. Falta o **jogo final**, que junta tudo.',
      ),
    ],
  ),
  Chapter(
    id: 'cmd-final',
    title: 'Jogo final',
    summary: 'Um jogo curto que junta tudo o que aprendeste',
    minutes: 6,
    setup: TSetup(
      turn: 5,
      seats: [
        TSeat(
          name: 'Tu',
          commander: marwyn,
          battlefield: [..._many(forest, 3), mystic, bears, warrior],
          hand: [forest, fyndhorn, baloth],
          library: [forest, visionary, ..._many(forest, 6)],
        ),
        TSeat(
          name: 'Bruno',
          commander: krenko,
          battlefield: _many(mountain, 4),
          hand: [mountain, bolt],
          library: _many(mountain, 8),
          life: 6,
        ),
        TSeat(
          name: 'Carla',
          commander: isamaru,
          battlefield: [..._many(plains, 4), lions],
          hand: [swords, plains],
          library: _many(plains, 8),
          life: 33,
        ),
      ],
      prepare: const [CastCommander(bruno), CastCommander(carla)],
    ),
    steps: [
      const TStep(
        'Jogo final. O **Bruno** está com **6 de vida** e tem o Krenko em campo. A **Carla** está forte. '
        'Usa o que aprendeste.',
      ),
      TStep(
        'Joga um **Forest**.',
        allow: Allow.play(forest),
        done: (t) => t.cardsNamed(forest, zone: Zone.battlefield, seat: 0).length >= 4,
        hint: 'Toca no Forest na tua mão e escolhe "Jogar para o campo".',
      ),
      TStep(
        'Vira **três Forests** e lança a **Marwyn** da zona de comando.',
        allow: Allow.any([
          Allow.tap([forest]),
          Allow.move(marwyn, Zone.battlefield, from: Zone.command)
        ]),
        done: Done.onField(marwyn),
        hint: 'Vira três Forests e depois toca na Marwyn (zona de comando) → "Para o campo".',
        focus: marwyn,
      ),
      TStep(
        'Vira o **Elvish Mystic** e joga os **Fyndhorn Elves**. Como entrou outro Elfo, a Marwyn ganha um '
        'contador: toca nela → **Contadores** → **+1/+1**.',
        allow: Allow.any([
          Allow.tap([mystic]),
          Allow.play(fyndhorn),
          (a) => a.type == Ev.counter && a.has(marwyn),
        ]),
        done: Done.all([Done.onField(fyndhorn), _marwynCounters(1)]),
        hint: 'Vira o Elvish Mystic, joga os Fyndhorn Elves e põe um contador +1/+1 na Marwyn.',
      ),
      TStep(
        'A Marwyn acabou de entrar e não pode atacar este turno. Passa a vez.',
        allow: Allow.passTurn,
        done: Done.turnOf(bruno),
        hint: 'Toca em "Passar turno".',
      ),
      TStep(
        'A Carla exilou a Marwyn. Devolve-a à **zona de comando** (abre o Exílio, toca nela → **Para a zona de '
        'comando**).',
        run: const [
          Tap(bruno, [krenko], say: 'O Bruno usa o Krenko: cria goblins.'),
          Token(bruno, 'Goblin', '1/1', qty: 2),
          PassTurn(say: 'A vez passa para a Carla.'),
          Cast(carla, swords, say: 'A Carla lança Swords to Plowshares na Marwyn!'),
          MoveCard(0, marwyn, Zone.exile),
          Life(0, 2),
          Tap(carla, [isamaru], say: 'E ataca o Bruno com o Isamaru, o comandante dela.'),
          CommanderHit(carla, bruno, 2),
        ],
        allow: Allow.move(marwyn, Zone.command),
        done: Done.inZone(marwyn, Zone.command),
        hint: 'Toca no Exílio, depois na Marwyn, e escolhe "Para a zona de comando".',
      ),
      const TStep(
        'O Bruno levou 2 de dano de comandante da Carla e está com 4 de vida. A Marwyn voltou sem os '
        'contadores: ao mudar de zona, é como uma carta nova. E agora custa **5** (3 + 2 de taxa).',
        run: [
          PassTurn(say: 'A vez volta para ti.'),
          UntapAll(0),
          Draw(0, 1, 'Desviras tudo e compras uma carta.'),
        ],
      ),
      TStep(
        'O Bruno tem os goblins virados (usou-os) e o Krenko também. Ataca-o com o **Grizzly Bears** e o '
        '**Elvish Warrior**: vira os dois.',
        allow: Allow.tap([bears, warrior]),
        done: Done.all([Done.tapped(bears), Done.tapped(warrior)]),
        hint: 'Vira o Grizzly Bears e o Elvish Warrior.',
      ),
      TStep(
        'Ninguém pode bloquear. São 4 de dano: toca no cartão do **Bruno** e tira-lhe **4 de vida**.',
        allow: Allow.life(bruno),
        done: Done.lifeAtMost(bruno, 0),
        hint: 'Toca no cartão do Bruno e usa o − da vida até chegar a 0.',
      ),
      const TStep(
        'O Bruno saiu do jogo! Ainda tens 5 mana: com o tempo voltas a lançar a Marwyn e vais atrás da Carla.\n\n'
        'Aprendeste: o baralho de 100, a identidade de cor, a zona de comando, a taxa, voltar à zona de '
        'comando, atacar vários jogadores e o dano de comandante. Bons jogos!',
        run: [Concede(bruno, say: 'O Bruno chegou a 0 de vida.')],
      ),
    ],
  ),
];
