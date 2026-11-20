# Estilo Encantado — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Um segundo estilo visual ("Encantado", claro e escuro) escolhido nas Definições, com o Clássico intacto.

**Architecture:** `buildTheme(brightness, style)` devolve o tema de hoje no Clássico e um tema Encantado (fontes, botões gema/obsidiana, molduras com fio de ouro) no outro; um `ThemeExtension` `EdhStyle` leva o estilo ativo e os tokens. Peças em `lib/ui/style/` desenham-se nos dois estilos (no Clássico devolvem o widget de hoje) e entram nos ecrãs Jogar, Sala, Deck e nas 3 mesas, só como pele.

**Tech Stack:** Flutter 3.24.5, Riverpod (`settingsProvider`), SharedPreferences, flutter_test (widget + golden).

**Spec:** `docs/superpowers/specs/2026-11-20-estilo-encantado-design.md`. Kit de origem: `docs/design/ui-encantada/` (copiado na Task 1).

## Global Constraints

- Flutter 3.24.5: `withOpacity` em vez de `withValues(alpha:)`; `TabBarTheme` em vez de `TabBarThemeData`; `CardTheme` (não `CardThemeData`).
- O Clássico fica idêntico ao píxel: testes golden do Clássico antes de mexer em cada ecrã, a passar no fim.
- Só pele: nenhuma mudança de arrumação, navegação, fluxo ou dado. Referências `E-*.png` só para o aspeto.
- `GameColors` e as cartas não mudam. Gema do jogador = `GameColors.player(seat)`.
- Fontes só em assets (sem `google_fonts`); OFL registada no `LicenseRegistry`.
- Texto novo via `tr()` + pipeline l10n (`tool/l10n/missing.json` vazio).
- Ecrãs pequenos: 360x640 com texto 1,3× sem cortes; alvos ≥ 44 px; texto dourado ≥ 12 px; contraste de texto ≥ 4,5:1 nos 4 modos.
- Efeitos (`TurnGlow`, reflexo da gema) parados com `MediaQuery.disableAnimations`.
- `flutter analyze` sem avisos e `flutter test` a passar no fim de cada task. Um commit por task.

## Review Focus

1. Mudar de Estilo com um jogo aberto (mesa ou bot): o tema troca sem perder o estado do jogo (o `MaterialApp` não pode ganhar uma `key` que dependa do estilo). → teste na Task 5.
2. Encantado Claro com texto dourado sobre pergaminho: legível (contraste ≥ 4,5:1). → teste de contraste dos tokens na Task 3.
3. Utilizador que atualiza da 2.2.2 (sem `ui_style` gravado): vê o Clássico. → teste na Task 2.
4. "Reduzir movimento" ligado: `TurnGlow` e o reflexo do botão gema param (nenhum `AnimationController` a correr). → teste na Task 6.
5. Encantado com 4 jogadores num ecrã 360 dp e texto 1,3×: plaquetas da vida e nomes não transbordam. → teste na Task 11.

---

### Task 1: Fontes, licenças e kit no repositório

**Files:**
- Create: `assets/fonts/Cinzel-SemiBold.ttf`, `Cinzel-Bold.ttf`, `Cinzel-ExtraBold.ttf`, `CrimsonPro-MediumItalic.ttf`, `Inter-Regular.ttf`, `Inter-Medium.ttf`, `Inter-SemiBold.ttf`, `Inter-Bold.ttf`; `assets/licenses/cinzel_OFL.txt`, `crimsonpro_OFL.txt`, `inter_OFL.txt`
- Create: `docs/design/ui-encantada/` (HANDOFF.md + `referencias/`)
- Modify: `pubspec.yaml` (bloco `fonts:` do HANDOFF §7; licenças em `assets:`), `lib/main.dart:23` (`LicenseRegistry`)

- [ ] **Step 1:** Descarregar os TTF estáticos do repositório google/fonts (ofl/cinzel, ofl/crimsonpro, ofl/inter) e os OFL.txt; copiar o kit do zip para `docs/design/ui-encantada/`.
- [ ] **Step 2:** Declarar as famílias `Cinzel`, `CrimsonPro`, `Inter` com os pesos do HANDOFF §7 e registar as 3 licenças.
- [ ] **Step 3:** `flutter pub get` e `flutter analyze` → sem erros.
- [ ] **Step 4:** Commit `estilo: fontes do Encantado (OFL) e kit de referência`.

### Task 2: `Settings.uiStyle`

**Files:** Modify `lib/data/settings.dart`; Test `test/data/settings_style_test.dart`

