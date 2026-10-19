"""Gera lib/l10n/strings_{en,es,it}.g.dart a partir de tool/l10n/src/*.json.

Cada ficheiro em src/ é uma lista de entradas [id, en, es, it]:
- id "s123" ou "d45": a chave é a posição 123 de snap_static.json (ou 45 de
  snap_data.json), uma fotografia das chaves para não as reescrever;
- id "=texto": a chave é o próprio texto (para chaves novas).
- en/es/it a null: o texto fica igual ao português (nomes, exemplos...).

Depois compara com keys.json (as chaves atuais, de extract.py) e lista as que
faltam traduzir e as traduções cujos marcadores {x} não batem certo.
"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.stdout.reconfigure(encoding='utf-8')
PH = re.compile(r'\{([a-z][A-Za-z0-9]*)\}')
LANGS = ('en', 'es', 'it')


def load():
    snap_s = json.load(open(os.path.join(HERE, 'snap_static.json'), encoding='utf-8'))
    snap_d = json.load(open(os.path.join(HERE, 'snap_data.json'), encoding='utf-8'))
    tables = {l: {} for l in LANGS}
    for f in sorted(glob.glob(os.path.join(HERE, 'src', '*.json'))):
        for entry in json.load(open(f, encoding='utf-8')):
            ident, *vals = entry
            if ident.startswith('='):
                key = ident[1:]
            elif ident[0] == 's':
                key = snap_s[int(ident[1:])]
            elif ident[0] == 'd':
                key = snap_d[int(ident[1:])]
            else:
                raise ValueError(f'{f}: id inválido {ident}')
            for lang, v in zip(LANGS, vals):
                tables[lang][key] = key if v is None else v
    return tables


def dart_str(s):
    s = s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', '\\n').replace('\r', '')
    return f"'{s}'"


def main():
    tables = load()
    keys = [e['key'] for e in json.load(open(os.path.join(HERE, 'keys.json'), encoding='utf-8'))]
    problems = 0
    for lang in LANGS:
        t = tables[lang]
        missing = [k for k in keys if k not in t]
        if missing:
            problems += len(missing)
            print(f'{lang}: faltam {len(missing)}')
        for k in keys:
            if k in t and set(PH.findall(t[k])) != set(PH.findall(k)):
                problems += 1
                print(f'{lang}: marcadores diferentes em {k!r} -> {t[k]!r}')
    missing = [k for k in keys if any(k not in tables[l] for l in LANGS)]
    json.dump(missing, open(os.path.join(HERE, 'missing.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
    for lang in LANGS:
        name = 'strings' + lang.capitalize()
        lines = ['// Gerado por tool/l10n/build.py a partir de tool/l10n/src. Não editar.', '',
                 f'const {name} = <String, String>{{']
        live = set(keys)
        for k in sorted(tables[lang]):
            if k in live and tables[lang][k] != k:
                lines.append(f'  {dart_str(k)}: {dart_str(tables[lang][k])},')
            elif k in live:
                lines.append(f'  {dart_str(k)}: {dart_str(k)},')
        lines.append('};')
        open(os.path.join(ROOT, 'lib', 'l10n', f'strings_{lang}.g.dart'), 'w', encoding='utf-8', newline='\n').write(
            '\n'.join(lines) + '\n')
    print(f'{len(keys)} chaves; {len(missing)} por traduzir (missing.json); {problems} problemas')


if __name__ == '__main__':
    main()
