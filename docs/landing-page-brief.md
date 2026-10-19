# EDHere — brief para a landing page

Documento para preparar a landing page do EDHere. A página tem quatro objetivos:

1. Apresentar a app.
2. Explicar como funciona e o que faz.
3. Levar as pessoas a entrar no **open beta** (Android).
4. Pedir **apoio ao projeto** através de doações, incluindo para financiar a versão **iOS**.

---

## 1. O produto num parágrafo

O **EDHere** é uma mesa de Magic: The Gathering no telemóvel, **totalmente offline**. Com ele constróis decks, testas decks e jogas com quem está ao teu lado, sem internet, sem contas e sem servidores. Cada jogador usa o seu telemóvel, e a mão de cada um nunca sai do seu aparelho. O foco é o **Commander (EDH)**, mas a mesa serve para qualquer formato. A app também inclui boosters (sealed, draft e JumpStart) e um tutorial que ensina a jogar Commander do zero.

- **Slogan atual:** "Joga com quem está aqui."
- **Preço:** 100% gratuito. Sem anúncios, sem compras na app e sem contas.
- **Plataforma:** Android já disponível em beta. O iOS está preparado no código, mas falta financiamento para o lançar (ver secção 6).

## 2. Público

- Grupos de amigos que jogam Commander à mesa e querem tirar partido do telemóvel: vida, contadores, dano de comandante, tokens…
- Jogadores que querem testar decks em qualquer lado, incluindo no avião, no comboio ou sem rede.
- Quem quer abrir boosters e fazer drafts com amigos sem gastar dinheiro em cartas.
- Quem nunca jogou Magic e quer aprender (há um tutorial guiado).

## 3. Tom e estilo

- Tom próximo e direto, de jogador para jogador. Nada de corporativo.
- A ideia central é **"uma mesa, não um árbitro"**: a app guarda o estado do jogo e os jogadores aplicam as regras, como numa mesa física. Isto é uma característica do produto, não uma limitação.
- Mensagens-chave a repetir: **offline**, **gratuito**, **joga com quem está ao teu lado**, **a tua mão fica no teu telemóvel**.

## 4. Identidade visual

Os logótipos (SVG) estão em `assets/logo/edhere-logo-svg/` no repositório:

- horizontal e vertical, nas versões `dark`, `light` e `white`;
- o símbolo sozinho, normal e simplificado.

Cores da app:

| Uso | Escuro | Claro |
| --- | --- | --- |
| Primária | `#6EA8FF` | `#2F6FEB` |
| Primária forte | `#2F6FEB` | `#1E4FB8` |
| Primária suave | `#16264A` | `#E3ECFF` |
| Fundo | `#0B111C` | `#F5F7FB` |
| Superfície | `#141C2B` / `#1C2638` | `#FFFFFF` |
| Texto | `#E6EBF5` | — |
| Texto secundário | `#93A0B8` | — |
| Contorno | `#26324A` | — |

