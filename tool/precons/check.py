"""Confere as listas dos decks base: total de cartas e, no Scryfall, se cada
carta existe e é legal no formato do deck.

    python -I tool/precons/check.py
"""
import json
import pathlib
import re
import sys
import time
import urllib.request

SRC = pathlib.Path(__file__).parents[2] / 'assets' / 'precons'
FORMATS = {'fdc_': ('commander', 100), 'modern_': ('modern', 60)}
BASIC = {'Plains', 'Island', 'Swamp', 'Mountain', 'Forest'}


def parse(path):
    cards = []
    for line in path.read_text(encoding='utf-8').splitlines():
        m = re.match(r'^(\d+)\s+(.+)$', line.strip())
        if m:
            cards.append((int(m.group(1)), m.group(2)))
    return cards


def scryfall(names):
    out = {}
    for i in range(0, len(names), 75):
        body = json.dumps({'identifiers': [{'name': n} for n in names[i:i + 75]]}).encode()
        req = urllib.request.Request('https://api.scryfall.com/cards/collection', data=body, headers={
            'Content-Type': 'application/json', 'User-Agent': 'EDHere-precons/1.0', 'Accept': 'application/json'})
        data = json.load(urllib.request.urlopen(req))
        for c in data['data']:
            out[c['name'].lower()] = c
            # Cartas de duas faces: aceita também o nome da frente.
            out[c['name'].split(' // ')[0].lower()] = c
        for nf in data.get('not_found', []):
            out.setdefault(nf['name'].lower(), None)
        time.sleep(0.15)
    return out


ok = True
for path in sorted(SRC.glob('*.txt')):
    fmt, size = next(v for k, v in FORMATS.items() if path.name.startswith(k))
    cards = parse(path)
    total = sum(q for q, _ in cards)
    names = sorted({n for _, n in cards})
    found = scryfall(names)
    problems = []
    if total != size:
        problems.append(f'{total} cartas (devia ter {size})')
    for q, n in cards:
        c = found.get(n.lower())
        if c is None:
            problems.append(f'não existe: {n}')
            continue
        legal = c['legalities'].get(fmt)
        if legal not in ('legal', 'restricted'):
            problems.append(f'{legal} em {fmt}: {n}')
        if fmt == 'modern' and q > 4 and n not in BASIC:
            problems.append(f'mais de 4: {n}')
        if fmt == 'commander' and q > 1 and n not in BASIC:
            problems.append(f'repetida: {n}')
    print(f'{path.name}: {total} cartas, {len(names)} nomes' + ('' if not problems else ''))
    for p in problems:
        ok = False
        print('   ', p)
sys.exit(0 if ok else 1)
