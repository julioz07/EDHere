---
name: a11y-review
description: Revisão de acessibilidade e de ecrãs pequenos de um ecrã ou funcionalidade Flutter do EDHere — alvos de toque, contraste, escala de texto, ecrãs 360x640, TalkBack/Semantics, informação só por cor, movimento e som. Usar antes de lançar um ecrã novo, quando um tester reporta botões escondidos/texto cortado, ou quando o utilizador pede revisão de acessibilidade/usabilidade.
---

# Revisão de acessibilidade (Flutter, EDHere)

Os testers usam Android baratos e pequenos (o caso do Redmi em 1.4.3), muitos com fonte aumentada. Primeiro garantir que **ninguém fica bloqueado**; depois o conforto.

## Como rever
1. Ler o código do ecrã (widgets, `tr()`, cores do tema) — muitos problemas veem-se sem correr.
2. Correr no emulador em **360x640 dp + fonte 1.3** (`adb shell wm size 720x1280; wm density 320; settings put system font_scale 1.3`) e em tablet; no fim repor (`wm size reset; wm density reset; font_scale 1.0`).
3. Ver o logcat de debug: `RenderFlex overflowed` é sempre um achado.
4. Se possível, ligar o TalkBack e percorrer o ecrã com gestos.

## Checklist

### Bloqueadores (P0)
- A ação principal está visível sem scroll a 360x640/fonte 1.3 → usar `BottomActions` (`lib/ui/widgets/responsive.dart`); em formulários com teclado, no fim de uma `Column` (lista `Expanded` + `BottomActions`) para ficar acima do teclado. Nunca `MaxWidth` dentro de uma barra inferior.
- Nenhum overflow, nenhum texto essencial cortado com `…` (prompts de jogo usam `maxLines: 3`, não 1–2).
- Diálogos cabem no ecrã ou fazem scroll; botões do diálogo nunca saem do ecrã.
- Nada depende só de gestos (arrastar, toque longo) — existe sempre um caminho por toque (ex.: atacar arrastando *ou* tocando).

### Graves (P1)
- Alvos de toque ≥ 48x48 dp (`IconButton` já cumpre; `InkWell`/`GestureDetector` em ícones pequenos não — usar `ConstrainedBox(minHeight: 48)` ou padding).
- Todo o `IconButton` tem `tooltip:` (o TalkBack lê-o); imagens de cartas importantes têm `Semantics(label: nome da carta)`; ícones decorativos ficam `excludeFromSemantics`.
- Contraste de texto ≥ 4.5:1 (≥ 3:1 para texto grande e ícones), nos dois temas e **por cima dos fundos de mesa** (o utilizador pode escolher imagens claras — o escurecimento do fundo tem de proteger o texto).
- Informação nunca só por cor: cores de mana têm símbolo, vida baixa tem número, carta selecionada tem borda/ícone além da cor, alvo válido tem mais que um tom.
- Texto escala com o sistema; só se limita (`textScaler` clamp, ex. 1.15 na mesa) onde o layout é denso, nunca em formulários e diálogos.
- Strings visíveis passam por `tr()`; nenhum texto do Forge/Scryfall aparece cru em inglês quando há tradução possível.

### Conforto (P2)
- Animações respeitam `MediaQuery.disableAnimations` (definição "remover animações" do Android) e a velocidade escolhida na app; nada pisca mais de 3 vezes por segundo.
- Sons e vibração têm opção de desligar; nenhuma informação é só sonora.
- Orientação: o ecrã funciona em retrato e paisagem, ou está explicitamente bloqueado (mesa partilhada).
- Feedback de estado anunciado: `SnackBar` ou `SemanticsService.announce` para ações sem mudança visual óbvia.
- Ordem de foco lógica; o primeiro foco de um diálogo é o título ou a ação principal.
- Tablet ≥ 840 dp: formulários com `MaxWidth`, sem linhas de texto com 150 caracteres.

## Resultado
Tabela por prioridade (P0/P1/P2): ecrã, problema, quem afeta, correção proposta com ficheiro:linha. Corrigir P0 sem perguntar só se o utilizador pediu correções; senão, propor.
