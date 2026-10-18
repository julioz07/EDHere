"""Gera os dados de boosters e de JumpStart que vão dentro da app.

Fonte: MTGJSON (licença MIT), https://mtgjson.com
- Para cada set com boosters (play, draft ou default), guarda as configurações
  exatas (quantas cartas de cada folha, com pesos) e as folhas de cartas.
- Para os pacotes JumpStart, guarda a lista de cartas de cada pacote.

Cada carta fica só com o id do Scryfall (para a imagem), o índice do oracle id
(para o texto, que vem da base de cartas da app), a raridade e o número.

Uso (no PC, com internet):
    python tool/boosters/build_boosters.py            # descarrega o que falta e gera
    python tool/boosters/build_boosters.py --offline  # só gera, com o que já está em cache

A cache fica em tool/boosters/.cache (fora do git).
"""

import gzip
import json
import os
import sys
import time
import urllib.request
from datetime import date

ROOT = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(ROOT, '.cache')
OUT = os.path.join(ROOT, '..', '..', 'assets', 'boosters')
API = 'https://mtgjson.com/api/v5'
UA = {'User-Agent': 'EDHere-build/1.0'}

# Tipos de set que têm boosters a sério.
SET_TYPES = {'core', 'expansion', 'draft_innovation', 'masters', 'starter', 'funny'}
# Ordem de preferência do tipo de booster para draft e sealed.
BOOSTER_KINDS = ['play', 'draft', 'default']
OFFLINE = '--offline' in sys.argv


def fetch(name, url):
    """Descarrega para a cache (uma vez) e devolve o caminho."""
    path = os.path.join(CACHE, name)
    if os.path.exists(path) or OFFLINE:
        return path if os.path.exists(path) else None
    req = urllib.request.Request(url, headers=UA)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            with open(path, 'wb') as f:
                f.write(data)
            time.sleep(0.15)
            return path
        except Exception as e:  # noqa: BLE001
            print(f'  falhou {url}: {e} (tentativa {attempt + 1})')
            time.sleep(2)
    return None


def load_json(path):
    opener = gzip.open if path.endswith('.gz') else open
    with opener(path, 'rt', encoding='utf-8') as f:
        return json.load(f)


RARITY = {'common': 'C', 'uncommon': 'U', 'rare': 'R', 'mythic': 'M', 'special': 'S', 'bonus': 'S'}


class Oracles:
    """Tabela partilhada de oracle ids (cada carta guarda só o índice)."""

    def __init__(self):
        self.ids = []
        self.index = {}

    def of(self, oracle_id):
        if oracle_id not in self.index:
            self.index[oracle_id] = len(self.ids)
            self.ids.append(oracle_id)
        return self.index[oracle_id]


def card_entry(card, oracles):
    ids = card.get('identifiers', {})
    sid = ids.get('scryfallId')
    oid = ids.get('scryfallOracleId')
    if not sid or not oid:
        return None
    return [sid, oracles.of(oid), RARITY.get(card.get('rarity'), 'C'), card.get('number', '')]


