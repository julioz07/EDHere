---
name: bot-playtest
description: Sessão de QA de "game feel" e de bugs do modo "jogar contra o bot" (Forge) no emulador, em modo tablet e telemóvel. Usar quando o utilizador pede para testar o jogo contra o bot, reporta bugs de jogo, diz que algo está "estático"/"confuso"/"não responde", ou antes de lançar uma versão que mexeu em lib/ui/bot ou no ForgeEngine.
---

# Playtest do modo bot

Objetivo: jogar partidas reais, no tablet **e** no telemóvel, e sair com uma lista numerada de achados (F1, F2…) e melhorias (G1, G2…) por prioridade — não com impressões vagas. Referência de qualidade: MTG Arena; ver também a skill `tcg-specialist`.

## Preparar
- Emulador tablet: AVD `Tablet_API_35` (fica `emulator-5554` quando é o único). Não apagar dados dos emuladores — têm apps de outros projetos.
- Build debug instalado (`flutter run` ou `flutter install`). O primeiro arranque do motor em debug demora ~50 s; em release é muito mais rápido — não reportar como bug sem ver em release.
- **Modo telemóvel** no mesmo emulador: `adb shell wm size 720x1280; adb shell wm density 320; adb shell settings put system font_scale 1.3`. Repor: `wm size reset; wm density reset; settings put system font_scale 1.0`. O utilizador testa sobretudo no telemóvel — os bugs dele costumam ser de ecrã pequeno.
- Capturas: `adb emu screenrecord screenshot <caminho.png>` (o `screencap` sai em branco nestes emuladores). Captura de 2000x1250; as coordenadas de toque no tablet são ×1.28.
- Scripts em `scripts/` (Git Bash): `shot.sh [x y] [espera] [saida.png]` toca e captura em modo tablet; `ptap.sh` o mesmo em modo telemóvel; `toblock.sh` joga sozinho até ao primeiro pedido de bloqueio. As coordenadas são do layout atual e dos prompts em italiano do Forge — se a UI mudou, ajusta antes de confiar neles.
- Os prompts do Forge aparecem no logcat: `adb logcat -d | grep "forge prompt"`. Erros: `grep -E "EDHereForge.*E |AndroidRuntime|E flutter|overflowed"`.

## O que jogar (cobrir em cada sessão)
1. Arranque: moeda, mulligan (mão inteira visível no telemóvel?), primeira jogada.
2. Turno próprio: jogar terreno, lançar feitiço com pagamento automático e manual, criatura com alvo, desfazer, terminar turno.
3. Combate: atacar por toque e por arrastar; bloquear por arrastar; criaturas a atacar não mudam de tamanho nem roubam espaço.
4. Respostas: pilha com feitiço do bot, responder com instantâneo, paragens (stops) e "Controlo total".
5. Escolhas: modais/efeitos múltiplos (opções têm de parecer botões), alvos, X, descartar.
6. Turno do bot: dá para perceber o que fez? (spotlight, registo, setas).
7. Fim: vitória, derrota, desistir, revanche.
8. Repetir 2–5 no telemóvel com fonte 1.3.

## Checklist de "game feel" (cada um é um achado se falhar)
- Cada toque tem resposta visível em <100 ms (mesmo que o Forge ignore a ação — há watchdog de 1,5 s; nunca fica preso em "O bot está a pensar…").
- Botões não mudam de função debaixo do dedo (lição: Cancelar = desfazer *ou* terminar turno parecia toque partido).
- Custos de mana e texto de regras usam símbolos (`OracleText`), nunca `{2}{R}` em texto.
- Texto vindo do Forge em inglês/italiano é traduzido ou limpo (ids ` (123)`, `[ ]`, "Life: …").
- O que o bot faz é visível antes de acontecer o seguinte; nada passa em <1 s sem rasto.
- Cartas jogáveis destacadas; terrenos que podem pagar destacados durante o pagamento.
- Animações nunca bloqueiam input e respeitam a velocidade escolhida.
- Nada transborda a 360x640 com fonte 1.3 (logcat "RenderFlex overflowed").
- Sons/haptics com opção de desligar.

## Lições técnicas conhecidas
- O Cancelar de prioridade do Forge desfaz se puder, senão termina o turno — a mesa usa ações explícitas `undo` / `endTurn` no `ForgeEngine.java`.
- Um toque que o Forge ignora não gera prompt novo: a UI não pode esperar por um para sempre.
- Um builder não pode capturar uma variável que depois é reatribuída ao próprio widget (StackOverflow no DragTarget de bloqueio).
- `ConcurrentModificationException` no snapshot é uma corrida benigna apanhada por `snapshotSafe`.
- Para ver diálogos sem jogar até eles: golden test com a fonte Segoe UI carregada como 'Roboto' e a fonte Mana via `FontLoader`, e `ForgeCardLookup` com `noSuchMethod`.

## Resultado
- Lista F (achados) com passos para reproduzir, ecrã (tablet/telemóvel) e captura; lista G (melhorias) por prioridade, com esforço estimado (S/M/L).
- Propor lotes; não implementar sem o utilizador aprovar.
- Guardar o backlog numa memória de projeto (como `qa-bot-feel.md`) e atualizar o estado quando um lote fechar.
