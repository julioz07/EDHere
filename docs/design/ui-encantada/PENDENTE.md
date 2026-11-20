# Estilo Encantado — o que falta

Estado em 2026-11-20. A branch `estilo-encantado` tem tudo o que está descrito em
[`docs/superpowers/specs/2026-11-20-estilo-encantado-design.md`](../../superpowers/specs/2026-11-20-estilo-encantado-design.md)
e no plano em `docs/superpowers/plans/2026-11-20-estilo-encantado.md` (tasks 1 a 13
feitas, revisão final feita e corrigida). Ainda **não está na `main`** nem lançada.

## O que já está feito

- Definições → Aparência → **Estilo: Clássico / Encantado**, com troca na hora e sem
  perder o que está aberto. O Clássico continua a ser o de origem (também para quem
  atualiza).
- Encantado escuro (cores do kit) e claro (pergaminho, com o dourado mais escuro no
  texto). Contraste medido em teste (≥ 4,5:1).
- Tema para a app toda: Cinzel nos títulos e botões, Inter no corpo, botão principal
  "gema", secundários "obsidiana", cartões com fio de ouro duplo, separadores e barra
  de baixo dourados.
- Peças em `lib/ui/style/` (cada uma desenha-se nos dois estilos; no Clássico devolve o
  widget de sempre): `SectionDivider`, `GoldPlate`, `GoldPlateFrame`, `StyleFrame`,
  `TurnGlow`, `LegendCrown`, `ManaOrb`.
- Ecrãs com as peças: Jogar, Sala, Deck e as três mesas (telemóvel, tablet, bot).
- Galeria de estilos só em debug (Definições → "Galeria de estilos (debug)").

## Antes de lançar (2.3.0)

1. **Juntar a branch à `main`** e correr `flutter test` no resultado.
2. **QA no aparelho** (o que não foi visto no emulador):
   - Encantado no **tablet** (`Tablet_API_35`): mesa partilhada, Jogar em 2 colunas, Deck.
   - Encantado **claro** nas mesas (só se viu o escuro) e no Deck.
   - Sala, Deck e mesas a **360x640 com letra a 1,3×** no emulador (só o Jogar foi
     visto assim; a mesa tem teste automático).
   - "Remover animações" ligado no Android: o brilho da vez tem de ficar parado (há
     teste, falta ver no aparelho).
   - Trocar de estilo **a meio de um jogo** contra o bot e numa sala com outro
     telemóvel.
   - Um jogo a 4 numa sala real com o Encantado (vidas a 0, derrotados, alvos).
3. Correr o skill `release` (notas nas 4 línguas a falar do novo "Estilo").

## Ficou de fora de propósito (pode vir depois)

- **Ecrãs secundários sem ornamentos**, só com o tema: Estatísticas, Boosters
  (Sealed/JumpStart/draft), Tutorial, Introdução, Definições, Cartas, ficha de carta.
  Nas Definições os títulos de secção ("Língua", "Aparência"…) continuam azuis; seria
  o próximo candidato a `SectionDivider`.
- **Mesa menos dourada do que a referência `E-Mesa.png`**: as contagens das zonas
  (grimório, cemitério, exílio) não têm plaqueta, a fase continua na cor âmbar do jogo,
  o grimório não tem o efeito de pilha, as cartas não têm plaquetas de F/R, e não há o
  selo arcano a rodar no fundo.
- **Sem reflexo animado no botão gema** (o kit tem um brilho que atravessa o botão a
  cada 3,8 s). O tema desenha a gema, mas sem animação.
- **Imagens da Play Store** com o Encantado (e as de tablet, que já estavam por fazer).

## Decisões a rever se alguém se queixar

- Os botões secundários cheios (`FilledButton.tonal`) também saem em gema: há ecrãs
  com mais de uma gema.
- Rótulos longos em Cinzel vão a 2 linhas (ex.: "Começar (só com quem está pronto)").
- Separadores (Cartas / Estatísticas / Validação) em Inter dourado e não em Cinzel:
  em Cinzel "Estatísticas" ficava cortado.
- Nomes de listas em Inter; Cinzel só em títulos, botões e modos do Jogar.
- Fontes reduzidas ao alfabeto latino (cerca de 580 KB): nomes com letras polacas ou
  cirílicas aparecem na letra de recurso.

## Pequenas limpezas (da revisão final)

- `deck_editor_screen.dart`: a moldura do comandante é escolhida comparando o título
  traduzido (`title == tr('Comandante')`); usar o tipo da secção.
- Ordem dos imports em `limited_builder.dart`, `resume_game.dart`, `card_view.dart`.
- `RepaintBoundary` à volta do `TurnGlow` (anima a 60 fps um brilho desfocado).
- 47 cores fixas `Color(0x…)` em 13 ficheiros de `lib/ui` ignoram o tema; ver se alguma
  fica feia no Encantado claro.

## Como testar

- Testes do estilo: `test/app/theme_test.dart`, `test/app/style_tokens_test.dart`,
  `test/ui/style_pieces_test.dart`, `test/ui/settings_style_test.dart` e os casos
  "Encantado" em `test/ui/table_screen_test.dart`.
- Garantia do Clássico: captura no emulador antes e depois da mudança, no mesmo
  estado, e comparação píxel a píxel (diferença máxima ≤ 2/255 conta como igual).