**Interfaces:** Produces `enum UiStyle { classic, enchanted }` (em `settings.dart`); `UiStyle get uiStyle` / `set uiStyle(UiStyle)` na chave `'ui_style'`.

- [ ] **Step 1: Teste** `uiStyle por omissão é classic` (prefs vazias → `UiStyle.classic`); `uiStyle grava e notifica` (set enchanted → `prefs.getString('ui_style') == 'enchanted'`, listener chamado uma vez); valor desconhecido → classic.
- [ ] **Step 2:** Correr → falha (não definido).
- [ ] **Step 3:** Implementar como `themeMode` (`_set`).
- [ ] **Step 4:** Correr → passa. Commit.

### Task 3: Tokens `EdhStyle`

**Files:** Create `lib/app/style_tokens.dart`; Test `test/app/style_tokens_test.dart`

**Interfaces:** Produces `class EdhStyle extends ThemeExtension<EdhStyle>` com `final UiStyle style; bool get isEnchanted` e as cores de `EnchantedColors` do kit (`background, surface, surfaceHigh, field, gold, goldLight, goldPale, goldDeep, plateLight, arcane, arcaneLight, arcaneDeep, text, textMuted, textOnGold, success`) mais `goldText` (ouro para texto). Constantes `EdhStyle.classicDark`, `classicLight`, `enchantedDark`, `enchantedLight`. `extension EdhStyleX on BuildContext { EdhStyle get edhStyle }` (fallback `classicDark`). `class EdhFonts { display='Cinzel'; flavor='CrimsonPro'; body='Inter' }` e `EdhText` (a escala `EnchantedText` do kit).

- `enchantedDark`: valores do kit; `goldText = goldLight`.
- `enchantedLight`: `background #F4EEDF, surface #FFFBF0, surfaceHigh #F1E7CF, field #FBF5E6, gold #A9822F, goldLight #C79F48, goldPale #E8CB80, goldDeep #8A6A2E, plateLight #FFF6DA, arcane #2F6FEB, arcaneLight #6EA8FF, arcaneDeep #1E4FB8, text #2A2116, textMuted #6B6150, textOnGold #1A120C, success #2E9E5B, goldText #7E5F1F`.
- `classicDark/Light`: mapeiam para `EdhColors` de hoje (surface, text, primary…), para as peças poderem ler tokens sem `if`.

- [ ] **Step 1: Teste** `contraste dos tokens Encantados`: para `enchantedDark` e `enchantedLight`, `contrast(text, surface)`, `contrast(textMuted, surface)`, `contrast(goldText, surface)`, `contrast(goldText, background)`, `contrast(textOnGold, plateLight)` ≥ 4.5 (luminância relativa WCAG, helper no teste). `lerp` a 0 e 1 devolve os extremos.
- [ ] **Step 2:** Correr → falha. **Step 3:** Implementar (afinar `enchantedLight` se o contraste falhar, mantendo o tom dourado). **Step 4:** Passa. Commit.

### Task 4: `buildTheme(brightness, style)`

**Files:** Modify `lib/app/theme.dart`; Create `lib/app/enchanted_theme.dart`, `lib/app/gold_frame_border.dart`; Test `test/app/theme_test.dart`

**Interfaces:** Consumes Task 3. Produces `ThemeData buildTheme(Brightness b, [UiStyle style = UiStyle.classic])`; `ThemeData buildEnchantedTheme(Brightness b)`; `class GoldFrameBorder extends OutlinedBorder` (raio 14; pinta 1 px `gold`, 2 px escuro/`background`, 1 px `gold` a 20%; `highlighted` usa `goldLight`).

- Clássico: o corpo de hoje inalterado, mais `extensions: [EdhStyle.classicDark/Light]`.
- Encantado (spec §5.3): `fontFamily: 'Inter'`; `textTheme` display/headline/title em Cinzel (w700/800); `FilledButton` com `backgroundBuilder` (gradiente `arcaneLight→arcane→arcaneDeep`, stops 0/.42/1, contorno `gold` 1,5, Cinzel w800 15 letterSpacing .6, foreground branco); `OutlinedButton` obsidiana (gradiente surfaceHigh→surface, contorno `gold` a .65, texto `goldText`); `cardTheme.shape: GoldFrameBorder()`; `tabBarTheme` com `GoldTabIndicator` (criado nesta task em `lib/app/gold_tab_indicator.dart`, adaptado do kit, cores por parâmetro); `navigationBarTheme` (indicador em gradiente arcano com contorno dourado, rótulo ativo `goldText`); `inputDecorationTheme`, `snackBarTheme`, `dividerTheme` do kit; `segmentedButtonTheme` com o ativo `plateLight→goldLight` e texto `textOnGold`; `chipTheme`, `dialogTheme`, `bottomSheetTheme` com contorno `gold` a .5. Tamanhos mínimos iguais aos do Clássico (`EdhSize.button`).

