"""Gera docs/play-store/store-listing.csv a partir de listing.md, para o
"Importe traduções com IA" da Play Console (uma coluna por língua).

Uso: python -I tool/play_store_csv.py
"""
import csv
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent / 'docs/play-store'
text = (root / 'listing.md').read_text(encoding='utf-8')
fields = ['App name / title', 'Short description', 'Full description']
cols = {}
for block in re.split(r'\n## ', text)[1:]:
    lang = re.match(r'(\S+)', block).group(1)  # pt-PT, en-US...
    sections = [s.split('\n', 1)[1].strip().split('\n---')[0].strip() for s in re.split(r'\n### ', block)[1:]]
    cols[lang] = sections[:3]
langs = list(cols)
out = root / 'store-listing.csv'
with out.open('w', encoding='utf-8-sig', newline='') as f:
    w = csv.writer(f)
    w.writerow(['field', *langs])
    for i, name in enumerate(fields):
        w.writerow([name, *(cols[l][i] for l in langs)])
print(out, langs)
