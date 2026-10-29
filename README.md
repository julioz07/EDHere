<p align="center">
  <img src="assets/logo/edhere-logo-svg/edhere-logo-vertical-dark.svg" alt="EDHere" width="200">
</p>

<p align="center"><strong>Joga com quem está aqui.</strong><br>
Uma mesa de Magic: The Gathering totalmente offline, para construir decks, testá-los e jogar com quem está ao teu lado — sem internet, sem contas, sem servidores.</p>

---

**Versão atual: 1.9.1** (Android). Os APKs são por arquitetura: `arm64` para quase todos os telemóveis atuais, `armv7` para os mais antigos, `universal` se tiveres dúvidas.

## O que é

O EDHere é uma app Flutter (Android; iOS preparado) que funciona como **mesa de jogo, não como motor de regras**: gere zonas, vida, contadores, turnos e tokens, e as regras ficam a cargo dos jogadores, como numa mesa física. O foco é **Commander/EDH**, mas a mesa serve qualquer formato.

A exceção é **jogar contra o bot**: aí as regras são aplicadas pelo motor do [Forge](https://github.com/Card-Forge/forge), que vem dentro da app e também é quem joga do outro lado.

A internet só é usada para descarregar a base de cartas e as imagens (do [Scryfall](https://scryfall.com)). Tudo o resto funciona em modo avião.

## Funcionalidades

**Contra o bot** (Android 8.0 ou mais recente)
- Partida 1 contra 1 com as regras completas, sem internet: o motor do [Forge](https://github.com/Card-Forge/forge) aplica as regras e joga do outro lado, na mesa do EDHere (imagens, cartas e língua da app).
- Três dificuldades: fácil (o bot comete erros de propósito), normal e difícil (pensa mais em cada jogada e tem melhor mana).
- Commander ou outro formato, com os teus decks; antes de começar avisa se o motor ainda não conhecer alguma carta.
- Tocar numa carta joga-a (as que se podem jogar ficam destacadas), tocar sem largar abre a ficha; as perguntas do jogo (alvos, custos opcionais, ordem dos gatilhos, dividir dano) aparecem como diálogos. Também dá para ver o bot a jogar contra outro bot.

**Cartas e decks**
- Base de cartas offline (~36 mil cartas, ~25 MB a descarregar) com pesquisa instantânea e sintaxe parecida com a do Scryfall (`t:dragon id:rg mv<=3`, `f:commander`, `is:commander`…).
- Deck builder com validação por formato (tamanho, singleton, banidas, identidade de cor, parceiros e backgrounds), vista em lista ou grelha, estatísticas, simulador de mão inicial.
- Importar e exportar listas (Moxfield, Archidekt, MTGO, Arena), com as versões das cartas quando a lista as traz, e partilhar decks por QR code.
- Versões alternativas das cartas: escolher a arte por entrada de deck ou como preferida em todo o lado; só se descarrega a imagem escolhida.
- As minhas cartas: coleção indicativa (importação do ManaBox, Moxfield, Deckbox, Dragon Shield ou texto), filtro "só as que tenho" ao construir decks e, em cada carta, em que decks está.
- Pacotes de imagens à escolha (Commander, Modern, tokens…), em resolução pequena ou normal.
- Backup num ficheiro: decks, coleção, histórico e versões escolhidas, guardado onde quiseres (Google Drive, PC, cartão) ou enviado a alguém; ao importar, junta ao que já existe sem duplicar. Também dá para exportar um só deck para o partilhar.

**Boosters (sealed, draft e JumpStart)**
- Draft na rede local: o anfitrião escolhe o set (ou um cubo), quantos boosters, tirar 1 ou 2 cartas de cada vez (Pick-Two), tempo por escolha e quantos lugares; os lugares vazios ficam com bots. Os packs passam à esquerda, à direita e à esquerda, e cada jogador só vê o seu. No fim cada um monta o deck de 40 e joga na mesma sala.
- Commander draft (Commander Legends, Baldur's Gate, Commander Masters, Mystery Booster Commander): Pick-Two, comandante escolhido entre as lendas tiradas (ou The Prismatic Piper / Faceless One), deck de 60 sem singleton, vida 40.
- Sealed: abrir boosters de qualquer um dos ~170 sets com boosters (de 1993 até hoje), com a composição real de cada set, ou packs de um cubo próprio; montar um deck de 40 com a pool (o resto fica no sideboard).
- JumpStart: escolher 2 de 570 pacotes temáticos vendo só o tema e a carta de destaque; os dois juntos fazem o deck de 40.
- Montar o deck com a pool: filtros por cor, ordenar por cor, custo ou tipo, terrenos sugeridos pelos símbolos de mana. O que fica a meio é guardado ("Decks por montar") e continua-se depois.
- Os dados vêm dentro da app (funcionam sem internet); só as imagens se descarregam, e dá para descarregar as de um set antes de jogar sem rede.

**Aprender a jogar Commander**
- Tutorial guiado contra dois adversários simulados, com jogadas fechadas: lês um pouco, jogas um pouco, e a mesa só deixa fazer o passo pedido (explica quando te enganas).
- Duas versões: "Já sei jogar Magic" (só o que o Commander tem de especial: baralho de 100, identidade de cor, zona de comando, taxa, dano de comandante, jogo a vários, brackets) e "Nunca joguei" (cartas, mana, turno, combate e a pilha primeiro).
- Pratica-se mesmo: mulligan, bloquear, responder a um feitiço na vez dos outros e cadeias de respostas na pilha.
- Os tipos de carta a fundo (equipamentos, auras, veículos…) e um capítulo sobre planeswalkers e lealdade.
- Termina com um jogo curto que junta tudo; progresso guardado e glossário de termos.

**Mesa**
- Goldfish, 1 contra 1 no mesmo dispositivo (mesa partilhada frente a frente, mãos abertas para ensinar). Grava-se sozinho: ao sair pergunta se fica gravado e continua-se depois, mesmo que a app feche.
- Tap, contadores editáveis (+1/+1, lealdade, modificadores de poder/resistência), habilidades dadas por efeitos, tokens, anexar, mudar controlo, virar face, alvos em cartas ou jogadores.
- Planeswalkers: entram com a lealdade inicial e as habilidades de lealdade (+1, −2…) usam-se no menu da carta, que soma ou tira a lealdade e escreve no registo.
- Grimório: comprar, baralhar, scry, surveil, mill, procurar, revelar, mulligan London.
- Vida, dano de comandante, veneno, energia, monarca, iniciativa, taxa de comandante automática.
- Registo de eventos, desfazer, dados e moeda, histórico de jogos e estatísticas.

**Multijogador local**
- Um jogador cria a sala na rede Wi-Fi ou num hotspot criado pela app; os outros entram por descoberta automática (mDNS), QR code ou IP.
- A mão e o grimório de cada jogador nunca saem do telemóvel dele.
- Religação automática a meio do jogo; se a app fechar, volta-se ao jogo com a mão e o grimório como estavam.
- Imagens em falta (por exemplo, versões alternativas de outro jogador) podem vir da internet ou do próprio dispositivo desse jogador, pela rede local.

**Línguas**
- A app em português, inglês, espanhol e italiano. Na primeira abertura fica na língua do telemóvel (inglês se for outra); muda-se nas Definições ou na introdução.
- As cartas também: nas Definições (ou antes do primeiro download) escolhe-se a língua das cartas, e a app descarrega do Scryfall o nome, o tipo, o texto e a imagem de cada carta nessa língua (~20 MB; as que não existem nessa língua ficam em inglês). A pesquisa encontra a carta pelo nome nas duas línguas; listas, exportações e regras continuam com o nome Oracle (inglês).
- O registo do jogo e as mensagens de validação seguem a língua de cada telemóvel.

**Primeira abertura**
- Introdução em 4 ecrãs: o que é a app, decks e boosters, jogar juntos e aprender, e porque é preciso descarregar a base de cartas. O último ecrã arranca o download.

**Definições**
- Tema claro, escuro ou do sistema; fundo da área de jogo (5 incluídos ou da galeria); tamanho das cartas; gestão dos dados offline.

## Estrutura

| Pasta | Conteúdo |
| --- | --- |
| `packages/mesa_core` | Núcleo de jogo em Dart puro: estado da mesa, eventos, zonas ocultas, desfazer |
| `packages/mesa_protocol` | Envelope dos eventos e enquadramento TCP |
| `packages/card_db` | Importação do Scryfall, pesquisa, decks, validação, listas em texto, versões (SQLite) |
| `lib/net` | Sala: anfitrião TCP, cliente com religação, mensagens diretas, mDNS, hotspot, QR |
| `lib/data` | Descargas, imagens, versões, boosters, decks por montar, definições, providers (Riverpod) |
| `lib/l10n` | Línguas: `tr()` e as traduções geradas (`strings_*.g.dart`) |
| `tool/l10n` | Traduções (`src/*.json`) e ferramentas: `extract.py` recolhe as frases, `build.py` gera as tabelas e diz o que falta |
| `lib/game` | `GameController` (núcleo ↔ UI), `NetworkGame` (lobby e jogo em rede), draft, jogos gravados |
| `lib/ui` | Ecrãs |
| `android/.../MainActivity.kt` | Hotspot local (`LocalOnlyHotspot`), orientação, partilha e o canal do bot, por platform channels |
| `android/.../forge/` | Ponte para o motor do Forge (Java): arranque sem interface, partidas, estado da mesa, perguntas e toques |
| `lib/bot` | Lado Flutter do bot: canal com o motor e estado da mesa vindo do Forge |
| `tool/forge` | `build_forge.py`: compila o Forge num commit fixo e gera os jars e os dados que vão na app |
| `tool/` | Geradores (glifos da fonte Mana, ícones da app, dados de boosters) |
| `assets/boosters` | Composição dos boosters por set e pacotes JumpStart (gerados do MTGJSON) |

O plano completo do projeto está em [`App Commander Offline — Arquitetura e Plano.md`](App%20Commander%20Offline%20—%20Arquitetura%20e%20Plano.md).

## Compilar

Requisitos: Flutter 3.24 (Dart 3.5), Android SDK 35, JDK 17+ (o do Android Studio serve) e, para o motor do bot, Maven e git.

```sh
python tool/forge/build_forge.py              # motor do Forge (uma vez, ou ao mudar o commit fixado)
flutter pub get
flutter run                                   # num dispositivo ou emulador
flutter build apk --release --split-per-abi   # APKs por arquitetura
```

## Versões

O número segue `MAIOR.MENOR.CORREÇÃO` (em `pubspec.yaml`, com o número de build depois do `+`, e em `appVersion`, `lib/net/discovery.dart`). Na sala, quem tiver uma versão diferente da do anfitrião vê-a indicada ao entrar.

| Versão | O que trouxe |
| --- | --- |
| 1.9.1 | Jogar contra até 4 bots em Commander: separadores com uma cor por jogador, o tabuleiro de quem ataca ou responde em foco, e o bot mostra o que está a pensar (cartas e alvos a brilhar na cor dele). Visual novo: menu Jogar com modos em cartões, lista de decks com o comandante, três vistas no editor, cores por jogador nas mesas. Estatísticas do deck com rampa, compra, remoção, limpezas e tutores e a probabilidade na mão inicial; o bracket mostra tutores e combos famosos. Mesa partilhada: manter premido muda a vida em 10, com o total das mudanças. Bots com deck aleatório, picks de draft melhores, avisos de derrota (0 de vida, 10 de veneno, 21 de dano de comandante). Textos do Forge traduzidos e muitas correções em ecrãs pequenos |
| 1.8.1 | Jogo contra o bot: custos de mana com símbolos no pagamento, na pilha e nos diálogos; quem ataca já não se deita (avança como no Arena); as escolhas entre efeitos são botões |
| 1.8.0 | Jogo contra o bot com mais vida: cartas a voar entre zonas, setas de ataque e bloqueio, destaque da carta do bot, pilha com mini-cartas, tremor e flash no dano, sons e vibração, barra das fases, vida animada, indicador do bot a pensar, mão em leque, moeda e mulligan em grande, ecrã de fim com gráfico da vida e revanche. Atacar e bloquear a arrastar, paragens por fase e controlo total, velocidade do bot, Desfazer em botão próprio |
| 1.7.0 | Jogar contra o bot: partida 1 contra 1 com as regras completas pelo motor do Forge (GPL-3.0), dentro da app e sem internet, com três dificuldades; ver o bot a jogar contra outro bot. O código do EDHere passa a ser aberto, sob a GPL-3.0 |
| 1.6.0 | Partida de teste de 2 a 6 jogadores no mesmo aparelho (controlas todos; ao passar o turno a mesa mostra o seguinte). Mesa partilhada: o ecrã deixa de rodar, os menus e detalhes das cartas abrem virados para quem tocou e na metade dele, e o botão "Token" tem texto. Editor de decks: seleção de várias cartas (toque longo) para mover (incluindo para comandante), mudar a categoria ou remover, com desfazer; importar uma lista para um deck que já existe (juntar ou substituir). Importação: "Commander" seguido do resto sem cabeçalho já não põe tudo como comandante |
| 1.5.0 | Pronta para a Play Store: identificador `com.juliocr.edhere` (instala-se ao lado da app antiga; passa os decks por backup), assinatura com a chave de upload, Android 16 (targetSdk 36). Ficha da loja, imagens e política de privacidade em `docs/play-store/` |
| 1.4.3 | Telemóveis pequenos (testado em 360×640 dp e com letra a 130%): no lobby, "Escolher deck", "Estou pronto" e "Começar" ficam fixos em baixo; "Abrir sala", "Começar" (1 contra 1), "Abrir boosters" e "Verificar/Importar" ficam sempre à vista, mesmo com o teclado; na mesa, a mão, as zonas e os jogadores encolhem para o campo caber, e a letra da mesa só cresce até 115%; o guia do tutorial tem altura limitada e o "Continuar" sobe para o título; cartões de jogo gravado e de pools com os botões por baixo do texto; editor de decks com o nome inteiro, miniaturas menores e separadores que não transbordam; introdução com os pontos todos à vista; tipo das cartas traduzido nas listas do deck; texto do draft "N jogadores e M bots" traduzido |
| 1.4.2 | Ronda de QA: cartas traduzidas com o tipo e o texto da impressão mais completa (ex.: Relámpago passa a "Instantáneo"); a pesquisa ordena pelo nome traduzido e põe primeiro o nome igual ou que começa pelo texto; nomes traduzidos na lista de decks, no lobby, nas mensagens de validação e na mesa; plurais certos com 1 (lugar livre, aviso, mão simulada…); escolher como comandante uma carta que já está no deck move-a em vez de a duplicar; quem atualiza da 1.3 fica em português e com as cartas em inglês |
| 1.4.1 | Introdução com imagens da app em cada língua; traduções que faltavam (raridade, secções do deck, apagar imagens, estatísticas, draft); a mão inicial cabe no ecrã do tablet ao deitado; downloads da língua das cartas mais cuidadosos com o Scryfall (2 pedidos de cada vez, esperas em caso de 429) |
| 1.4.0 | Línguas: app em português, inglês, espanhol e italiano (deteta a do telemóvel; inglês por defeito), seletor nas Definições e na introdução; cartas na língua escolhida (nome, texto e imagem do Scryfall), com pesquisa pelos dois nomes. Planeswalkers mostram as habilidades na língua das cartas |
| 1.3.0 | Tutorial: capítulos "Os tipos de carta a fundo" (instantâneo e feitiço, artefactos, equipamentos com prática de Equip, veículos, encantamentos, auras, sagas, lendários) e "Planeswalkers e lealdade" (com jogo); glossário maior. Mesa: os planeswalkers entram com a lealdade inicial e as habilidades +N/−N usam-se no menu da carta, com registo. Brief da landing page em `docs/` |
| 1.2.1 | Tutorial: os custos ({1}{G}, {T}…) aparecem como símbolos de mana; a vez dos adversários vai mais devagar (cerca de 3,5 s por jogada) e o guia mostra a lista do que fizeram |
| 1.2.0 | Introdução na primeira abertura (4 ecrãs com prints da app) que acaba no download da base de cartas; "Ver a introdução" nas Definições. O pacote "As minhas cartas" e a importação de backups descarregam as versões escolhidas nos decks |
| 1.1.1 | Tutorial: bloquear, responder na vez dos outros e cadeias; mulligan de treino; cartas a tocar destacadas; correções de QA. Bracket deteta turnos extra e destruição de terrenos em massa |
| 1.1.0 | Aprender a jogar Commander: tutorial guiado com duas versões, adversários simulados e glossário; Vehicles e Spacecraft lendários como comandantes |
| 1.0.3 | Espaço entre os cartões na lista de decks do Goldfish e nos avisos da sala |
| 1.0.2 | Terrenos anexados uns aos outros viram (tap) todos juntos; "Virar só esta" para virar um |
| 1.0.1 | Importar listas mantém as versões das cartas ("(SET) número" do Moxfield/Archidekt); exportar também as inclui |
| 1.0.0 | Primeira versão estável: tudo o que está acima |
| 0.13 | Segunda ronda de QA: decks por montar, imagens por set, melhorias no sealed, draft e JumpStart |
| 0.12 | Backup em ficheiro; gravar jogo solo |
| 0.9–0.11 | Sealed, cubo, JumpStart, draft em rede, Commander draft, símbolos dos sets |
| 0.1–0.8 | Base de cartas, decks, mesa, rede local, coleção, tablet, primeira ronda de QA |

## Testes

```sh
flutter test                              # rede, lobby, jogo em rede e partilha de imagens (loopback)
cd packages/mesa_core && dart test        # núcleo de jogo
cd packages/card_db && dart test          # base de cartas, pesquisa, validação, decks
cd packages/mesa_protocol && dart test    # protocolo
```

No Windows, os testes do `card_db` usam a `sqlite3.dll` do Python (ou a indicada em `SQLITE3_DLL`). Para testar a importação real do Scryfall:
`EDHERE_ORACLE=caminho/oracle-cards.jsonl.gz dart test test/real_bulk_test.dart`.

Ferramentas:
- `python -I tool/gen_mana_glyphs.py mana.css` — volta a gerar o mapa de glifos da fonte Mana.
- `flutter test tool/icons/render_icons_test.dart` — volta a gerar os ícones Android a partir do logótipo.
- `python tool/boosters/build_boosters.py` — volta a gerar os dados de boosters e JumpStart a partir do MTGJSON (correr quando sai um set novo; a cache fica em `tool/boosters/.cache`).

## Aviso legal e créditos

EDHere é **conteúdo de fãs não oficial**, permitido pela [Fan Content Policy](https://company.wizards.com/en/legal/fancontentpolicy). Não é aprovado nem endossado pela Wizards. Partes dos materiais usados são propriedade da Wizards of the Coast. ©Wizards of the Coast LLC.

- Dados e imagens das cartas: [Scryfall](https://scryfall.com), descarregados diretamente para o dispositivo de cada utilizador. O EDHere não é produzido nem apoiado pelo Scryfall.
- Composição dos boosters e pacotes JumpStart: [MTGJSON](https://mtgjson.com) (licença MIT).
- Símbolos dos sets: fonte [Keyrune](https://github.com/andrewgioia/keyrune), de Andrew Gioia (SIL OFL 1.1; licença em `assets/licenses/keyrune_LICENSE.md`). Para sets novos: atualizar `assets/fonts/keyrune.ttf` e correr `python -I tool/gen_keyrune_glyphs.py keyrune.css`.
- Símbolos de mana, contadores e habilidades: fonte [Mana](https://github.com/andrewgioia/mana), de Andrew Gioia (SIL OFL 1.1; licença em `assets/licenses/mana_OFL.txt`).
- Motor de regras e bot: [Forge](https://github.com/Card-Forge/forge) (GPL-3.0); o código vem sem alterações, no commit que está em `tool/forge/build_forge.py`. Os dados levam correções nossas, em `tool/forge/overrides`: traduções e dicas para a IA em alguns guiões de cartas.
- Dicas para a IA do Forge em guiões de cartas (`tool/forge/overrides/cards`): do [Grimório](https://github.com/hubertdungen/grimorio), de @hubertdungen (GPL-3.0).

A app é e será **100% gratuita**: sem anúncios, sem funcionalidades pagas, sem contas.

## Licença

O código do EDHere é software livre, sob a [GNU General Public License v3.0](LICENSE) (a mesma do Forge, que vem dentro da app): podes usá-lo, estudá-lo, alterá-lo e redistribuí-lo nos termos dessa licença.

O nome **EDHere** e o logótipo não fazem parte da licença: versões alteradas têm de usar outro nome e outro logótipo. Sugestões e contribuições são bem-vindas.
