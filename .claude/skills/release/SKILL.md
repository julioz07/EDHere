---
name: release
description: Lança uma versão nova do EDHere (beta fechado / Play Store) — sobe a versão, escreve notas em 4 línguas, compila AAB e APKs assinados, verifica a assinatura, entrega no NAS, faz commit, tag e push. Usar quando o utilizador pede "gera os pacotes", "nova versão", "lança a X.Y.Z", "dá-me um pacote para instalar".
---

# Lançar uma versão do EDHere

Caminhos privados (NAS, keystore) estão em `local.md` nesta pasta — **lê-o primeiro**. Esse ficheiro está no `.gitignore` e não pode ir para o repositório (é público).

## Regras que nunca se quebram
- O keystore de upload nunca é copiado para o repositório, nem mostrado, nem partilhado. `android/key.properties` está no `.gitignore`; confirma com `git status` antes do commit.
- Não mexer no Gradle wrapper do utilizador sem fazer cópia de segurança.
- Ficheiros por commitar que não são teus (ex.: `docs/landing-page-brief.md`, `.vscode/`) ficam de fora do commit — `git add` só dos ficheiros da versão.
- O push de `main` + tags é obrigatório: a app é GPL-3.0 e o código público tem de corresponder ao build.

## Passos

1. **Decidir o número.** Ver a versão atual em `pubspec.yaml` (`version: X.Y.Z+N`).
   - Correções → `X.Y.Z+1`; funcionalidades → `X.(Y+1).0`. O build number (`+N`) sobe **sempre** 1.
   - Se o utilizador não disse, escolhe pela natureza das mudanças desde a última tag (`git log vX.Y.Z..HEAD --oneline`) e diz qual escolheste.

2. **Verificar antes de compilar.**
   - `flutter analyze` sem avisos e `flutter test` a passar.
   - Se houve texto novo, correr o pipeline de traduções (ver memória i18n): `L10N_DUMP=1 flutter test test/l10n/l10n_test.dart --plain-name "os textos dos dados"` → `python -I tool/l10n/extract.py` → `PYTHONIOENCODING=utf-8 python -I tool/l10n/build.py`; `tool/l10n/missing.json` tem de ficar vazio.

3. **Subir a versão em dois sítios** (esquecer o segundo já aconteceu):
   - `pubspec.yaml` → `version: X.Y.Z+N`
   - `lib/net/discovery.dart` → `appVersion = 'X.Y.Z'` (serve para dispositivos na mesma rede se reconhecerem).

4. **Notas da versão.**
   - `docs/play-store/listing.md`: secções "Notas da versão (X.Y.Z)", "Release notes", "Notas de la versión", "Note sulla versione" — PT, EN, ES, IT, **cada uma com menos de 500 caracteres** (limite da Play Console). Conta os caracteres.
   - Escritas para jogadores, não para programadores: o que mudou para eles, sem nomes de classes.
   - `README.md`: linha "**Versão atual: X.Y.Z**" e uma linha nova no topo da tabela de versões.

5. **Compilar** (cada um demora; correr em sequência):
   ```
   flutter build appbundle --release
   flutter build apk --release --split-per-abi
   flutter build apk --release
   ```
   O último gera o universal; o segundo gera `app-arm64-v8a-release.apk` e `app-armeabi-v7a-release.apk`.

6. **Verificar a assinatura** de pelo menos um APK e do AAB:
   `keytool -printcert -jarfile <ficheiro>` → o Owner tem de ser `CN=EDHere, O=juliocr, C=PT`. Se aparecer `Android Debug`, **parar**: o `key.properties` não foi lido.

7. **Entregar no NAS** (precisa de sandbox desligada; caminho em `local.md`):
   - `EDHere-vX.Y.Z-arm64.apk`, `EDHere-vX.Y.Z-armv7.apk`, `EDHere-vX.Y.Z-universal.apk` na raiz.
   - `PlayStore/EDHere-vX.Y.Z-N.aab`.
   - Manter só as **3 últimas versões** de APKs; apagar as mais antigas (os AAB ficam).

8. **Git.**
   ```
   git add <ficheiros da versão>
   git commit -m "X.Y.Z (N): <resumo curto em PT>"
   git tag vX.Y.Z
   git push origin main --tags
   ```

9. **Memória.** Acrescentar a entrada da versão em `edhere-roadmap-progress.md` (data, versionCode, tag, o que contém, o que está no NAS) e atualizar a linha do `MEMORY.md`.

10. **Responder ao utilizador** com: caminhos no NAS, qual APK instalar (arm64 para quase todos), as notas nas 4 línguas prontas a colar na Play Console, e o aviso de que um APK do NAS não instala por cima de uma versão instalada pela Play Store (assinaturas diferentes — a Play reassina).
