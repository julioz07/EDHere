"""Recolhe as chaves de tradução (o texto em português).

- Chamadas tr(), mesaTr() e cardDbTr() com literal em lib/ e packages/*/lib.
- Os textos dos dados (tutorial, glossário, formatos...) vêm de
  tool/l10n/data_keys.json, escrito pelo teste test/l10n/l10n_test.dart.

Escreve tool/l10n/keys.json: [{"key": ..., "where": [...]}], por ordem de
ficheiro.
"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
from wrap import tokens, groups  # noqa: E402

CALL = re.compile(r'\b(tr|mesaTr|cardDbTr)\(\s*$')


def unescape(t):
    out = []
    i = 0
    while i < len(t):
        c = t[i]
        if c == '\\' and i + 1 < len(t):
            n = t[i + 1]
            if n == 'n':
                out.append('\n')
            elif n == 't':
                out.append('\t')
            elif n == 'r':
                out.append('\r')
            elif n == 'u':
                if t[i + 2] == '{':
                    j = t.index('}', i)
                    out.append(chr(int(t[i + 3:j], 16)))
                    i = j + 1
                    continue
                out.append(chr(int(t[i + 2:i + 6], 16)))
                i += 6
                continue
            else:
                out.append(n)
            i += 2
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def static_keys():
    files = [f for f in glob.glob(os.path.join(ROOT, 'lib', '**', '*.dart'), recursive=True)
             if not f.endswith('.g.dart')]
    files += glob.glob(os.path.join(ROOT, 'packages', '*', 'lib', '**', '*.dart'), recursive=True)
    keys = {}
    for f in sorted(files):
        s = open(f, encoding='utf-8').read()
        rel = os.path.relpath(f, ROOT).replace(os.sep, '/')
        scan(s, rel, 0, keys)
    return keys


def scan(s, rel, line0, keys):
    """As chaves de tr() em s, incluindo dentro das interpolações."""
    for g in groups(s, tokens(s)):
        line = line0 + s.count('\n', 0, g[0].start) + 1
        for l in g:
            for k, t in l.parts:
                if k == 'e':
                    scan(t, rel, line - 1, keys)
        before = s[max(0, g[0].start - 40):g[0].start]
        if not CALL.search(before):
            continue
        if any(k == 'e' for l in g for k, _ in l.parts):
            print(f'AVISO: interpolação dentro de tr() em {rel}:{line}')
            continue
        key = ''.join(unescape(t) if not l.raw else t for l in g for _, t in l.parts)
        keys.setdefault(key, []).append(f'{rel}:{line}')


def main():
    keys = static_keys()
    data = os.path.join(HERE, 'data_keys.json')
    if os.path.exists(data):
        for k, where in json.load(open(data, encoding='utf-8')).items():
            keys.setdefault(k, []).append(where)
    else:
        print('AVISO: falta data_keys.json (corre flutter test test/l10n)')
    out = [{'key': k, 'where': w} for k, w in keys.items()]
    json.dump(out, open(os.path.join(HERE, 'keys.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(len(out), 'chaves')


if __name__ == '__main__':
    main()
