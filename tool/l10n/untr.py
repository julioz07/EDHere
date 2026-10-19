"""Tira tr() de linhas/blocos: python -I tool/l10n/untr.py ficheiro inicio fim [const]

Entre as linhas inicio e fim (1-based, inclusive) troca tr('x') por 'x' (só os
simples, sem argumentos). Com 'const', troca o 'final' da linha inicio por 'const'.
"""
import re
import sys

path, a, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
mk_const = len(sys.argv) > 4 and sys.argv[4] == 'const'
lines = open(path, encoding='utf-8').read().split('\n')
for i in range(a - 1, b):
    lines[i] = re.sub(r"""\btr\(('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")\)""", r'\1', lines[i])
if mk_const:
    lines[a - 1] = re.sub(r'\bfinal\b', 'const', lines[a - 1], count=1)
open(path, 'w', encoding='utf-8', newline='').write('\n'.join(lines))