- **Recomendação:** a página em tema escuro, a puxar para uma mesa de jogo à noite, com o azul como cor de destaque.
- **Ícones de mana:** a app usa os símbolos da fonte [Mana](https://github.com/andrewgioia/mana) (SIL OFL), que podem ser usados como elementos decorativos.
- **Screenshots:** vão ficar no NAS, em `\\UG-JRZ07\Desenvolvimento\EDHere\Screenshots`, com versões de telemóvel e de tablet. Até lá, usar espaços reservados. Na app já existem três prints em `assets/onboarding/`: `table.jpg` (a mesa), `deck.jpg` (um deck) e `room.jpg` (a sala multijogador).

## 5. Estrutura sugerida da página

### 5.1 Hero
- O logótipo, o slogan "Joga com quem está aqui." e um subtítulo: *"Uma mesa de Magic: The Gathering no teu telemóvel. Offline, gratuita, para jogar com quem está ao teu lado."*
- Botão principal: **"Entrar no open beta (Android)"**.
- Botão secundário: **"Apoiar o projeto"** (leva à secção de doações).
- Imagem: um telemóvel com a mesa de jogo, ou dois telemóveis lado a lado na mesma partida.

### 5.2 Como funciona (3 passos)
1. **Descarrega as cartas uma vez.** A base de cartas tem cerca de 36 mil cartas e uns 25 MB. Depois disso, tudo funciona em modo avião.
2. **Monta ou importa o teu deck.** Aceita listas do Moxfield, do Archidekt, do MTGO e do Arena, e a app valida o deck para o formato.
3. **Joga.** Um jogador cria a sala no Wi-Fi ou num hotspot criado pela própria app, e os outros entram pelo QR code. Cada um joga no seu telemóvel.

### 5.3 Funcionalidades (em grelha de cartões)

**Jogar juntos, sem internet**
- Sala na rede local ou num hotspot criado pela app. Os outros entram por descoberta automática, QR code ou IP.
- A mão e o grimório de cada jogador nunca saem do telemóvel dele.
- Se alguém perder a ligação, volta a entrar sozinho. Se a app fechar, o jogo é retomado onde ficou.

**Uma mesa completa**
- Vida, dano de comandante, taxa de comandante automática, veneno, energia, monarca e iniciativa.
- Virar cartas (tap), contadores, tokens, anexar cartas e mudar o controlo. Os planeswalkers entram com a lealdade e as habilidades usam-se com um toque.
- Ações do grimório: comprar, baralhar, scry, surveil, mill, procurar e mulligan.
- Registo de tudo o que acontece, desfazer, dados e moeda, e histórico de jogos com estatísticas.

**Decks e cartas**
- Pesquisa instantânea e offline, com sintaxe parecida com a do Scryfall.
- Deck builder com validação por formato, estatísticas e simulador de mão inicial.
- Escolha da arte (versão) de cada carta.
- Coleção "As minhas cartas", importada do ManaBox, Moxfield, Deckbox ou Dragon Shield.
- Partilha de decks por QR code e backup num ficheiro.
- Estimativa do **bracket** de Commander (1–5).

**Boosters**
- Sealed com cerca de 170 sets, de 1993 até hoje, com a composição real de cada um.
- Draft na rede local com amigos. Os lugares vazios ficam com bots.
- Commander draft (Commander Legends, Commander Masters…).
- JumpStart com 570 pacotes temáticos.

**Aprender a jogar**
- Tutorial guiado contra dois adversários simulados: lês um pouco e jogas um pouco.
- Duas versões: "Nunca joguei" e "Já sei jogar Magic" (só o que muda no Commander).
- Inclui glossário de termos.

**Também para testar sozinho**
- Goldfish (testar o deck a solo) ou 1 contra 1 no mesmo dispositivo.
- O jogo fica gravado e pode ser retomado mais tarde.
- Funciona em telemóvel e em tablet.

### 5.4 "Uma mesa, não um árbitro"
Um bloco curto a explicar a filosofia:

> A app não joga por ti nem te impede de jogar. Guarda o estado da partida (vida, zonas, contadores e turnos) e deixa as regras aos jogadores, como numa mesa a sério. Por isso funciona com qualquer carta, mesmo as que saíram ontem.

### 5.5 Open beta
- Título: **"Entra no open beta"**.
- Texto: *"O EDHere está em beta aberto para Android. Experimenta, joga com os teus amigos e diz-nos o que melhorar."*
- Botão: **"Quero entrar no beta"**. O link ainda está por definir (ver secção 7).
- Requisitos: Android 6.0 ou superior. O download inicial das cartas é de cerca de 25 MB e convém fazê-lo em Wi-Fi.

### 5.6 Apoiar o projeto
- Título: **"Apoia o EDHere"**.
- Texto: *"O EDHere é e vai continuar a ser gratuito, sem anúncios e sem contas. É feito por uma pessoa, no tempo livre. Se gostas da app, ajuda a mantê-la viva."*
- Botão de doação. A plataforma ainda está por definir (ver secção 7).
- Destaque **"Leva o EDHere ao iPhone"**: o código já está preparado para iOS, mas publicar na App Store exige a conta de programador da Apple (99 USD por ano) e um Mac para compilar e testar. As doações ajudam a pagar o lançamento no iOS.
  - **Sugestão:** uma barra de progresso para o objetivo "lançamento iOS".

### 5.7 FAQ (curta)
- **É mesmo gratuito?** Sim. Sem anúncios, sem compras na app e sem contas.
- **Preciso de internet?** Só para descarregar as cartas e as imagens. Depois disso, funciona em modo avião.
- **Os outros jogadores precisam da app?** Sim. Cada um joga no seu telemóvel, na mesma rede Wi-Fi ou no hotspot de quem cria a sala.
- **A app aplica as regras?** Não. É uma mesa: guarda o estado do jogo e os jogadores jogam como numa mesa física.
- **E iPhone?** Está nos planos e depende do apoio da comunidade (ver "Apoia o EDHere").
- **Em que línguas?** Por agora em português. Inglês, espanhol e italiano estão a caminho.

### 5.8 Rodapé (obrigatório)
Deve incluir o aviso legal:

> EDHere é conteúdo de fãs não oficial, permitido pela Fan Content Policy. Não é aprovado nem endossado pela Wizards. Partes dos materiais usados são propriedade da Wizards of the Coast. ©Wizards of the Coast LLC.

Deve incluir também:
- os créditos: dados e imagens das cartas do [Scryfall](https://scryfall.com) (o EDHere não é produzido nem apoiado pelo Scryfall), dados dos boosters do [MTGJSON](https://mtgjson.com), e símbolos das fontes Mana e Keyrune, de Andrew Gioia;
- "© Júlio Rodrigues".

## 6. Cuidados

- **Não usar** logótipos, marcas nem arte oficial da Wizards de forma que pareça uma app oficial. Imagens de cartas, só dentro dos screenshots da app.
- Não dizer que a app é open source: o código é privado.
- Não prometer datas para o iOS nem para as outras línguas.

## 7. Por definir (pelo Júlio)

- **Link do open beta.** Opções: um teste aberto do Google Play, um link direto para o APK, ou um formulário de inscrição.
- **Plataforma de doações.** Por exemplo Ko-fi, Buy Me a Coffee, PayPal ou GitHub Sponsors. Decidir também se a página mostra o objetivo do iOS com uma barra de progresso.
- **Domínio e alojamento** da página.
- **Línguas da página.** Sugestão: começar em português e inglês e acrescentar espanhol e italiano quando a app os tiver.
- **Contacto.** Email ou Discord para sugestões e para reportar problemas.
