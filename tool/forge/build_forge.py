"""Compila o motor do Forge e prepara o que vai dentro da app para o bot.

Fonte: Forge (GPL-3.0), https://github.com/Card-Forge/forge
- Os jars do motor (forge-core, forge-game, forge-ai, forge-gui) e as
  bibliotecas de que precisam vão para android/app/libs/forge/. As de rede
  (netty, jetty) ficam de fora: o jogo em rede do Forge não é usado.
- Os dados (scripts das cartas, sets, formatos, perfis da IA) vão num zip para
  android/app/src/main/assets/forge/forge-res.zip. As cartas ficam num
  cardsfolder.zip lá dentro, que o Forge lê sem o extrair (34 mil ficheiros
  pequenos ocupariam ~300 MB no telemóvel).

O Forge fica preso a um commit (FORGE_COMMIT) para os builds serem iguais.

Uso (no PC, com JDK 17+ e Maven):
    python tool/forge/build_forge.py
    python tool/forge/build_forge.py --src C:/caminho/forge --mvn C:/maven/bin/mvn

Sem --src, o código do Forge é clonado para tool/forge/.cache/forge (fora do git).
"""

import argparse
import io
import os
import shutil
import subprocess
import sys
import zipfile

FORGE_REPO = 'https://github.com/Card-Forge/forge.git'
FORGE_COMMIT = '0880b059e9e54903c16ee44c63a9e46ee87746a5'

ROOT = os.path.dirname(os.path.abspath(__file__))
APP = os.path.normpath(os.path.join(ROOT, '..', '..'))
CACHE = os.path.join(ROOT, '.cache')
LIBS_OUT = os.path.join(APP, 'android', 'app', 'libs', 'forge')
RES_OUT = os.path.join(APP, 'android', 'app', 'src', 'main', 'assets', 'forge', 'forge-res.zip')

# Pastas de forge-gui/res de que o motor precisa para jogar (o resto é da
# interface do Forge: aventura, quest, música, temas...).
RES_DIRS = ['tokenscripts', 'editions', 'blockdata', 'setlookup', 'formats', 'ai', 'defaults', 'lists', 'effects']
LANGUAGES = ['en-US', 'pt-BR', 'es-ES', 'it-IT']

# Bibliotecas que não vão para a app (jogo em rede do Forge, anotações).
SKIP_JARS = ('netty', 'jetty', 'javax.servlet', 'rssreader', 'checker', 'error_prone', 'j2objc', 'jsr305',
             'listenablefuture')


def run(cmd, cwd=None):
    print('>', ' '.join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True, shell=(os.name == 'nt'))


def ensure_source(src):
    if src:
        return src
    src = os.path.join(CACHE, 'forge')
    if not os.path.isdir(os.path.join(src, '.git')):
        os.makedirs(src, exist_ok=True)
        run(['git', 'init', '-q'], cwd=src)
        run(['git', 'remote', 'add', 'origin', FORGE_REPO], cwd=src)
    run(['git', 'fetch', '-q', '--depth', '1', 'origin', FORGE_COMMIT], cwd=src)
    run(['git', 'checkout', '-q', FORGE_COMMIT], cwd=src)
    return src


def check_commit(src):
    head = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=src, capture_output=True, text=True).stdout.strip()
    if head != FORGE_COMMIT:
        sys.exit(f'O Forge em {src} está em {head[:10]}, não no commit esperado {FORGE_COMMIT[:10]}.')


def build_jars(src, mvn):
    deps = os.path.join(CACHE, 'deps')
    shutil.rmtree(deps, ignore_errors=True)
    # copy-dependencies corre dentro do reactor: os módulos do Forge usam
    # ${revision} e não se resolvem uns aos outros fora dele.
    run([mvn, '-q', '-B', '-pl', 'forge-gui', '-am', 'package', 'dependency:copy-dependencies',
         '-DskipTests', '-Dcheckstyle.skip', '-DincludeScope=runtime', f'-DoutputDirectory={deps}'], cwd=src)
    shutil.rmtree(LIBS_OUT, ignore_errors=True)
    os.makedirs(LIBS_OUT)
    jars = [os.path.join(deps, j) for j in os.listdir(deps)]
    jars.append(next(os.path.join(src, 'forge-gui', 'target', j) for j in os.listdir(os.path.join(src, 'forge-gui', 'target'))
                     if j.startswith('forge-gui-') and j.endswith('.jar')))
    total = 0
    for j in sorted(jars):
        name = os.path.basename(j)
        if name.startswith(SKIP_JARS) or not name.endswith('.jar'):
            continue
        shutil.copy(j, LIBS_OUT)
        total += os.path.getsize(j)
    print(f'jars: {len(os.listdir(LIBS_OUT))} em {LIBS_OUT} ({total / 1e6:.1f} MB)')


def build_res(src):
    res = os.path.join(src, 'forge-gui', 'res')
    os.makedirs(os.path.dirname(RES_OUT), exist_ok=True)

    cards = io.BytesIO()
    with zipfile.ZipFile(cards, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        folder = os.path.join(res, 'cardsfolder')
        for dirpath, _, files in os.walk(folder):
            for f in sorted(files):
                path = os.path.join(dirpath, f)
                z.write(path, os.path.relpath(path, folder).replace(os.sep, '/'))

    with zipfile.ZipFile(RES_OUT, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        # já vem comprimido: guardado tal como está
        z.writestr(zipfile.ZipInfo('res/cardsfolder/cardsfolder.zip'), cards.getvalue(), zipfile.ZIP_STORED)
        for d in RES_DIRS:
            for dirpath, _, files in os.walk(os.path.join(res, d)):
                for f in sorted(files):
                    path = os.path.join(dirpath, f)
                    z.write(path, 'res/' + os.path.relpath(path, res).replace(os.sep, '/'))
        for lang in LANGUAGES:
            z.write(os.path.join(res, 'languages', f'{lang}.properties'), f'res/languages/{lang}.properties')
        z.writestr('VERSION', FORGE_COMMIT + '\n')
    print(f'dados: {RES_OUT} ({os.path.getsize(RES_OUT) / 1e6:.1f} MB)')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', help='pasta com o código do Forge (já no commit certo)')
    ap.add_argument('--mvn', default=os.environ.get('MVN', 'mvn'), help='executável do Maven')
    ap.add_argument('--res-only', action='store_true', help='só gera o zip dos dados')
    args = ap.parse_args()

    src = ensure_source(args.src)
    check_commit(src)
    if not args.res_only:
        build_jars(src, args.mvn)
    build_res(src)


if __name__ == '__main__':
    main()
