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
    python tool/forge/build_forge.py --languages   (só as correções das línguas)

Sem --src, o código do Forge é clonado para tool/forge/.cache/forge (fora do git).
"""

import argparse
import hashlib
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

    fixed = card_overrides()
    cards = io.BytesIO()
    with zipfile.ZipFile(cards, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        folder = os.path.join(res, 'cardsfolder')
        for dirpath, _, files in os.walk(folder):
            for f in sorted(files):
                path = os.path.join(dirpath, f)
                name = os.path.relpath(path, folder).replace(os.sep, '/')
                if name in fixed:
                    z.writestr(name, fixed[name])
                else:
                    z.write(path, name)

    with zipfile.ZipFile(RES_OUT, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        # já vem comprimido: guardado tal como está
        z.writestr(zipfile.ZipInfo('res/cardsfolder/cardsfolder.zip'), cards.getvalue(), zipfile.ZIP_STORED)
        for d in RES_DIRS:
            for dirpath, _, files in os.walk(os.path.join(res, d)):
                for f in sorted(files):
                    path = os.path.join(dirpath, f)
                    z.write(path, 'res/' + os.path.relpath(path, res).replace(os.sep, '/'))
        for lang in LANGUAGES:
            with open(os.path.join(res, 'languages', f'{lang}.properties'), encoding='utf-8') as f:
                z.writestr(f'res/languages/{lang}.properties', patch_language(lang, f.read()))
        z.writestr('VERSION', res_version() + '\n')
    print(f'dados: {RES_OUT} ({os.path.getsize(RES_OUT) / 1e6:.1f} MB)')


# As línguas do Forge com as nossas correções (tool/forge/overrides/<língua>.properties).
# O pt-BR é a língua do bot para quem usa a app em português de Portugal: o
# Forge trata por "você", aqui trata-se por tu nas perguntas mais comuns.
OVERRIDES = os.path.join(ROOT, 'overrides')
PT_RULES = [('Você quer ', 'Queres '), ('você quer ', 'queres '), ('Você deseja ', 'Queres '),
            ('você deseja ', 'queres '), ('Você pode ', 'Podes '), ('você pode ', 'podes '),
            ('Você tem ', 'Tens '), ('você tem ', 'tens '),
            # pedidos: imperativo por tu e possessivos de Portugal (as contrações primeiro)
            ('=Escolha ', '=Escolhe '), ('=Selecione ', '=Seleciona '),
            (' de sua mão', ' da tua mão'), (' em sua mão', ' na tua mão'), (' na sua mão', ' na tua mão'),
            (' sua mão', ' a tua mão'),
            (' de seu grimório', ' do teu grimório'), (' em seu grimório', ' no teu grimório'),
            (' no seu grimório', ' no teu grimório'), (' seu grimório', ' o teu grimório'),
            (' de seu cemitério', ' do teu cemitério'), (' em seu cemitério', ' no teu cemitério'),
            (' no seu cemitério', ' no teu cemitério'), (' seu cemitério', ' o teu cemitério')]


def overrides(lang):
    path = os.path.join(OVERRIDES, f'{lang}.properties')
    fixes = {}
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            for line in f.read().splitlines():
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    fixes[key] = value
    return fixes


def patch_language(lang, text):
    fixes = overrides(lang)
    out = []
    for line in text.splitlines():
        key = line.split('=', 1)[0] if '=' in line and not line.startswith('#') else None
        if key in fixes:
            line = f'{key}={fixes.pop(key)}'
        elif lang == 'pt-BR' and key:
            for a, b in PT_RULES:
                line = line.replace(a, b)
        out.append(line)
    out += [f'{k}={v}' for k, v in fixes.items()]
    return '\n'.join(out) + '\n'


# Guiões de cartas com dicas para a IA (tool/forge/overrides/cards/<letra>/<carta>.txt),
# no lugar dos do Forge. Vêm do Grimório (github.com/hubertdungen/grimorio, GPL-3.0):
# só os que diferem do nosso Forge numa dica para a IA, com as regras iguais.
CARD_OVERRIDES = os.path.join(OVERRIDES, 'cards')


def card_overrides():
    """{caminho no cardsfolder: conteúdo} das cartas corrigidas."""
    fixed = {}
    for dirpath, _, files in os.walk(CARD_OVERRIDES):
        for f in sorted(files):
            if f.endswith('.txt'):
                path = os.path.join(dirpath, f)
                with open(path, 'rb') as fh:
                    fixed[os.path.relpath(path, CARD_OVERRIDES).replace(os.sep, '/')] = fh.read()
    return fixed


def res_version():
    """O commit do Forge mais uma marca das correções: a app só volta a extrair
    os dados quando isto muda, por isso uma correção nova tem de o mudar."""
    h = hashlib.sha1(repr(PT_RULES).encode())
    for lang in LANGUAGES:
        h.update(repr(sorted(overrides(lang).items())).encode())
    h.update(repr(sorted(card_overrides().items())).encode())
    return f'{FORGE_COMMIT}+{h.hexdigest()[:8]}'


def patch_cards(data):
    """O cardsfolder.zip com as cartas corrigidas no lugar das originais."""
    fixed = card_overrides()
    out = io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(data)) as zin, zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as zout:
        for info in zin.infolist():
            zout.writestr(info, fixed.get(info.filename, zin.read(info)))
    return out.getvalue()


def patch_res_zip():
    """Aplica as correções das línguas ao zip que já existe, sem o código do Forge."""
    tmp = RES_OUT + '.tmp'
    with zipfile.ZipFile(RES_OUT) as zin, zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as zout:
        for info in zin.infolist():
            data = zin.read(info)
            if info.filename == 'VERSION':
                data = (res_version() + '\n').encode()
            elif info.filename.startswith('res/languages/'):
                lang = os.path.basename(info.filename)[:-len('.properties')]
                data = patch_language(lang, data.decode('utf-8')).encode('utf-8')
            elif info.filename == 'res/cardsfolder/cardsfolder.zip':
                data = patch_cards(data)
            zout.writestr(info, data)
    os.replace(tmp, RES_OUT)
    print(f'línguas e cartas corrigidas em {RES_OUT} (VERSION {res_version()})')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', help='pasta com o código do Forge (já no commit certo)')
    ap.add_argument('--mvn', default=os.environ.get('MVN', 'mvn'), help='executável do Maven')
    ap.add_argument('--res-only', action='store_true', help='só gera o zip dos dados')
    ap.add_argument('--languages', action='store_true',
                    help='só aplica tool/forge/overrides ao zip dos dados que já existe')
    args = ap.parse_args()

    if args.languages:
        patch_res_zip()
        return
    src = ensure_source(args.src)
    check_commit(src)
    if not args.res_only:
        build_jars(src, args.mvn)
    build_res(src)


if __name__ == '__main__':
    main()