def build_sets(oracles):
    set_list = load_json(fetch('SetList.json', f'{API}/SetList.json'))['data']
    wanted = [s for s in set_list if s['type'] in SET_TYPES and not s.get('isOnlineOnly')]
    wanted.sort(key=lambda s: s.get('releaseDate', ''), reverse=True)
    index = []
    by_uuid = {}  # uuid -> entrada, para folhas que usam cartas de outros sets
    raw = {}
    for i, s in enumerate(wanted):
        code = s['code']
        path = fetch(f'{code}.json.gz', f'{API}/{code}.json.gz')
        if not path:
            continue
        print(f'[{i + 1}/{len(wanted)}] {code} {s["name"]}')
        data = load_json(path)['data']
        for c in data.get('cards', []):
            e = card_entry(c, oracles)
            if e:
                by_uuid[c['uuid']] = e
        boosters = data.get('booster') or {}
        kind = next((k for k in BOOSTER_KINDS if k in boosters), None)
        if kind:
            raw[code] = (s, kind, boosters[kind])

    os.makedirs(OUT, exist_ok=True)
    for code, (s, kind, b) in raw.items():
        prints = []
        pidx = {}

        def ref(uuid):
            e = by_uuid.get(uuid)
            if e is None:
                return None
            if uuid not in pidx:
                pidx[uuid] = len(prints)
                prints.append(e)
            return pidx[uuid]

        sheets = {}
        for name, sh in b['sheets'].items():
            cards = []
            for uuid, w in sh['cards'].items():
                r = ref(uuid)
                if r is not None:
                    cards.append([r, w])
            if cards:
                sheets[name] = {'foil': 1 if sh.get('foil') else 0, 'cards': cards}
        configs = []
        for cfg in b['boosters']:
            contents = cfg['contents']
            # Uma composição com folhas que ficaram vazias (cartas de fora) não serve.
            if all(n in sheets for n in contents):
                configs.append([cfg['weight'], contents])
        if not configs or not prints:
            continue
        size = max(sum(c[1].values()) for c in configs)
        out = {
            'code': code,
            'name': s['name'],
            'date': s.get('releaseDate', ''),
            'type': s['type'],
            'kind': kind,
            'prints': prints,
            'sheets': sheets,
            'configs': configs,
        }
        with gzip.open(os.path.join(OUT, f'set_{code.lower()}.json.gz'), 'wt', encoding='utf-8') as f:
            json.dump(out, f, separators=(',', ':'))
        index.append({'code': code, 'name': s['name'], 'date': s.get('releaseDate', ''),
                      'type': s['type'], 'kind': kind, 'size': size})
    return index


def build_jumpstart(oracles):
    decks = load_json(fetch('DeckList.json', f'{API}/DeckList.json'))['data']
    packets = [d for d in decks if d['type'] == 'Jumpstart']
    out = []
    for i, d in enumerate(packets):
        path = fetch(f'deck_{d["fileName"]}.json', f'{API}/decks/{d["fileName"]}.json')
        if not path:
            continue
        if i % 50 == 0:
            print(f'JumpStart {i + 1}/{len(packets)}')
        deck = load_json(path)['data']
        cards = []
        for c in deck.get('mainBoard', []):
            e = card_entry(c, oracles)
            if e:
                cards.append(e + [c.get('count', 1)])
        if not cards:
            continue
        # O nome vem como "Goblins 1": o tema é sem o número da variante.
        theme = d['name'].rsplit(' ', 1)[0] if d['name'].rsplit(' ', 1)[-1].isdigit() else d['name']
        out.append({'set': d['code'], 'name': d['name'], 'theme': theme,
                    'date': d.get('releaseDate', ''), 'cards': cards})
    return out


def main():
    os.makedirs(CACHE, exist_ok=True)
    oracles = Oracles()
    index = build_sets(oracles)
    jumpstart = build_jumpstart(oracles)
    with gzip.open(os.path.join(OUT, 'jumpstart.json.gz'), 'wt', encoding='utf-8') as f:
        json.dump(jumpstart, f, separators=(',', ':'))
    with gzip.open(os.path.join(OUT, 'oracles.json.gz'), 'wt', encoding='utf-8') as f:
        json.dump(oracles.ids, f, separators=(',', ':'))
    with open(os.path.join(OUT, 'index.json'), 'w', encoding='utf-8') as f:
        json.dump({'v': 1, 'generated': date.today().isoformat(),
                   'source': 'MTGJSON (MIT) — https://mtgjson.com', 'sets': index,
                   'jumpstart': len(jumpstart)}, f, ensure_ascii=False, indent=0)
    total = sum(os.path.getsize(os.path.join(OUT, n)) for n in os.listdir(OUT))
    print(f'{len(index)} sets, {len(jumpstart)} pacotes JumpStart, {len(oracles.ids)} cartas, '
          f'{total / 1024 / 1024:.1f} MB')


if __name__ == '__main__':
    main()
