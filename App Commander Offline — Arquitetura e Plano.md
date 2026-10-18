# EDHere — Arquitetura e Plano

Oct 17, 2026 · @Júlio Rodrigues

## Visão e princípios

Uma app mobile em Flutter que funciona como mesa de Magic: The Gathering totalmente offline, para construir decks, testá-los e jogar com pessoas ao lado sem internet. A internet só serve para atualizar a base de dados de cartas.

- **Mesa, não motor de regras.** A app gere zonas, vida, contadores, turnos e tokens. As regras ficam a cargo dos jogadores, como numa mesa física.
- **Offline-first.** Pesquisa, deck builder, playtest e multijogador funcionam sem rede. A rede é opcional e só traz atualizações.
- **Multi-formato.** Commander é o foco, mas como as regras são dos jogadores, a mesa serve qualquer formato: Modern, Standard, Pauper, Brawl, Oathbreaker, Two-Headed Giant ou casas próprias. A app só valida a legalidade do deck e adapta os valores iniciais (vida, tamanho do deck, zona de comando).
- **Jogo local entre pessoas presentes.** Um jogador cria a sala na rede local ou no hotspot do telemóvel; os outros entram por QR code ou descoberta automática.
- **Leve e controlável.** O utilizador escolhe que pacotes de imagens descarrega, para não ocupar dezenas de GB.

A app é 100% gratuita e sem servidores próprios: um projeto de um jogador para os jogadores, sem fins lucrativos, mantido apenas por donativos voluntários.

## Nome e identidade visual

A app chama-se **EDHere**: EDH + "here", jogar com quem está aqui. A identidade é moderna, com fundos escuros por defeito, tema claro opcional e azul como cor principal.

### Nome

Escolhido EDHere. As alternativas consideradas ficam registadas:

| Nome | Ideia |
| --- | --- |
| EDHere | EDH + "here": jogar com quem está aqui. Curto e fácil de dizer |
| EDHOff | A proposta original: EDH offline |
| Pod Local | "Pod" é o nome da comunidade para uma mesa de Commander |
| OffPod | Pod offline; mais distintivo que EDHOff |
| Mesa EDH | Português, mas menos internacional |

Regra para qualquer nome e ícone: não usar "Magic", "MTG", "The Gathering", os símbolos de mana oficiais nem o logótipo da Wizards ou do Scryfall. "EDH" e "Commander" são termos da comunidade e do formato. Antes de publicar, confirmar que EDHere está livre na App Store, no Google Play e como domínio.

### Paleta

Azul principal escolhido: **#2F6FEB**, um azul vivo com contraste AA (cerca de 4,6:1) sobre branco. No tema escuro usa-se uma variante mais clara, para manter o contraste sobre fundos quase pretos.

| Papel | Tema escuro | Tema claro |
| --- | --- | --- |
| Primária | #6EA8FF | #2F6FEB |
| Primária forte (botões premidos, seleção) | #2F6FEB | #1E4FB8 |
| Primária suave (destaques, chips) | #16264A | #E3ECFF |
| Fundo | #0B111C | #F5F7FB |
| Superfície (cartões, painéis) | #141C2B | #FFFFFF |
| Superfície elevada (menus, folhas) | #1C2638 | #EEF2F9 |
| Texto | #E6EBF5 | #0F172A |
| Texto secundário | #93A0B8 | #5B6478 |
| Contornos | #26324A | #D5DCE8 |

Notas de design:

- O tema segue o sistema por defeito, com opção manual nas definições. Em Flutter: `ColorScheme.fromSeed(seedColor: Color(0xFF2F6FEB))` para Material 3, ajustado com os valores acima.
- Na mesa, o azul da app pode confundir-se com a cor azul de Magic. As cores das cartas e da identidade de cor aparecem sempre com símbolos de mana desenhados por nós (ou da fonte livre Mana, de Andrew Gioia), nunca só como manchas de cor.
- O destaque (highlight) de cartas na mesa usa a primária; o jogador ativo usa um contorno animado na mesma cor.
- Visual limpo: cantos arredondados, tipografia sem serifa (Inter ou a do sistema) e as imagens das cartas como protagonistas.

## Benchmark: EDHPlay e EDHLAB

