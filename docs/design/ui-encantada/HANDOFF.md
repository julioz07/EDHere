# EDHere — UI encantada: handoff para o Claude Code

Objetivo: trocar a "pele" da app (componentes base do Flutter/Material) por um kit
de fantasia ao estilo Magic. **O layout, os fluxos e a lógica ficam iguais**:
só mudam os componentes visuais, as cores, a tipografia e os efeitos.

## 1. O que está nesta pasta

| Ficheiro | Para quê |
|---|---|
| `referencias/E-*.png` | Capturas dos 4 ecrãs redesenhados (Jogar, Mesa, Deck, Sala). Nestas capturas os títulos aparecem numa letra de recurso; a final é Cinzel. |
| `referencias/E-*.dc.html` | A fonte exata do design: todos os valores (cores, raios, sombras, tamanhos) estão no CSS inline. Em caso de dúvida, vale o que está aqui. |
| `referencias/E-Componentes.dc.html` | O kit: botões e estados, moldura, orbes, plaquetas, efeitos, e o mapa de Material para encantado. |
| `lib/ui/enchanted/enchanted_theme.dart` | Tokens (`EnchantedColors` como `ThemeExtension`), escala de texto e `buildEnchantedTheme()`. |
| `lib/ui/enchanted/enchanted_widgets.dart` | Componentes base: `EnchantedFrame`, `GemButton`, `ObsidianButton`, `SectionDivider`, `GoldPlate`, `ManaOrb`, `LegendCrown`, `TurnGlow`, `GoldTabIndicator`, `GemNavBar`. |

Os ficheiros Dart são um **ponto de partida, não foram compilados**. Pedem Flutter ≥ 3.29 (`TabBarThemeData`, `Color.withValues`).
Em versões mais antigas, usa `TabBarTheme` e `withOpacity`.

## 2. Linguagem visual (porquê, em 6 linhas)

- **Moldura = rebordo de uma carta:** fio de ouro duplo (1 px ouro, 2 px escuro, 1 px ouro a 20%) e uma gema no topo.
- **Plaquetas biseladas douradas** para números (vida, contagens), como a caixa de força/resistência.
- **Coroa de lendária** no comandante e nas lendárias.
- **Cor de identidade** na gema de cada jogador e nos brilhos. O ouro é só para o que está ativo ou é especial.
- **Botão principal "gema" azul EDHere:** só um por ecrã. Os secundários são "obsidiana" com contorno dourado.
- **Tipografia:** Cinzel (títulos e botões), Crimson Pro itálico (texto de apoio, como o texto de ambiente das cartas), Inter (corpo).

## 3. Tokens

| Token | Hex | Uso |
|---|---|---|
| background | `#0A0D18` | fundo da app |
| surface → surfaceHigh | `#121831` → `#1C2442` | gradiente das molduras |
| field | `#0E1326` | campos, ranhuras de zona |
| gold / goldLight / goldPale | `#D8B868` / `#E8CB80` / `#FBEBB8` | fios, texto dourado, gemas |
| goldDeep / plateLight | `#8A6A2E` / `#FFF6DA` | plaquetas |
| arcaneLight / arcane / arcaneDeep | `#86B6FF` / `#4682F2` / `#2149B8` | botão gema, nav ativa |
| text / textMuted | `#F2ECDD` / `#A9B0C8` | texto |
| success | `#4CC074` | "Pronto", validação |
| Mana W U B R G C | `#F2E6C2` `#3B7BF0` `#3E2E4E` `#E0502A` `#3FA35A` `#B8B2A6` | identidade |

Raios: molduras 14, botões e campos 12, plaquetas cerca de 22% da altura. Alvos de toque ≥ 44 px.

## 4. Substituições (Material → encantado)

| Antes | Depois |
|---|---|
| `FilledButton` / `ElevatedButton` | `GemButton` (só a ação principal do ecrã) |
| `OutlinedButton` / `FilledButton.tonal` | `ObsidianButton` |
| `Card` / `ListTile` em cartão | `EnchantedFrame` (`highlighted: true` para o item ativo ou próprio) |
| `TabBar` | `TabBar(indicator: GoldTabIndicator())` com o tema |
| `NavigationBar` | `GemNavBar` |
| `TextField` | o `InputDecorationTheme` do tema (rótulo em Cinzel dourado) |
| `SegmentedButton` | segmentos com o ativo em gradiente `plateLight → goldLight` (ver `E-Deck`) |
| Chips ou números soltos | `GoldPlate` |
| Títulos de secção | `SectionDivider('Com outros')` |
| Separadores de jogador na mesa | `EnchantedFrame` pequena com `ManaOrb`/gema e `GoldPlate` da vida, envolvida em `TurnGlow` quando é a vez desse jogador |

## 5. Efeitos (poucos, cada um com significado)

| Efeito | Onde | Especificação |
|---|---|---|
| Reflexo | Só no `GemButton` | passa em 55% de um ciclo de 3,8 s, `easeInOut` |
| Respiração | Moldura de quem tem a vez | 2,4 s ida e volta, brilho do ouro de 35% a 70% |
| Coroa | Comandante e lendárias | ornamento + brilho de 16 px |
| Brilho de mana | Gemas, orbes, estado ativo | `BoxShadow` 10–24 px na cor |

