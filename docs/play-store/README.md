# EDHere na Play Store: guia de publicação

Tudo o que é preciso para publicar a versão 1.5.0. Os ficheiros estão no NAS, em `\\UG-JRZ07\Desenvolvimento\EDHere\PlayStore\`.

| Ficheiro | Para quê |
| --- | --- |
| `EDHere-v1.5.0-31.aab` | O pacote a enviar (App Bundle, assinado com a chave de upload) |
| `icon-512.png` | Ícone da app (512×512) |
| `feature-graphic-{pt,en,es,it}.png` | Imagem de destaque (1024×500), uma por língua |
| `phone-{pt,en,es,it}-N-*.png` | Capturas de ecrã do telemóvel (1080×1920), com legenda |
| `tablet-{pt,en}/*.png` | Capturas de ecrã do tablet (2560×1600) |
| `listing.md` | Nome, descrições e notas da versão nas 4 línguas |
| `privacy-policy.html` | Política de privacidade (tem de ficar num link público) |

A chave de upload está em `C:\Users\julio\.edhere-keys\` e tem uma cópia em `\\UG-JRZ07\Desenvolvimento\EDHere\keys\`. A password está no `LEIA-ME.txt`. **Não a percas, nem a partilhes.**

---

## Antes de começar

1. **Conta de programador** em [play.google.com/console](https://play.google.com/console). Custa 25 USD, pagos uma vez, e pede verificação de identidade.
2. **Email de contacto público:** a Play Store mostra-o na ficha. Põe-no também na política de privacidade, onde está `[EMAIL DE CONTACTO]`.
3. **Alojar a política de privacidade** num link público, por exemplo na futura landing page, no GitHub Pages de um repositório público só para o site, ou no Google Sites. A Play Console só aceita um URL.
4. **Contas pessoais criadas depois de novembro de 2023:** a Google exige um **teste fechado com pelo menos 12 testers durante 14 dias seguidos** antes de dar acesso à produção. Isto serve de open beta: começa por aí.

## 1. Criar a app

**Todas as apps › Criar app**
- Nome: `EDHere: mesa de Commander`
- Língua predefinida: Português (Portugal) – pt-PT
- App ou jogo: **Jogo** (categoria *Cartas*), ou **App** (categoria *Entretenimento*). Recomendo **Jogo › Cartas**, que é onde os jogadores procuram.
- Gratuita
- Aceitar as declarações (políticas e leis de exportação dos EUA)

## 2. Configurar a app (Painel › "Configurar a sua app")

### Acesso à app
**Todas as funcionalidades estão disponíveis sem restrições de acesso.** Não há login.

### Anúncios
**Não, a app não contém anúncios.**

### Classificação de conteúdo (questionário IARC)
- Email de contacto e categoria: **Jogo** (ou "Todos os outros tipos de apps", se a criaste como app).
- Violência: as cartas mostram **ilustrações de fantasia** com combate (criaturas, magia), sem sangue realista. Responde *sim* a violência de fantasia e *não* a violência realista e a sangue.
- Medo/terror: algumas ilustrações são sombrias (mortos-vivos, demónios). Responde *sim* a imagens que possam assustar crianças pequenas, se te pedirem.
- Linguagem imprópria, sexo, drogas, álcool, tabaco: **não**.
- Jogo a dinheiro ou jogo simulado: **não**. Abrir boosters é grátis e não envolve dinheiro, nem real nem virtual.
- Interação entre utilizadores: os jogadores **não** trocam mensagens nem conteúdo livre; só jogam na rede local. Partilha de localização: **não**. Compras digitais: **não**.
- Resultado esperado: PEGI 7 a 12, ou ESRB Everyone 10+.

### Público-alvo e conteúdo
- Faixas etárias: **13–15, 16–17 e 18+**. Não incluas menores de 13: evita as regras extra da política "Famílias".
- A app pode atrair crianças sem querer? **Não.**

### App de notícias / Rastreio de contactos COVID-19 / Funcionalidades financeiras / Saúde / Governo
Responde **não** a tudo.

### Segurança dos dados (Data safety)
- A app recolhe ou partilha algum dos tipos de dados de utilizador obrigatórios? **Não.**
  - Porquê: a app não envia dados pessoais para nenhum servidor. Os pedidos ao Scryfall só descarregam dados públicos das cartas. O jogo em rede é direto entre os telemóveis, na rede local, e os dados nunca saem dela. A câmara só lê QR codes no momento.
- Os dados são encriptados em trânsito? Os pedidos ao Scryfall usam HTTPS. Como não há dados recolhidos, esta pergunta normalmente nem aparece.
- Forma de pedir a eliminação de dados: não se aplica (não há contas). Se a Play Console a pedir, explica que tudo fica no dispositivo e se apaga ao desinstalar.
- Política de privacidade: o URL onde alojaste o `privacy-policy.html`.

### Permissões
A app pede câmara, Wi-Fi, dispositivos Wi-Fi próximos e localização (só Android 8–12). Nenhuma destas exige formulário especial na Play Console. A localização é só "em primeiro plano" e serve para criar o hotspot local.

## 3. Ficha da loja

**Crescer › Presença na loja › Ficha da loja principal**, com os textos em pt-PT do `listing.md`:
- Ícone: `icon-512.png`
- Imagem de destaque: `feature-graphic-pt.png`
- Capturas do telemóvel: `phone-pt-*.png` (5 imagens, por esta ordem)
- Capturas de tablet de 7" e de 10": `tablet-pt/` (escolhe 4 a 8: mesa, deck, estatísticas, carta, tutorial, sala, sealed…)
- Email de contacto e, se quiseres, o site

Depois, em **Gerir traduções › Adicionar as suas próprias traduções**, junta en-US, es-ES e it-IT com os textos do `listing.md`, e em cada uma as imagens dessa língua (`feature-graphic-xx.png`, `phone-xx-*.png`). O tablet em espanhol e italiano pode usar as imagens em inglês.

## 4. Enviar a versão (teste fechado = beta)

1. **Testar › Teste fechado › Criar faixa** (ou usa a faixa "Alpha" que já existe).
2. **Testers:** cria uma lista de emails (no mínimo 12 pessoas para a regra dos 14 dias) ou usa um Grupo do Google. Copia o **link de participação**: é o "link do open beta" para a landing page.
3. **Criar versão:**
   - Na primeira vez, aceita a **Assinatura de apps do Google Play** com a chave gerada pela Google (opção recomendada). A nossa chave fica como chave de upload.
   - Envia o `EDHere-v1.5.0-31.aab`.
   - Nome da versão: `1.5.0 (31)`. Notas: as do `listing.md`, nas 4 línguas.
4. **Países:** todos, ou começa por Portugal, Espanha, Itália, Brasil, Reino Unido e EUA.
5. **Rever e implementar.** A primeira revisão da Google costuma demorar 1 a 7 dias.

Ao fim de 14 dias com 12 ou mais testers ativos, a Play Console permite pedir acesso à **produção**. Aí respondes a umas perguntas sobre o teste e publicas a mesma versão (ou uma mais nova).

## 5. Atualizações futuras

1. Subir `version:` no `pubspec.yaml`. O número depois do `+` (versionCode) tem de aumentar sempre.
2. `flutter build appbundle --release`. Assina sozinho com a chave de upload, lida de `android/key.properties`.
3. Enviar o `build/app/outputs/bundle/release/app-release.aab` para a faixa de teste ou de produção.

## Notas

- **Identificador da app:** `com.juliocr.edhere`. Não se pode mudar depois de publicada.
- **Testers que já têm o APK antigo** (`com.juliocr.edhoff`): a versão da Play Store é outra app, por isso as duas ficam lado a lado. Para passar os decks: na app antiga, *Definições › Exportar backup*; na nova, *Importar backup*. Depois, desinstala a antiga.
- **APKs do NAS a partir da 1.5.0:** estão assinados com a chave de upload, não com a chave da Google. Quem instalar um APK do NAS tem de o desinstalar antes de instalar pela Play Store, e vice-versa. Para os testers, o melhor é passar a usar só a Play Store.
- **Propriedade intelectual:** a Play Store pode questionar as imagens das cartas. A descrição já inclui o aviso da Fan Content Policy da Wizards e os créditos do Scryfall. Se houver objeções, responde com esse enquadramento: conteúdo de fãs gratuito, sem anúncios nem compras, e imagens descarregadas pelo utilizador a partir do Scryfall.
- **Screenshots:** as do telemóvel são da 1.4.1. O lobby e o separador Jogar mudaram um pouco na 1.4.3; se quiseres, refaço-as.