Ambos são mesas virtuais sem motor de regras, online e com contas. A nossa diferença é fazer o mesmo sem internet e entre pessoas presentes. O que vale copiar está na última coluna.

| Funcionalidade | EDHPlay | EDHLAB | Na nossa app |
| --- | --- | --- | --- |
| Salas de 2 a 6 jogadores | Sim, 4 por defeito | Até 4 | Core: 2 a 6, local |
| Passar turno (espaço ou botão), destaque do jogador ativo e untap automático | — | Sim | Core |
| Comprar carta manual (sem compra automática) | — | Sim, tecla D | Core, com opção de compra automática |
| Menu de vida por jogador: vida, dano de comandante, veneno, experiência, energia, monarca, "marcar como morto" | — | Sim | Core |
| Dano de comandante desconta na vida | — | Sim | Core |
| Taxa de comandante | — | Sim | Core, automática ao voltar à zona de comando |
| Empilhar cartas e terrenos | — | Sim | Core |
| Tap por duplo clique ou tecla T, configurável | Menu e atalhos | Sim | Core: toque duplo, configurável |
| Tokens com contador de quantidade, separar virados e desvirados | Tokens e contadores | Sim | Core |
| Arrastar carta para o campo de outro jogador (mudar controlo) | Dar carta a outro jogador | Sim | Core |
| Mover para zona (cemitério, exílio, mão, topo ou fundo do grimório) | Menu de contexto | Menu de contexto | Core: menu de toque longo |
| Anexar cartas (equipamentos, auras) | Sim | — | Core |
| Mão inicial com mulligan | Sim | — | Core |
| Registo de eventos (cada carta jogada e virada) | Sim | — | Core |
| Escolher a impressão de cada carta | Sim | — | Nice to have |
| Importar lista colada (Moxfield, Archidekt) | Sim | — | Core |
| Decks iniciais pré-construídos | Sim | — | Nice to have |
| Verificação de legalidade por formato e modo "livre" | Sim | — | Core |
| Playtest com vários lugares controlados por uma pessoa | Sim | Até 4 decks | Core |
| Histórico de jogos e estatísticas | Sim (completo pago) | Não | Nice to have, local |
| Espectadores sem ver zonas ocultas | Sim | — | Nice to have |
| Draft de boosters com bots | Sim | — | Fora do âmbito inicial |
| Chat de texto e voz | Texto, voz via Discord | Texto e voz | Fora: as pessoas estão lado a lado |
| Atalhos reconfiguráveis | Sim | Parcial | Tablet com teclado: nice to have |
| Várias línguas | 8 no site, 7 no texto das cartas | — | PT e EN no início |

"—" significa que as páginas consultadas não falam disso, não que a funcionalidade falte.

