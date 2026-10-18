<p align="center">
  <img src="assets/logo/edhere-logo-svg/edhere-logo-vertical-dark.svg" alt="EDHere" width="200">
</p>

<p align="center"><strong>Joga com quem está aqui.</strong><br>
Uma mesa de Magic: The Gathering totalmente offline, para construir decks, testá-los e jogar com quem está ao teu lado — sem internet, sem contas, sem servidores.</p>

---

## O que é

O EDHere é uma app Flutter (Android; iOS preparado) que funciona como **mesa de jogo, não como motor de regras**: gere zonas, vida, contadores, turnos e tokens, e as regras ficam a cargo dos jogadores, como numa mesa física. O foco é **Commander/EDH**, mas a mesa serve qualquer formato.

A internet só é usada para descarregar a base de cartas e as imagens (do [Scryfall](https://scryfall.com)). Tudo o resto funciona em modo avião.

## Funcionalidades

**Cartas e decks**
- Base de cartas offline (~36 mil cartas, ~25 MB a descarregar) com pesquisa instantânea e sintaxe parecida com a do Scryfall (`t:dragon id:rg mv<=3`, `f:commander`, `is:commander`…).
- Deck builder com validação por formato (tamanho, singleton, banidas, identidade de cor, parceiros e backgrounds), vista em lista ou grelha, estatísticas, simulador de mão inicial.
- Importar e exportar listas (Moxfield, Archidekt, MTGO, Arena) e partilhar decks por QR code.
- Versões alternativas das cartas: escolher a arte por entrada de deck ou como preferida em todo o lado; só se descarrega a imagem escolhida.
- As minhas cartas: coleção indicativa (importação do ManaBox, Moxfield, Deckbox, Dragon Shield ou texto), filtro "só as que tenho" ao construir decks e, em cada carta, em que decks está.
- Pacotes de imagens à escolha (Commander, Modern, tokens…), em resolução pequena ou normal.

**Boosters (sealed e JumpStart)**
- Sealed: abrir boosters de qualquer um dos ~170 sets com boosters (de 1993 até hoje), com a composição real de cada set, ou packs de um cubo próprio; montar um deck de 40 com a pool (o resto fica no sideboard).
- JumpStart: escolher 2 de 570 pacotes temáticos vendo só o tema e a carta de destaque; os dois juntos fazem o deck de 40.
- Os dados vêm dentro da app (funcionam sem internet); só as imagens se descarregam.

**Mesa**
- Goldfish, 1 contra 1 no mesmo dispositivo (mesa partilhada frente a frente, mãos abertas para ensinar).
- Tap, contadores editáveis (+1/+1, lealdade, modificadores de poder/resistência), habilidades dadas por efeitos, tokens, anexar, mudar controlo, virar face, alvos em cartas ou jogadores.
- Grimório: comprar, baralhar, scry, surveil, mill, procurar, revelar, mulligan London.
- Vida, dano de comandante, veneno, energia, monarca, iniciativa, taxa de comandante automática.
- Registo de eventos, desfazer, dados e moeda, histórico de jogos e estatísticas.

**Multijogador local**
- Um jogador cria a sala na rede Wi-Fi ou num hotspot criado pela app; os outros entram por descoberta automática (mDNS), QR code ou IP.
- A mão e o grimório de cada jogador nunca saem do telemóvel dele.
- Religação automática a meio do jogo.
- Imagens em falta (por exemplo, versões alternativas de outro jogador) podem vir da internet ou do próprio dispositivo desse jogador, pela rede local.

**Definições**
- Tema claro, escuro ou do sistema; fundo da área de jogo (5 incluídos ou da galeria); tamanho das cartas; gestão dos dados offline.

## Estrutura

| Pasta | Conteúdo |
| --- | --- |
| `packages/mesa_core` | Núcleo de jogo em Dart puro: estado da mesa, eventos, zonas ocultas, desfazer |
| `packages/mesa_protocol` | Envelope dos eventos e enquadramento TCP |
| `packages/card_db` | Importação do Scryfall, pesquisa, decks, validação, listas em texto, versões (SQLite) |
| `lib/net` | Sala: anfitrião TCP, cliente com religação, mensagens diretas, mDNS, hotspot, QR |
| `lib/data` | Descargas, imagens, versões, definições, providers (Riverpod) |
| `lib/game` | `GameController` (núcleo ↔ UI) e `NetworkGame` (lobby e jogo em rede) |
| `lib/ui` | Ecrãs |
| `android/.../MainActivity.kt` | Hotspot local (`LocalOnlyHotspot`) por platform channel |
| `tool/` | Geradores (glifos da fonte Mana, ícones da app, dados de boosters) |
| `assets/boosters` | Composição dos boosters por set e pacotes JumpStart (gerados do MTGJSON) |

O plano completo do projeto está em [`App Commander Offline — Arquitetura e Plano.md`](App%20Commander%20Offline%20—%20Arquitetura%20e%20Plano.md).

## Compilar

Requisitos: Flutter 3.24 (Dart 3.5), Android SDK 35, JDK 17+ (o do Android Studio serve).

```sh
flutter pub get
flutter run                                   # num dispositivo ou emulador
flutter build apk --release --split-per-abi   # APKs por arquitetura
```

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

A app é e será **100% gratuita**: sem anúncios, sem funcionalidades pagas, sem contas.

## Direitos

© Júlio Rodrigues. Todos os direitos reservados. O EDHere é gratuito, mas o código não é aberto: este repositório é privado e não pode ser copiado, modificado nem redistribuído sem autorização. Sugestões são bem-vindas.
