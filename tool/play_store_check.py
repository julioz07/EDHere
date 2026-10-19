"""Confere os limites da Play Store nos textos de docs/play-store/listing.md.

Uso: python -I tool/play_store_check.py
"""
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')
LIMITS = [30, 80, 4000, 500]  # nome, descrição breve, descrição completa, notas da versão
text = pathlib.Path(__file__).resolve().parent.parent.joinpath('docs/play-store/listing.md').read_text(encoding='utf-8')
ok = True
for lang_block in re.split(r'\n## ', text)[1:]:
    lang = lang_block.split('\n', 1)[0].strip()
    sections = [s.split('\n', 1)[1].strip().split('\n---')[0].strip() for s in re.split(r'\n### ', lang_block)[1:]]
    for name, body, limit in zip(['nome', 'breve', 'completa', 'notas'], sections, LIMITS):
        n = len(body)
        flag = 'OK ' if n <= limit else 'MAIS'
        ok &= n <= limit
        print(f'{flag} {lang:28} {name:9} {n:5} / {limit}')
sys.exit(0 if ok else 1)
