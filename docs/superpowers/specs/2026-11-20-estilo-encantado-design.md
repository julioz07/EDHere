# Estilo "Encantado" (segundo estilo visual da app)

Data: 2026-11-20 · Estado: aguarda aprovação final do utilizador (abordagem C e "só pele" já escolhidas)

## 1. Intenção

Alguns testers acham a UI demasiado simples ("plain"), outros gostam dela assim. O
utilizador quer um aspeto de fantasia, ao estilo Magic, sem perder o atual. Por isso a
app passa a ter um **Estilo** escolhido nas Definições:

- **Clássico**: a app tal como está hoje (2.2.2). Não muda nada.
- **Encantado**: o kit "UI encantada" (feito no Claude online, zip `edhere-ui-encantada.zip`):
  molduras com fio de ouro, plaquetas douradas, botão "gema" azul, Cinzel e Crimson Pro,
  brilho em quem tem a vez.

O Estilo é independente do modo Claro/Escuro/Sistema: há 4 combinações e todas têm de
funcionar bem.

## 2. Objetivos, não-objetivos, anti-objetivos

**Objetivos**
- Escolher o Estilo nas Definições, com efeito imediato (sem reiniciar a app).
- O Encantado veste a app inteira (todos os ecrãs) através do tema.
- Nos ecrãs onde se olha mais (Jogar, Sala, Deck, Mesa) aparecem as peças especiais do
  kit: plaquetas da vida, brilho de quem tem a vez, coroa no comandante, títulos de
  secção ornamentados, molduras com gema.
- Encantado Claro: as cores equivalentes em claro (pergaminho), **mantendo o dourado**.

**Não-objetivos (por agora)**
- Ornamentos extra nos ecrãs secundários (estatísticas, boosters, tutorial, introdução,
  definições): ficam encantados só pelo tema. Podem vir depois, um de cada vez.
- O selo arcano a rodar no fundo da mesa (opcional no kit): fica de fora; a mesa continua
  com os fundos que o jogador escolhe.
- Mudar layout, navegação, fluxos ou lógica.
- Escolher o Estilo na introdução (onboarding).

**Anti-objetivos (falha mesmo que "funcione")**
- O Clássico mudar de aspeto, nem que seja um pouco.
- Texto cortado ou sobreposto a 360 dp de largura ou com texto a 1,3×.
- Duas versões do mesmo ecrã para manter (um ecrã = um código, as peças é que sabem
  desenhar-se nos dois estilos).
- As cores do jogo mudarem de significado (atacar, bloquear, alvo, jogável e as cores dos
  jogadores ficam como estão em `GameColors`).
- Descarregar fontes da internet (a app é offline).

## 3. Restrições

- Flutter 3.24.5. O código do kit pede ≥ 3.27: trocar `Color.withValues(alpha:)` por
  `withOpacity`, `TabBarThemeData` por `TabBarTheme`. `ButtonStyle.backgroundBuilder`
  existe na 3.24 (confirmado no SDK), por isso o gradiente "gema" pode ir no tema.
- Fontes em `assets/fonts/` (Cinzel 600/700/800, Crimson Pro 500 itálico, Inter
  400/500/600/700), com OFL.txt registado no `LicenseRegistry` como já se faz com o
  Mana. Cerca de 1 MB a mais.
- Textos novos passam pelo `tr()` e pelo pipeline de traduções (PT/EN/ES/IT).
- Ecrãs pequenos: regras da memória "Small screens" (BottomActions/ResumeTile); testar
  360x640 com fonte 1,3.
- Efeitos param com `MediaQuery.disableAnimations`.
- Alvos de toque ≥ 44 px; texto dourado nunca abaixo de 12 px; contraste de texto ≥ 4,5:1
  nos 4 modos.

## 4. Abordagens consideradas

| | Abordagem | Troca | Decisão |
|---|---|---|---|
| A | Só pelo tema (um segundo `ThemeData`) | Barato e veste tudo, mas a mesa e os ecrãs principais ficam sem plaquetas, coroa e brilho | Base da C |
| B | Peças próprias em todo o lado (~270 botões e ~155 cartões em 35 ficheiros) | Mais fiel ao kit, mas lenta e arrisca partir ecrãs pequenos já afinados | Rejeitada |
| **C** | **Misto: A para a app toda + peças do kit nos 4 ecrãs principais** | ~80% do efeito com pouco risco; ecrãs secundários sem ornamentos | **Escolhida pelo utilizador** |

