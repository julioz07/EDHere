"""Lista os literais com letras que não estão dentro de tr() (para rever à mão).

Uso: python -I tool/l10n/report.py ficheiros...
"""
import re
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.stdout.reconfigure(encoding='utf-8')
from wrap import tokens, groups, text_of  # noqa: E402

for path in sys.argv[1:]:
    s = open(path, encoding='utf-8').read()
    for g in groups(s, tokens(s)):
        t = text_of(g)
        if len(re.sub(r'[^A-Za-zÀ-ÿ]', '', t)) < 2:
            continue
        before = s[max(0, g[0].start - 12):g[0].start]
        if re.search(r'\b(tr|mesaTr|cardDbTr)\(\s*$', before):
            continue
        line = s.count('\n', 0, g[0].start) + 1
        src_line = s.split('\n')[line - 1].strip()
        if re.match(r'(import|export|part)\b', src_line):
            continue
        print(f'{path}:{line}: {t[:70]!r}   | {src_line[:110]}')