- [ ] **Step 1: Testes** `Clássico igual ao de hoje`: `buildTheme(b)` e `buildTheme(b, UiStyle.classic)` têm o mesmo `colorScheme`, `scaffoldBackgroundColor`, `filledButtonTheme.style.minimumSize` que a versão anterior (copiar os valores esperados de `EdhColors`); `Encantado tem EdhStyle.isEnchanted` e `fontFamily` Inter nos dois brilhos; `FilledButton.styleFrom` mínimo = `EdhSize.button` nos dois estilos.
- [ ] **Step 2:** Falha. **Step 3:** Implementar. **Step 4:** Passa. Commit.

### Task 5: Escolha nas Definições e ligação ao `MaterialApp`

**Files:** Modify `lib/main.dart:73-75`, `lib/ui/settings/settings_tab.dart` (após o `SegmentedButton<ThemeMode>`); Create `tool/l10n/src/s138_ui_style.json`; Test `test/ui/settings_style_test.dart`

- `MaterialApp(theme: buildTheme(light, s.uiStyle), darkTheme: buildTheme(dark, s.uiStyle))`; **sem** mudar a `key` (`ValueKey(lang)`).
- Definições → Aparência: `SegmentedButton<UiStyle>` igual ao do tema (`showSelectedIcon: false`, `FitText`), ícones `Icons.crop_square` (Clássico) e `Icons.auto_awesome` (Encantado), textos `tr('Clássico')`, `tr('Encantado')`, com rótulo `tr('Estilo')` por cima (`titleSmall`, como "Fundo da área de jogo"). Traduções: Classic/Clásico/Classico; Enchanted/Encantado/Incantato; Style/Estilo/Stile.

- [ ] **Step 1: Testes** `trocar de estilo muda o tema sem refazer a app`: um `StatefulWidget` com estado (contador) dentro do `EdhereApp`/`MaterialApp` de teste; mudar `uiStyle` → `Theme.of(ctx).extension<EdhStyle>()!.isEnchanted == true` e o estado mantém-se. `o seletor grava a escolha` (tocar "Encantado" → `settings.uiStyle == enchanted`).
- [ ] **Step 2:** Falha. **Step 3:** Implementar + pipeline l10n. **Step 4:** Passa; `missing.json` vazio. Commit.

### Task 6: Peças do kit (`lib/ui/style/`)

**Files:** Create `lib/ui/style/style_frame.dart`, `gold_plate.dart`, `section_divider.dart`, `turn_glow.dart`, `legend_crown.dart`, `mana_orb.dart`, `gem_button.dart` (GemButton/ObsidianButton para onde o tema não chega, ex. FAB); barrel `lib/ui/style/style.dart`; Test `test/ui/style_pieces_test.dart`

**Interfaces:** Cada peça recebe o que o ecrã já passa hoje e um `classic` que é o widget atual:
- `SectionDivider(String label, {required Widget classic})`
- `GoldPlate(String text, {required Widget classic, double fontSize = 19, double minWidth = 38, double height = 34})`
- `StyleFrame({required Widget child, required Widget Function(Widget child) classic, bool highlighted = false, bool showGem = true, EdgeInsetsGeometry padding = const EdgeInsets.all(14)})`
- `TurnGlow({required Widget child, required bool active, Widget Function(Widget child)? classic, double radius = 12})` (sem `classic` → devolve `child`)
- `LegendCrown({double width = 24})` (Clássico → `SizedBox.shrink()`)
- `ManaOrb({required Color color, double size = 18})` (Clássico → `SizedBox.shrink()`, ou o ponto de cor que o ecrã já tem via parâmetro opcional `classic`)
- Todas leem `context.edhStyle`; cores do kit fixas (`0xFF242C4A`, `0xFFF0D99A`…) passam a tokens para funcionarem no Claro.

- [ ] **Step 1: Testes** (`pumpWidget` com `buildTheme(dark, s)` para s em ambos): no Clássico cada peça encontra exatamente o `classic` passado (`find.byKey`) e nenhum `CustomPaint`/gradiente do kit; no Encantado encontra o texto e não o `classic`. `TurnGlow` e `GemButton` com `MediaQuery(disableAnimations: true)`: `tester.hasRunningAnimations == false` após `pump`. `GoldPlate('40')` a 1,3× em 60 px de largura: sem overflow.
- [ ] **Step 2:** Falha. **Step 3:** Implementar adaptando `enchanted_widgets.dart` (withOpacity, tokens). **Step 4:** Passa. Commit.