Todos param quando `MediaQuery.disableAnimations` está ligado.

## 6. Ecrã a ecrã (ver as capturas)

- **Jogar:** logótipo com o texto "EDHere" em gradiente dourado. O jogo gravado vai numa `EnchantedFrame` com miniatura do comandante e coroa, e por baixo uma linha com Apagar e o `GemButton` Continuar. "Criar sala" é o `GemButton` do ecrã; "Entrar numa sala" é `ObsidianButton`. Boosters e Testar e ensinar ficam em grelhas 2×1 de `ObsidianButton`.
- **Mesa:** barra superior escura com linha dourada em baixo e pílula de fase. Os jogadores aparecem em 3 molduras com nome em cima e, em baixo, `GoldPlate` da vida mais mão e grimório com ícones; quem tem a vez leva `TurnGlow`. O campo de batalha tem um selo arcano subtil, opacidade 22% e rotação lenta (opcional). As zonas são ranhuras com a contagem numa `GoldPlate`, e o grimório tem o verso da carta e um efeito de pilha. O registo vai em Crimson Pro itálico, e "Passar turno" é `GemButton`.
- **Deck:** cabeçalho com a arte do comandante (art crop do Scryfall) e gradiente para o fundo. Separadores com `GoldTabIndicator`. Pesquisa num campo arcano e segmentos Tipo/Custo. Secções com `SectionDivider`. O comandante vai numa moldura destacada com coroa; as linhas têm nome em Cinzel, que pode ocupar 2 linhas, tipo em Crimson Pro e custo à direita. FAB em `GemButton` circular.
- **Sala:** a moldura das regras tem o título "Commander" e o subtítulo "Vida 40 · N jogadores". A linha do jogador leva o selo "Pronto" na linha do nome e o deck por baixo. Há um lugar livre tracejado a piscar ("À espera de jogadores"). Ações em `ObsidianButton` e "Começar jogo" em `GemButton`.

## 7. Regras para não partir nada

- **Nunca cortar texto.** Os nomes de cartas podem ocupar 2 linhas; os rótulos curtos usam `maxLines: 1` + `ellipsis` só onde o design o mostra (botões).
- **Testar em 360 dp de largura** e com a escala de texto do sistema a 1,3×.
- **As fontes vão em assets.** A app é offline: **não** usar o pacote `google_fonts` em runtime. Descarregar Cinzel, Crimson Pro e Inter de fonts.google.com (pasta `static/`) para `assets/fonts/` e declarar no `pubspec.yaml`:

```yaml
flutter:
  fonts:
    - family: Cinzel
      fonts:
        - asset: assets/fonts/Cinzel-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Cinzel-Bold.ttf
          weight: 700
        - asset: assets/fonts/Cinzel-ExtraBold.ttf
          weight: 800
    - family: CrimsonPro
      fonts:
        - asset: assets/fonts/CrimsonPro-MediumItalic.ttf
          weight: 500
          style: italic
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
          weight: 400
        - asset: assets/fonts/Inter-Medium.ttf
          weight: 500
        - asset: assets/fonts/Inter-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Inter-Bold.ttf
          weight: 700
```

- **Licenças:** as três fontes são SIL OFL. Incluir os ficheiros OFL.txt e registar com `LicenseRegistry`.
- **Símbolos de mana:** continuar a usar os SVG do Scryfall que a app já tem. `ManaOrb` é para gemas e indicadores.
- **Contraste:** `textMuted` sobre `surface` dá cerca de 8:1. Não usar texto dourado com menos de 12 px.

## 8. Ordem de implementação sugerida

1. Fontes nos assets + `enchanted_theme.dart` ligado no `MaterialApp(theme: buildEnchantedTheme())`.
2. `enchanted_widgets.dart` e uma página de teste (galeria) com todos os componentes e estados.
3. Ecrã **Jogar** (o mais simples) e depois **Sala**, **Deck** e **Mesa**.
4. Os restantes ecrãs (introdução, tutorial, boosters, definições) com as mesmas peças.
5. Efeitos (`TurnGlow`, reflexo), por último, e validação com "reduzir movimento" ligado.

## 9. Prompt para colar no Claude Code

> Lê `design/ui-encantada/HANDOFF.md` e as capturas em `design/ui-encantada/referencias/`.
> Vamos aplicar a "UI encantada" à app EDHere **sem mudar layout, navegação nem lógica**.
> 1) Põe as fontes em assets e liga `lib/ui/enchanted/enchanted_theme.dart` no MaterialApp.
> 2) Revê e corrige `lib/ui/enchanted/enchanted_widgets.dart` para a nossa versão do Flutter, e cria uma página de galeria (só em debug) com todos os componentes e estados.
> 3) Mostra-me a galeria antes de continuares.
> 4) Depois migra os ecrãs um a um, por esta ordem: Jogar, Sala, Deck, Mesa. Para cada um, compara com a captura correspondente.
> Em todos os ecrãs: nenhum texto cortado nem sobreposto a 360 dp nem com texto a 1,3×, alvos ≥ 44 px, efeitos desligados com `disableAnimations`.
> Faz um commit por ecrã.