Fontes: [EDHPlay: jogar Commander online](https://edhplay.com/play-commander-online), [EDHPlay: alternativa ao Tabletop Simulator](https://edhplay.com/tabletop-simulator-alternative), [EDHPlay: sem webcam](https://edhplay.com/play-commander-without-webcam), [EDHLAB: Anatomy of a Playtest Game](https://blog.edhlab.gg/anatomy-of-a-playtest-game/), [EDHLAB no hunted.space](https://hunted.space/product/edhlab-gg/launches/edhlab-gg), [comparação da Playgroup](https://playgroup.gg/playgroup-live/play-commander-online).

## Funcionalidades

O MVP traz o essencial para jogar uma partida completa sem internet. O resto entra por fases.

### Base de cartas e pesquisa

**Core**

- Pesquisa offline instantânea por nome, com filtros por cor, identidade de cor, tipo, custo de mana, raridade, formato e texto.
- Subconjunto da sintaxe do Scryfall: `t:`, `c:`, `id:`, `o:`, `cmc`/`mv`, `f:`, `r:`.
- Ficha da carta com texto Oracle, legalidades, rulings (se descarregados) e impressões disponíveis.

**Nice to have**

- Pesquisas guardadas.
- Coleção pessoal (as cartas que tenho), com marcação no deck builder.

### Deck builder

**Core**

- Criar deck escolhendo o formato. Em Commander, escolher primeiro o comandante (ou parceiros, background, companheiro).
- Validação por formato: tamanho, singleton, identidade de cor, banidas. Avisos em vez de bloqueios, e um modo "livre" sem validação.
- Categorias (ramp, draw, remoção, terrenos, etc.), sideboard e "maybeboard".
- Importar e exportar lista em texto (compatível com Moxfield, Archidekt e MTGO).
- Estatísticas: curva de mana, distribuição de cores e tipos, fontes de mana por cor.

**Nice to have**

- Escolher a impressão de cada carta.
- Probabilidades: chance de ter X terrenos na mão inicial, ou uma carta até ao turno N.
- Partilhar deck com quem está ao lado (QR code ou pela sala local).
- Versões do deck (histórico de alterações).

### Playtest

**Core**

- Goldfish: mão inicial, mulligan (London e o mulligan grátis de Commander), comprar cartas, jogar sozinho.
- Hot-seat: vários decks meus na mesma mesa, controlados por mim, num só dispositivo.
- Simulador de mão inicial: gerar N mãos seguidas para ver se o deck abre bem.

**Nice to have**

- Modo tablet partilhado: vários jogadores à volta de um tablet, cada um com a sua área rodada para o seu lado.

### Mesa de jogo (local e playtest)

**Core**

- Zonas: grimório, mão, campo de batalha, cemitério, exílio e zona de comando.
- Vida, dano de comandante por adversário (descontado na vida), taxa de comandante automática, veneno, energia, experiência, monarca, iniciativa, "marcar como derrotado".
- Passar turno: destaca o jogador ativo, desvira as cartas dele e, opcionalmente, compra uma carta. Contador de turnos.
- Fases opcionais (manutenção, compra, principal, combate, final), só como indicador visual.
- Gestos na carta: tap e untap (toque duplo), virar face (cartas de duas faces), face para baixo (morph, manifest), contadores (+1/+1, -1/-1, lealdade, genéricos), anexar, mudar controlo, duplicar como token.
- Tokens: pesquisa de tokens oficiais, token personalizado, empilhar com contador de quantidade.
- Ações de grimório: baralhar, comprar N, scry N, surveil N, mill N, procurar carta, revelar o topo, ver o topo X, pôr carta no topo ou no fundo.
- Revelar uma carta ou a mão a todos ou a um jogador.
- Destaques (highlight): tocar numa carta para a destacar a todos, por exemplo para apontar alvos ou anunciar um feitiço. Setas de alvo entre cartas.
- Registo de eventos visível a todos.
- Desfazer a última ação (só as próprias).
- Dados, moeda, escolher jogador ao acaso, primeiro jogador ao acaso.
- Zoom de carta com texto legível.

**Nice to have**

- Day/night, cidade de ouro (city's blessing), emblemas, dungeons.
- Temporizador de turno opcional.
- Planechase e Archenemy (cartas especiais na mesa).
- Histórico de partidas e estatísticas locais: vitórias por deck, duração média, comandante mais jogado.
- Modo espectador.

### Formatos suportados

A mesa é igual para todos os formatos. O formato só muda a validação do deck e os valores iniciais da sala.

| Formato | Vida inicial | Deck | Zona de comando |
| --- | --- | --- | --- |
| Commander | 40 | 100, singleton | Sim |
| Brawl / Historic Brawl | 25 (multijogador 30) | 60 ou 100, singleton | Sim |
| Oathbreaker | 20 | 60, singleton | Sim (planeswalker + feitiço) |
| Modern, Pioneer, Standard, Legacy, Vintage, Pauper | 20 | 60 mínimo + 15 sideboard | Não |
| Livre / casa | Configurável | Sem validação | Opcional |

O anfitrião pode alterar a vida inicial e o número de lugares antes de começar.

## Dados offline

Os dados das cartas vêm do bulk data do Scryfall, convertidos numa base SQLite compacta. As imagens descarregam-se por pacotes que o utilizador escolhe.

### Dados das cartas

O Scryfall gera os ficheiros bulk a cada 12 horas. Para dados de jogo, recomenda descarregar semanalmente ou após cada lançamento de coleção ([bulk data](https://scryfall.com/docs/api/bulk-data)).

| Ficheiro Scryfall | Tamanho | Uso na app |
| --- | --- | --- |
| Oracle Cards | 148 MB | Base principal: uma entrada por carta |
| Default Cards | 462 MB | Não descarregado: impressões alternativas vêm da API quando há rede |
| Rulings | 21,9 MB | Rulings, pacote opcional |
| All Cards | 2,15 GB | Não usar (todas as línguas) |

Tamanhos na página do Scryfall, sujeitos a variação.

Tudo acontece no telemóvel, sem servidor próprio:

1. No primeiro arranque, um assistente pede ligação à internet e mostra os pacotes disponíveis (dados, rulings, imagens) com o tamanho estimado de cada um.
2. A app consulta `GET https://api.scryfall.com/bulk-data` e descarrega o Oracle Cards diretamente do Scryfall.
3. Converte o ficheiro em streaming, num isolate de Dart, para `cards.sqlite`: guarda só os campos necessários e cria o índice FTS5. O JSON nunca fica inteiro em memória e o ficheiro temporário é apagado no fim.
4. Calcula as listas dos pacotes de imagens a partir das legalidades da base local e descarrega as imagens escolhidas.

Sem servidor não há diffs: cada atualização volta a descarregar o Oracle Cards completo. Para compensar, a app compara a data do bulk com a da base local e só descarrega quando há novidade. A conversão tem de ser medida em telemóveis fracos logo na fase 1.

### Pacotes de imagens

O utilizador escolhe o que quer offline. A app mostra o tamanho estimado de cada pacote antes de descarregar.

| Pacote | Conteúdo |
| --- | --- |
| As minhas cartas | Automático: todas as cartas dos meus decks, em resolução normal |
| Commander | Todas as cartas legais em Commander, uma impressão por carta |
| Commander + Modern | O anterior mais as legais em Modern |
| Por formato | Pioneer, Standard, Pauper, Legacy, etc. |
| Tokens e emblemas | Todos os tokens oficiais |
| Tudo | Todas as cartas, uma impressão por carta |

Cada pacote tem duas resoluções: "pequena" (146×204 do Scryfall, para listas e campo de batalha) e "normal" (488×680, para zoom e leitura). Como os formatos se sobrepõem muito, as imagens são guardadas uma vez por carta e os pacotes são só listas. Commander + Modern não duplica nada.

A lista de cada pacote é calculada no próprio telemóvel a partir das legalidades da base local. As imagens descarregam-se diretamente de `cards.scryfall.io`, que não tem o limite de pedidos da API ([guia da API](https://scryfall.com/docs/api)).

Sem imagem descarregada, a carta aparece como "carta de texto": moldura genérica com nome, custo, tipo e texto Oracle. A mesa funciona sempre, mesmo com zero imagens.

### Atualizações

- Verificação automática quando há rede, no máximo uma vez por dia. Descarga só em Wi-Fi, por defeito.
- Em dados móveis, aviso com o tamanho da descarga antes de começar (`connectivity_plus`). Nice to have.
- Base nova primeiro, imagens novas dos pacotes instalados depois, em segundo plano. A base antiga só é substituída quando a nova está pronta.
- Numa sala local, todos os jogadores devem ter a mesma versão da base. Se alguém tiver uma versão anterior e faltar uma carta, o anfitrião envia os dados dessa carta (texto, sem imagem) pela rede local.
- Nice to have: copiar a base e as imagens de outro telemóvel pela rede local, para quem não tem internet nenhuma.

## Multijogador local

O jogo corre por TCP na rede local: Wi-Fi de casa, de uma loja ou o hotspot de um dos telemóveis. Um jogador é anfitrião e ordena todos os eventos. Cada jogador mantém no seu próprio dispositivo as zonas ocultas (mão e grimório). O BLE fica fora do MVP.

### Entrar numa sala

1. **Criar sala.** O anfitrião escolhe formato, lugares e vida inicial. A app abre um `ServerSocket` (dart:io) e anuncia o serviço `_mesa._tcp` por mDNS (pacote `bonsoir`). O anúncio leva nome da sala, formato, lugares livres, versão da app e versão da base de cartas.
2. **Sem rede?** No Android, a app cria um hotspot local (`LocalOnlyHotspot`, Android 8+). No iPhone, o utilizador liga o Hotspot Pessoal manualmente, porque a app não o pode fazer.
3. **QR code.** A app mostra um QR Wi-Fi standard (`WIFI:T:WPA;S:…;P:…;;`) quando criou o hotspot, mais o código da sala. A câmara do iOS e do Android 10+ liga-se à rede só por ler o QR.
4. **Descoberta automática.** Já na mesma rede, a app procura salas por mDNS. Uma sala encontrada: entra com confirmação rápida. Várias: mostra a lista.
5. **Plano B.** Se o mDNS falhar (alguns hotspots bloqueiam multicast), a app tenta ligar-se ao IP do gateway da rede, que num hotspot é o próprio anfitrião. Último recurso: introduzir o IP manualmente.
6. **Lobby.** Cada jogador escolhe o deck, a app valida a legalidade para o formato da sala e o jogador fica "pronto". O anfitrião inicia o jogo.

Um PIN de 4 dígitos opcional impede que estranhos na mesma rede (numa loja, por exemplo) entrem na sala.

### Protocolo de sincronização

- **Transporte:** TCP, mensagens JSON delimitadas por tamanho. MessagePack mais tarde, se necessário.
- **Envelope:** `{v, seq, type, actor, ts, payload}`. `seq` é atribuído pelo anfitrião e define a ordem global.
- **Fluxo:** o cliente envia uma intenção ("mover carta X do campo para o cemitério"). O anfitrião atribui `seq`, guarda no registo e difunde o evento a todos. Cada dispositivo aplica os eventos pela ordem de `seq`.
- **Só IDs:** como todos têm a base de cartas, os eventos levam só IDs de cartas e de instâncias. Mensagens de poucas centenas de bytes.
- **Zonas ocultas:** a mão e a ordem do grimório vivem só no dispositivo do dono. Os outros recebem contagens ("7 cartas na mão"). Quando uma carta passa a pública (jogada, revelada, descartada), o evento leva o ID dela. Baralhar acontece no dispositivo do dono.
- **Ligação:** heartbeat a cada 2 s. Sem resposta durante 10 s, o jogador aparece como desligado e o jogo continua.
- **Reconexão:** o cliente volta com o seu token de jogador e o último `seq` que aplicou. O anfitrião envia os eventos em falta ou um snapshot do estado público.
- **Desfazer:** um evento `undo` referencia o `seq` a anular. O anfitrião só aceita anular ações do próprio jogador, e só a última dele.
- **Anfitrião sai:** no MVP, o jogo pausa e o estado fica guardado em todos. Como cada cliente tem o estado público completo e as suas zonas ocultas, a migração de anfitrião é viável numa fase seguinte.

### Permissões

| Plataforma | Permissão | Para quê |
| --- | --- | --- |
| iOS 14+ | `NSLocalNetworkUsageDescription` + `NSBonjourServices` (`_mesa._tcp`) | Descobrir e ligar a salas na rede local |
| Android 13+ | `NEARBY_WIFI_DEVICES` | Criar o hotspot local |
| Android 10 a 12 | `ACCESS_FINE_LOCATION` | Criar o hotspot local |
| Ambos | Câmara | Ler QR codes |

O primeiro uso do multijogador explica estas permissões antes de as pedir. No iOS, se o utilizador recusar a rede local, a descoberta falha sem erro visível, por isso a app tem de detetar e explicar o problema.

## Stack Flutter e arquitetura

A peça central é um núcleo de jogo em Dart puro, sem Flutter, baseado em eventos. O playtest solo e o multijogador usam exatamente o mesmo núcleo; só muda o transporte (local ou TCP).

### Camadas

1. **UI (Flutter):** ecrãs de pesquisa, deck builder, lobby e mesa. A mesa usa widgets e `CustomPainter` com `InteractiveViewer` para zoom e arrasto. Não é preciso um motor de jogos como o Flame.
2. **Estado (Riverpod):** liga a UI ao núcleo e aos repositórios.
3. **Núcleo de jogo (`mesa_core`, Dart puro):** `GameState` imutável e uma função `apply(state, event) → state`. Sem I/O, 100% testável com testes unitários.
4. **Transporte:** interface `GameTransport` com duas implementações: `LocalTransport` (playtest e hot-seat) e `TcpTransport` (anfitrião ou cliente).
5. **Dados:** `CardRepository` (SQLite só de leitura, substituído nas atualizações), `DeckRepository` (SQLite do utilizador, nunca apagado), `ImageStore` (ficheiros no disco).
6. **Serviços:** atualização de dados, descarga de pacotes de imagens, descoberta de salas, hotspot.

### Pacotes

| Necessidade | Pacote |
| --- | --- |
| Estado | `flutter_riverpod` |
| Base de dados (SQLite + FTS5) | `drift` |
| Modelos imutáveis | `freezed` + `json_serializable` |
| Navegação | `go_router` |
| Sockets TCP | `dart:io` (nativo) |
| Descoberta mDNS | `bonsoir` |
| IP do gateway e da rede | `network_info_plus` |
| Wi-Fi ou dados móveis | `connectivity_plus` |
| Ecrã ligado durante o jogo | `wakelock_plus` |
| Gerar QR | `qr_flutter` |
| Ler QR | `mobile_scanner` |
| Descargas em segundo plano | `background_downloader` |
| Donativos pelas lojas | `in_app_purchase` |
| Hotspot Android | Platform channel próprio em Kotlin (`LocalOnlyHotspot`) |
| Ligar a Wi-Fi a partir da app (fase posterior) | Platform channels: `NEHotspotConfiguration` (iOS), `WifiNetworkSpecifier` (Android) |

### Estrutura do repositório

- `packages/mesa_core`: núcleo de jogo, eventos, estado. Dart puro.
- `packages/mesa_protocol`: envelope, serialização e versões do protocolo.
- `packages/card_db`: esquema drift, parser da sintaxe de pesquisa, validação de formatos.
- `packages/card_import`: importador do bulk do Scryfall em streaming e cálculo das listas dos pacotes de imagens. Corre no telemóvel, num isolate.
- `app/`: a aplicação Flutter.

Não há servidor nem backend: a app fala diretamente com o Scryfall para dados e imagens, e com os outros telemóveis pela rede local.

## Modelo de dados

Há duas bases separadas: a de cartas, só de leitura e substituível, e a do utilizador, que nunca é apagada nas atualizações. O estado de jogo vive em memória e é guardado como snapshot mais registo de eventos.

### `cards.sqlite` (gerada pelo servidor)

| Tabela | Campos principais |
| --- | --- |
| `cards` | `oracle_id` (PK), `name`, `mana_cost`, `mv`, `type_line`, `oracle_text`, `power`, `toughness`, `loyalty`, `colors`, `color_identity`, `layout`, `keywords`, `default_print_id` |
| `card_faces` | `oracle_id`, `face_index`, `name`, `mana_cost`, `type_line`, `oracle_text`, `power`, `toughness` |
| `prints` | `print_id` (PK, ID Scryfall), `oracle_id`, `set_code`, `collector_number`, `lang`, `artist`, `img_small_url`, `img_normal_url`, `released_at` |
| `legalities` | `oracle_id`, `format`, `status` (legal, banned, restricted, not\_legal) |
| `tokens` | `print_id`, `name`, `type_line`, `oracle_text`, `power`, `toughness`, `colors` |
| `rulings` | `oracle_id`, `published_at`, `comment` (pacote opcional) |
| `cards_fts` | Índice FTS5 sobre nome, tipo e texto |
| `meta` | `db_version`, `generated_at`, `scryfall_bulk_date` |

Os pacotes de imagens não são tabelas: são consultas sobre `legalities` (por exemplo, "legal em commander OU legal em modern") que o servidor resolve em listas de URLs no manifesto.

### `user.sqlite` (no dispositivo)

| Tabela | Campos principais |
| --- | --- |
| `decks` | `id`, `name`, `format`, `commander_ids`, `notes`, `created_at`, `updated_at` |
| `deck_cards` | `deck_id`, `oracle_id`, `print_id` (opcional), `qty`, `board` (main, side, maybe, command), `category` |
| `deck_versions` | `deck_id`, `version`, `snapshot_json`, `created_at` (nice to have) |
| `collection` | `print_id`, `qty`, `foil` (nice to have) |
| `image_cache` | `print_id`, `size` (small, normal), `path`, `bytes` |
| `installed_packs` | `pack_id`, `resolution`, `installed_at`, `db_version` |
| `games` | `id`, `format`, `players_json`, `winner`, `turns`, `duration_s`, `played_at` |
| `settings` | chave e valor |

### Estado de jogo (`mesa_core`)

- `GameState`: `gameId`, `format`, `players`, `turn`, `activePlayer`, `phase`, `seq`, `log`.
- `PlayerState`: `seat`, `name`, `life`, `commanderDamage` (por comandante adversário), `commanderTax`, `poison`, `energy`, `experience`, `isMonarch`, `hasInitiative`, `defeated`, contagens de mão e grimório.
- `CardInstance`: `instanceId` (único na partida), `oracleId`, `printId`, `owner`, `controller`, `zone`, `tapped`, `faceDown`, `faceIndex`, `counters`, `attachedTo`, `position` (x, y no campo), `stackQty` (para tokens), `isToken`.
- Zonas públicas no estado partilhado; mão e grimório só no estado privado do dono.

### Tipos de evento

| Grupo | Eventos |
| --- | --- |
| Sala | `join`, `leave`, `deck_selected`, `ready`, `start_game`, `heartbeat` |
| Turno | `pass_turn`, `set_phase`, `untap_all` |
| Cartas | `move`, `tap`, `untap`, `flip`, `face_down`, `attach`, `detach`, `change_control`, `set_position` |
| Contadores | `add_counter`, `remove_counter`, `create_token`, `set_token_qty` |
| Jogador | `set_life`, `commander_damage`, `set_player_counter`, `set_monarch`, `set_initiative`, `concede` |
| Grimório e mão | `draw`, `shuffle`, `mill`, `reveal`, `scry_done`, `search_done`, `mulligan` |
| Mesa | `highlight`, `target_arrow`, `roll_die`, `flip_coin`, `undo`, `chat_emote` |

`scry_done` e `search_done` só publicam o resultado visível (por exemplo, "pôs 1 no fundo"). A escolha acontece no dispositivo do dono.

## Fases e roadmap do MVP

A fase 0 é um protótipo de rede só para validar o maior risco antes de qualquer interface. O MVP fecha na fase 3, com jogo local completo.

&#91;embedded content: roadmap · 5 fases, 4 gates\]

Cada fase só avança quando o seu gate é cumprido. O núcleo de jogo (mesa\_core) não depende da UI, por isso o trabalho nele pode começar ainda durante a fase 1.

## Riscos, questões legais e decisões

O maior risco técnico é a rede local entre iOS e Android; o maior risco legal é a forma como distribuímos dados e imagens do Scryfall. Ambos se mitigam cedo com um protótipo e com as regras abaixo.

### Riscos técnicos

| Risco | Mitigação |
| --- | --- |
| mDNS bloqueado em alguns hotspots ou routers | Fallback para o IP do gateway e IP manual; testar cedo em vários telemóveis |
| Permissão de rede local recusada no iOS | Ecrã explicativo antes do pedido; detetar a falha e mandar para as Definições |
| Hotspot Pessoal do iPhone indisponível (operadora, sem dados) | Recomendar que um Android seja anfitrião, ou usar um router |
| Telemóvel do anfitrião bloqueia o ecrã e o SO corta a rede | Manter o ecrã ligado durante o jogo (`wakelock_plus`); reconexão automática |
| Mesa ilegível em ecrãs pequenos com 4 a 6 jogadores | Vista "o meu campo" mais miniaturas dos adversários; tocar num adversário para ver o campo dele; modo tablet |
| Base de cartas diferente entre jogadores | Versão no anúncio da sala; anfitrião envia os dados em falta |
| Batota (app modificada) | Aceitável para jogo casual entre amigos; as zonas ocultas ficam no dispositivo de cada um |

### Regras do Scryfall e da Wizards

Segundo o [guia da API do Scryfall](https://scryfall.com/docs/api):

- Não se pode cobrar acesso aos dados nem exigir pagamento, subscrição ou conta paga para os ver.
- As imagens não podem ser cortadas, distorcidas, recoloridas nem levar marcas d'água; o nome do artista e o copyright têm de ficar visíveis. Se usarmos recortes de arte, o artista e o copyright aparecem noutro sítio do mesmo ecrã.
- Não se pode usar o logótipo do Scryfall nem sugerir que apoiam o projeto.
- Não se pode simplesmente reempacotar os dados: a app tem de acrescentar valor (e acrescenta).
- Cache de pelo menos 24 horas e uso do bulk data para descargas completas.

A [Fan Content Policy da Wizards](https://company.wizards.com/en/legal/fancontentpolicy) exige que o conteúdo seja gratuito: sem pagamentos, subscrições nem registo obrigatório. Permite recuperar custos com donativos (dá o Patreon como exemplo), desde que não limitem o acesso. Não permite vender o conteúdo nem usar logótipos ou marcas da Wizards sem autorização. A app deve mostrar no ecrã "Sobre" o aviso de conteúdo de fã não oficial que a política pede.

### Gratuita, com donativos

A app é 100% gratuita: sem anúncios, sem funcionalidades pagas, sem conta. O único extra é um ecrã "Apoiar o projeto" nas definições e um botão discreto no ecrã inicial. As lojas limitam como se recebem donativos:

- **Google Play:** aceita links de donativo dentro da app só quando o destinatário é uma organização isenta de impostos. Em 2026, o AnkiDroid teve atualizações bloqueadas por causa de um link para o Open Collective ([Gigazine](https://gigazine.net/gsc_news/en/20260902-ankidroid-google-play-policy-violation/)).
- **App Store:** a Apple tem rejeitado links externos de gorjeta (por exemplo, "Buy Me a Coffee") e pede que as gorjetas passem por compra integrada ([fórum de programadores da Apple](https://developer.apple.com/forums/thread/844046)).

Solução proposta:

- **Dentro da app:** gorjetas como compras integradas consumíveis (por exemplo, 1, 3 e 5 €), que não desbloqueiam nada. As lojas ficam com uma comissão, mas é o caminho que as duas aceitam.
- **Fora da app:** link direto para Ko-fi ou GitHub Sponsors no site do projeto e no repositório, sem comissão das lojas.
- **F-Droid:** se o código for aberto, publicar também no F-Droid, que aceita links de donativo e chega a quem instala apps sem a Play Store.
- Doar precisa de internet, mas o resto da app continua totalmente offline.

### Decisões

| Tema | Decisão | Estado |
| --- | --- | --- |
| Nome | EDHere (confirmar disponibilidade nas lojas e domínio) | Decidido |
| Servidor | Nenhum. Importação do Scryfall e cálculo dos pacotes no telemóvel | Decidido |
| Base de cartas | Descarregada no primeiro arranque, com escolha de pacotes. Aviso em dados móveis como nice to have | Decidido |
| Modelo | 100% gratuita; só donativos (gorjetas pelas lojas dentro da app, Ko-fi ou GitHub Sponsors fora) | Decidido |
| Identidade | Moderna, tema escuro por defeito e claro opcional, azul #2F6FEB | Decidido |
| Versões mínimas | Android 10+ (API 29) e iOS 15+ | Decidido |
| Código | Open source, licença MPL-2.0 | Decidido |
| Contas e cloud | Fora do âmbito; backup e restauro por ficheiro | Decidido |
| Modo tablet partilhado | Fase 4; o hot-seat num dispositivo fica no MVP | Decidido |

**Versões mínimas.** O Flutter já exige Android 7 (API 24) e iOS 15 ([plataformas suportadas](https://docs.flutter.dev/reference/supported-platforms)). Android 10 é a melhor base: traz o `WifiNetworkSpecifier` e a leitura nativa de QR Wi-Fi na câmara, e evita os casos especiais de armazenamento e localização das versões anteriores. No iOS, a própria exigência do Flutter (15+) chega para tudo o que usamos: permissão de rede local (iOS 14+) e `NEHotspotConfiguration` (iOS 11+).

**Open source.** Encaixa num projeto gratuito "de jogadores para jogadores": a comunidade pode traduzir, acrescentar formatos e confirmar que a app não faz nada escondido na rede local. Abre também a porta ao F-Droid. A MPL-2.0 protege as alterações aos ficheiros do projeto sem os conflitos conhecidos entre a GPL e os termos da App Store. O risco são clones com anúncios, mas a política da Wizards já obriga a que o conteúdo seja gratuito.

**Contas e cloud.** Sem servidores, contas só trariam custos. A alternativa é exportar um backup (decks, coleção, histórico) para um ficheiro e partilhá-lo pelo menu do sistema: Drive, iCloud, email. No futuro pode haver sincronização pela cloud do próprio utilizador, sem servidor nosso.

**Modo tablet.** O MVP já tem vários lugares num dispositivo (hot-seat). Um tablet partilhado obriga a uma mesa rodada para cada lado e mais testes de interface, por isso fica para a fase 4. A mesa deve ser desenhada desde o início para suportar essa rotação.