## 5. Desenho

### 5.1 Definição e escolha
- `Settings`: chave nova `ui_style` com `classic` (por omissão, também para quem
  atualiza) ou `enchanted`. Getter/setter como `themeMode`.
- Definições → secção do aspeto: por baixo de Claro/Escuro/Sistema, um seletor
  "Estilo: Clássico / Encantado" do mesmo tipo (`SegmentedButton`). Mudar refaz o tema
  na hora.
- `main.dart`: `theme`/`darkTheme` passam a vir de `buildTheme(brightness, style)`.

### 5.2 Tokens
- Um `ThemeExtension` (`EdhStyle`) com o estilo ativo e as cores do kit (as de
  `EnchantedColors`), presente nos 4 temas. No Clássico as cores apontam para os
  equivalentes de hoje, para que uma peça do kit possa ler os tokens sem `if`.
- `context.edhStyle` para ler; `isEnchanted` para as poucas decisões de forma.
- **Encantado Escuro**: os valores do kit (`#0A0D18`, `#121831`→`#1C2442`, ouro
  `#D8B868`…).
- **Encantado Claro** (proposta, afinar no ecrã): fundo pergaminho `#F4EEDF`, molduras
  `#FFFBF0`→`#F1E7CF`, campo `#FBF5E6`, ouro dos fios `#A9822F`, ouro mais escuro para
  texto dourado `#7E5F1F` (o ouro claro não tem contraste para texto sobre pergaminho),
  plaqueta `#FFF6DA`→`#E8CB80` com contorno `#8A6A2E`, azul gema `#2F6FEB`→`#1E4FB8`,
  texto `#2A2116`, texto secundário `#6B6150`. Cada par texto/fundo é medido (≥ 4,5:1).

### 5.3 Camada 1: tema (veste a app toda)
`buildTheme(brightness, enchanted)` em `lib/app/theme.dart`; o ramo Clássico devolve
exatamente o tema de hoje. No Encantado:
- `textTheme`: Cinzel em display/headline/title e nos botões, Inter no corpo.
- `FilledButton` → "gema": gradiente azul via `backgroundBuilder`, contorno dourado,
  Cinzel. É só uma gema por ecrã (a convenção da app já é um `FilledButton` principal);
  os sítios com vários ficam como estão e são revistos no QA.
- `OutlinedButton` e `FilledButton.tonal` → "obsidiana": fundo da moldura, contorno dourado.
- `Card` → um `ShapeBorder` próprio que pinta o fio de ouro duplo (1 px ouro, 2 px
  escuro, 1 px ouro a 20%) em cantos 14.
- `TabBar` com o `GoldTabIndicator`; `NavigationBar` com o indicador ativo em gema;
  `InputDecoration` com rótulo dourado; `AppBar`, `Divider`, `SnackBar`, `BottomSheet`,
  `Dialog`, `SegmentedButton` (ativo em gradiente `plateLight → goldLight`) e `Chip`.
- `GameColors` e as cartas não mudam.

### 5.4 Camada 2: peças do kit (nos 4 ecrãs)
Em `lib/ui/style/`, adaptadas de `enchanted_widgets.dart`. **Cada peça desenha-se nos
dois estilos**: no Clássico devolve exatamente o widget que o ecrã usa hoje.
- `SectionDivider`: título de secção ornamentado. Clássico = o título atual.
- `GoldPlate`: número em plaqueta biselada (vida, contagens). Clássico = o texto atual.
- `StyledFrame` (`EnchantedFrame`): moldura com gema no topo, `highlighted` para o
  próprio/ativo. Clássico = o `Card`/contentor atual.
- `TurnGlow`: brilho a "respirar" (2,4 s) à volta de quem tem a vez. Clássico = o
  destaque atual da vez.
- `LegendCrown`: coroa sobre o comandante. Clássico = nada.
- `GemButton`/`ObsidianButton` só onde o tema não chega (ex.: FAB circular do Deck).
- `ManaOrb` para gemas de identidade dos jogadores; os símbolos de mana continuam a ser
  os SVG atuais.

