"""Tira o `const` que envolve um tr() (os erros de constante do analisador).

Corre `flutter analyze`, e para cada erro de constante procura o `const` cuja
expressão contém o sítio do erro: numa expressão tira a palavra; numa
declaração (`const x = ...`, `static const`) troca-a por `final`. Repete até
não haver erros destes.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
CODES = {'const_eval_method_invocation', 'const_with_non_constant_argument', 'non_constant_list_element',
         'const_initialized_with_non_constant_value', 'non_constant_map_value', 'non_constant_map_element',
         'const_constructor_param_type_mismatch', 'invalid_constant', 'non_constant_set_element'}
LINE = re.compile(r'^\s*error - .* - (.+?):(\d+):(\d+) - (\w+)\s*$')


def analyze(paths):
    out = subprocess.run(['flutter', 'analyze', *paths], cwd=ROOT, capture_output=True, text=True, encoding='utf-8',
                         shell=True).stdout
    errs = []
    for l in out.splitlines():
        m = LINE.match(l)
        if m and m.group(4) in CODES:
            errs.append((m.group(1), int(m.group(2)), int(m.group(3))))
    return errs


def skip_ws(s, i):
    while i < len(s) and s[i] in ' \t\r\n':
        i += 1
    return i


def match_close(s, i):
    """s[i] é ( [ ou {: devolve o índice a seguir ao fecho."""
    pairs = {'(': ')', '[': ']', '{': '}'}
    stack = [pairs[s[i]]]
    i += 1
    while stack:
        c = s[i]
        if c in '\'"':
            q = s[i:i + 3] if s[i:i + 3] in ("'''", '"""') else c
            i += len(q)
            while not s.startswith(q, i):
                i += 2 if s[i] == '\\' else 1
            i += len(q)
            continue
        if s.startswith('//', i):
            i = s.find('\n', i)
            continue
        if c in pairs:
            stack.append(pairs[c])
        elif stack and c == stack[-1]:
            stack.pop()
        i += 1
    return i


def const_span(s, k):
    """Fim da expressão que começa no `const` em k (ou fim da declaração)."""
    i = skip_ws(s, k + 5)
    # Declaração: const nome = ...;  ou  const Tipo nome = ...;
    m = re.match(r'(?:[A-Za-z_<>,?\s.]+\s+)?[A-Za-z_]\w*\s*=(?!=)', s[i:])
    if m and not re.match(r'[A-Z]\w*\s*\(', s[i:]):
        j = s.find(';', i)
        # o ';' pode estar dentro de strings ou blocos: avança com equilíbrio
        j = i
        depth = 0
        while True:
            c = s[j]
            if c in '([{':
                j = match_close(s, j)
                continue
            if c in '\'"':
                q = s[j:j + 3] if s[j:j + 3] in ("'''", '"""') else c
                j += len(q)
                while not s.startswith(q, j):
                    j += 2 if s[j] == '\\' else 1
                j += len(q)
                continue
            if c == ';':
                return j, True
            j += 1
    # Expressão: Nome<...>.ctor( ... ) ou [ ... ] ou { ... } ou <T>[...]
    m = re.match(r'[A-Za-z_][\w.]*(?:<[^>]*>)?\s*', s[i:])
    if m:
        i += m.end()
    elif s[i] == '<':
        i = s.find('>', i) + 1
        i = skip_ws(s, i)
    if i < len(s) and s[i] in '([{':
        return match_close(s, i), False
    return i, False


def fix_file(path, offsets):
    s = open(path, encoding='utf-8').read()
    edits = set()
    for off in offsets:
        best = None
        for m in re.finditer(r'\bconst\b', s[:off]):
            k = m.start()
            end, decl = const_span(s, k)
            if k < off < end:
                best = (k, decl)  # o mais exterior? queremos o mais interior que contém: o último
        if best:
            edits.add(best)
    for k, decl in sorted(edits, reverse=True):
        if decl:
            s = s[:k] + 'final' + s[k + 5:]
        else:
            j = skip_ws(s, k + 5)
            s = s[:k] + s[j:]
    open(path, 'w', encoding='utf-8', newline='').write(s)
    return len(edits)


def offset(path, line, col):
    s = open(path, encoding='utf-8').read()
    lines = s.split('\n')
    return sum(len(l) + 1 for l in lines[:line - 1]) + col - 1


def main():
    paths = sys.argv[1:] or ['lib', 'packages']
    for round_ in range(30):
        errs = analyze(paths)
        if not errs:
            print('sem erros de const')
            return
        byfile = {}
        for f, l, c in errs:
            p = os.path.join(ROOT, f)
            byfile.setdefault(p, []).append(offset(p, l, c))
        n = sum(fix_file(p, offs) for p, offs in byfile.items())
        print(f'volta {round_ + 1}: {len(errs)} erros, {n} const tirados')
        if n == 0:
            for f, l, c in errs[:20]:
                print('  por resolver:', f, l, c)
            return


main()