### Task 7: Galeria (debug) — PONTO DE PARAGEM

**Files:** Create `lib/ui/style/style_gallery_screen.dart`; Modify `lib/ui/settings/settings_tab.dart` (entrada só com `kDebugMode`).

- Mostra, em 2×2 (Clássico/Encantado × Claro/Escuro, via `Theme(data: buildTheme(...))`): FilledButton, OutlinedButton, TextField, Card, TabBar, SegmentedButton, NavigationBar, SnackBar e as peças da Task 6 (incluindo `TurnGlow` ativo).
- [ ] **Step 1:** Implementar; `flutter analyze` limpo.
- [ ] **Step 2:** Correr no emulador, capturar a galeria e os ecrãs Jogar/Definições/Deck/Mesa só com o tema (sem peças) nos 4 modos. Commit.
- [ ] **Step 3: Mostrar ao utilizador e esperar o OK antes da Task 8.**

### Tasks 8–13: ecrãs (só pele)

Para cada ecrã, a mesma sequência:
1. **Golden do Clássico primeiro** (`test/ui/goldens/<ecrã>_classic_test.dart`, 360x640 e 411x891, escuro e claro), gerado com `--update-goldens` **antes** de mexer, e commitado.
2. Trocar os elementos indicados pelas peças da Task 6, passando o widget de hoje como `classic`.
3. `flutter test` → goldens do Clássico continuam a passar (prova de que não mudou).
4. Golden novo do Encantado (escuro e claro) e um teste de overflow a 360 dp com `textScaler: TextScaler.linear(1.3)`.
5. Captura no emulador comparada com o aspeto de `E-*.png`. Commit `estilo: <ecrã> encantado`.

- **Task 8 — Jogar** (`lib/ui/play/play_tab.dart`, `play_with_deck.dart`, `lib/ui/widgets/resume_tile.dart`): títulos de secção → `SectionDivider`; jogo gravado → `StyleFrame(highlighted: true)`; "EDHere" do cabeçalho em `EdhText.display` com gradiente dourado (Encantado). Cartões das opções ficam como estão (o tema já os veste).
- **Task 9 — Sala** (`room_screen.dart` `_Players`, `lobby_screen.dart` `_SeatCard`, `create_room_screen.dart`): regras e jogadores em `StyleFrame` (o próprio `highlighted`), "Pronto" com `success`, gema do lugar `ManaOrb(GameColors.player(seat))`, títulos `SectionDivider`.
- **Task 10 — Deck** (`lib/ui/decks/`): títulos de secção da lista → `SectionDivider`; linha do comandante → `StyleFrame(highlighted: true)` + `LegendCrown`; FAB → `GemButton` circular no Encantado.
- **Task 11 — Mesa telemóvel** (`table_screen.dart` `_PlayersStrip`, `_BigPlayerChip`, `_BottomBar`, AppBar): vida → `GoldPlate`; chip do jogador → `StyleFrame` pequena com `ManaOrb` do lugar; quem tem a vez → `TurnGlow` (Clássico = destaque atual); `LegendCrown` no comandante da zona de comando e no chip; barra de cima com fio dourado em baixo; contagens das zonas → `GoldPlate` pequena; registo em `EdhText.flavor`. Teste do Review Focus 5 (4 jogadores, 360 dp, 1,3×).
- **Task 12 — Mesa tablet** (`tablet_table_screen.dart` `_SeatArea`, `_CenterBar`): as mesmas peças da Task 11.
- **Task 13 — Mesa do bot** (`bot_table_screen.dart` `_PlayerBar`, `_PromptBar`, `bot_effects.dart` `PhaseBar`): as mesmas peças; fase atual em "pílula" com contorno dourado; prompt em `StyleFrame`.

### Task 14: Fecho

- [ ] **Step 1:** Emulador ([[qa-testers-avds]] / "Small screens"): os 4 ecrãs × 4 modos em 360x640 com fonte 1,3 e num tablet; um jogo contra o bot com "Remover animações" ligado; trocar de estilo a meio de um jogo.
- [ ] **Step 2:** Corrigir o que aparecer (cores fixas `Color(0x…)` que não seguem o tema, se ficarem feias no Encantado).
- [ ] **Step 3:** `flutter analyze`, `flutter test`, commit. A versão (2.3.0) sai pelo skill `release` quando o utilizador pedir.