**Só pele (decisão do utilizador).** As referências `E-*.png` servem para o **aspeto**
(dourado, símbolos, molduras, letras, a ideia), **não para a arrumação**: onde a imagem
arruma um ecrã de outra forma (ex.: Jogar em grelha de botões sem o cartão do bot, Deck
com cabeçalho de arte e miniaturas por linha), manda a arrumação de hoje. Nenhum dado
novo (ex.: miniatura do comandante no jogo gravado).

Onde entram (só o aspeto das referências):
- **Jogar** (`lib/ui/play/`, `resume_tile.dart`): logótipo com "EDHere" dourado, jogo
  gravado em `StyledFrame` com coroa, `SectionDivider` nas secções.
- **Sala** (`room_screen.dart`, `lobby_screen.dart` `_SeatCard`/`_Players`): moldura das
  regras, selo "Pronto", lugar livre tracejado.
- **Deck** (`lib/ui/decks/`): cabeçalho com arte do comandante, `SectionDivider`,
  comandante em moldura destacada com coroa.
- **Mesa**: as 3 mesas, telemóvel (`table_screen.dart` `_PlayersStrip`/`_BigPlayerChip`),
  tablet (`tablet_table_screen.dart` `_SeatArea`) e bot (`bot_table_screen.dart`
  `_PlayerBar`): vida em `GoldPlate`, `TurnGlow` em quem tem a vez, coroa no
  comandante, registo em Crimson Pro itálico, barra de cima com fio dourado e a fase em
  "pílula", contagens das zonas em `GoldPlate`.

O layout da mesa, a mão e as zonas não mudam de sítio; só a pele.

### 5.6 Decisões do construtor (aceites pelo utilizador ou a confirmar na leitura)
- **Coroa** (`LegendCrown`): no comandante da zona de comando e no cartão/barra do
  jogador. **Não** nas cartas no campo de batalha: as cartas não mudam.
- **Mesa, fora de âmbito:** verso da carta com efeito de pilha no grimório e plaquetas de
  força/resistência nas cartas.
- **Gema de cada jogador:** a cor do lugar (`GameColors.player`), não a identidade do
  comandante, para manter o significado que os jogadores já conhecem.
- **Garantia do Clássico:** são permitidas pequenas refatorações para meter as peças nos
  ecrãs, desde que o Clássico fique idêntico ao píxel. Antes de mexer em cada ecrã, fazer
  testes golden do Clássico (telemóvel 360x640 e normal) e mantê-los a passar.

### 5.5 Kit e referências no repositório
- `docs/design/ui-encantada/` recebe o `HANDOFF.md` e as referências (`E-*.png` e
  `.dc.html`), para quem continuar o trabalho.
- Galeria só em debug com todas as peças, nos 2 estilos × claro/escuro, para rever.

## 6. Ordem e entregas
1. Fontes + licenças + `Settings.uiStyle` + seletor nas Definições + tema Encantado
   (camada 1) + galeria debug. → **Mostrar ao utilizador antes de continuar.**
2. Peças da camada 2 + Jogar.
3. Sala. 4. Deck. 5. Mesa (telemóvel, tablet, bot). 6. Efeitos + validação com
   "reduzir movimento".
Um commit por passo. Sai numa versão menor (2.3.0).

## 7. Testes
- Widget tests de cada peça nos 2 estilos; no Clássico, que devolve o widget de hoje.
- Teste de que o tema Clássico continua igual ao atual (mesmas cores/tamanhos).
- Seletor de Estilo: muda e persiste.
- Emulador: os 4 ecrãs em 4 combinações (Clássico/Encantado × Claro/Escuro), em 360x640
  com fonte 1,3 e num tablet; um jogo contra o bot com "reduzir movimento" ligado.

## 8. Fica ao critério de quem constrói
- Valores finos do Encantado Claro, desde que o contraste passe e o dourado se mantenha.
- Nomes dos ficheiros e das classes em `lib/ui/style/`.
- Que ecrã ou componente precisa de pequenos ajustes para o tema "pegar" (ex.: cores
  fixas em `Color(0x…)` que hoje ignoram o tema, 47 em 13 ficheiros de `lib/ui`).
