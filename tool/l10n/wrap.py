"""Envolve os textos visíveis do código Dart numa chamada de tradução.

Uso: python -I tool/l10n/wrap.py FUNC ficheiro.dart [...]

Cada sequência de literais (adjacentes) que pareça texto para o utilizador
passa a FUNC('...'). A interpolação vira marcadores: '$n cartas' ->
FUNC('{n} cartas', {'n': n}). Fica de fora o que parece chave, caminho,
identificador, padrão de switch, chave de mapa ou argumento de métodos de
texto (contains, split...). É uma ajuda: o resultado revê-se à mão.
"""
import re
import sys

SKIP_CALLS = (
    'contains', 'startsWith', 'endsWith', 'split', 'join', 'indexOf', 'replaceAll', 'replaceFirst',
    'RegExp', 'getString', 'setString', 'getBool', 'setBool', 'getInt', 'setInt', 'getDouble',
    'setDouble', 'getStringList', 'setStringList', 'remove', 'containsKey', 'Key', 'ValueKey',
    'debugPrint', 'print', 'Uri', 'parse', 'tryParse', 'loadString', 'asset', 'AssetImage', 'Image',
    'SvgPicture', 'Intent', 'byId', 'byCode', 'MethodChannel', 'EventChannel', 'fromEnvironment',
    'padLeft', 'padRight', 'fontFamily', 'firstWhere', 'where', 'lookup', 'query', 'execute', 'select',
    'prepare', 'tr', 'mesaTr', 'cardDbTr', 'File', 'Directory', 'join', 'extension', 'basename',
    'withName', 'named', 'get', 'post', 'Duration', 'Locale', '_has', 'hasMatch', 'firstMatch', 'allMatches',
)
SKIP_NAMED = ('fontFamily', 'package', 'heroTag', 'restorationId', 'key', 'id', 'kind', 'type', 'route',
              'asset', 'path', 'name', 'code', 'scheme', 'host', 'mime', 'mimeType', 'extension',
              'allowedExtensions', 'fileName', 'serviceType', 'pos', 'format')


class Lit:
    def __init__(self, start, end, raw, parts, quote):
        self.start, self.end, self.raw, self.parts, self.quote = start, end, raw, parts, quote


def scan_string(src, i):
    """Lê um literal a partir de src[i] (prefixo r opcional). Devolve (fim, partes, raw, quote)
    em que partes é uma lista de ('t', texto) e ('e', expressão)."""
    raw = False
    if src[i] in 'rR':
        raw = True
        i += 1
    q = src[i]
    triple = src[i:i + 3] == q * 3
    qq = q * 3 if triple else q
    i += len(qq)
    parts = []
    buf = []
    while True:
        if src.startswith(qq, i):
            i += len(qq)
            break
        c = src[i]
        if c == '\\' and not raw:
            buf.append(src[i:i + 2])
            i += 2
            continue
        if c == '$' and not raw:
            if src[i + 1] == '{':
                depth = 1
                j = i + 2
                while depth:
                    if src[j] in '\'"':
                        j, _, _, _ = scan_string(src, j)
                        continue
                    if src[j] == '{':
                        depth += 1
                    elif src[j] == '}':
                        depth -= 1
                    j += 1
                if buf:
                    parts.append(('t', ''.join(buf)))
                    buf = []
                parts.append(('e', src[i + 2:j - 1]))
                i = j
                continue
            m = re.match(r'[A-Za-z_][A-Za-z0-9_]*', src[i + 1:])
            if m:
                if buf:
                    parts.append(('t', ''.join(buf)))
                    buf = []
                parts.append(('e', m.group(0)))
                i += 1 + len(m.group(0))
                continue
        buf.append(c)
        i += 1
    if buf:
        parts.append(('t', ''.join(buf)))
    return i, parts, raw, qq


def tokens(src):
    """Os literais de topo (fora de comentários), com posições."""
    i = 0
    n = len(src)
    out = []
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if src.startswith('/*', i):
            i = src.find('*/', i) + 2
            continue
        if c in '\'"' or (c in 'rR' and i + 1 < n and src[i + 1] in '\'"' and not (i > 0 and (src[i - 1].isalnum() or src[i - 1] == '_'))):
            end, parts, raw, qq = scan_string(src, i)
            out.append(Lit(i, end, raw, parts, qq))
            i = end
            continue
        i += 1
    return out


def groups(src, lits):
    """Junta literais adjacentes (só espaço entre eles)."""
    gs = []
    for l in lits:
        if gs and src[gs[-1][-1].end:l.start].strip() == '':
            gs[-1].append(l)
        else:
            gs.append([l])
    return gs


def text_of(g):
    return ''.join(t for l in g for k, t in l.parts if k == 't')


def looks_visible(g):
    if any(l.raw for l in g):
        return False
    t = text_of(g)
    letters = re.sub(r'[^A-Za-zÀ-ÿ]', '', t)
    if len(letters) < 2:
        return False
    if re.search(r'[À-ÿ]', t):
        return True
    if re.fullmatch(r'[a-z0-9_.:/#@\-+*=<>%&|,;\[\]()!?\s{}]*', t) and ' ' not in t:
        return False  # chave, id, caminho
    if re.match(r'^(assets/|https?:|package:|dart:)', t):
        return False
    if re.fullmatch(r'[A-Z0-9_]+', t):
        return False  # constante
    return True


def prev_token(src, pos):
    j = pos - 1
    while j >= 0 and src[j] in ' \t\r\n':
        j -= 1
    return j


def context_skip(src, g):
    s, e = g[0].start, g[-1].end
    line_start = src.rfind('\n', 0, s) + 1
    line = src[line_start:s]
    if re.match(r'\s*(import|export|part|library)\b', line):
        return True
    # Depois do literal.
    k = e
    while k < len(src) and src[k] in ' \t\r\n':
        k += 1
    after = src[k:k + 2]
    pj = prev_token(src, s)
    before = src[max(0, pj - 40):pj + 1]
    if after.startswith('=>') and not before.rstrip().endswith('=>'):
        return True  # padrão de switch
    if after.startswith('==') or before.endswith('==') or before.endswith('!='):
        return True
    if after[:1] == ':' and (before.endswith('{') or before.endswith(',') or re.search(r'\bcase$', before)):
        return True  # chave de mapa ou case
    if before.endswith('[') and after[:1] == ']':
        return True  # índice
    if before.endswith('||') or after.startswith('||'):
        return True  # padrões combinados
    m = re.search(r'([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*$', before)
    if m and m.group(1) in SKIP_CALLS:
        return True
    m = re.search(r'([A-Za-z_][A-Za-z0-9_]*)\s*:\s*$', before)
    if m and m.group(1) in SKIP_NAMED:
        return True
    if re.search(r'@\w*\(?\s*$', before):
        return True
    return False


def placeholder_name(expr, used):
    m = re.fullmatch(r'\s*([A-Za-z_][A-Za-z0-9_]*)\s*', expr)
    base = None
    if m:
        base = m.group(1)
    else:
        m = re.search(r'\.([A-Za-z_][A-Za-z0-9_]*)\s*$', expr)
        if m and m.group(1) not in ('length', 'name', 'toString', 'label'):
            base = m.group(1)
        elif m and m.group(1) in ('length',):
            base = 'n'
    if not base or base in ('this',):
        base = 'v'
    base = base.lstrip('_') or 'v'
    name = base
    k = 2
    while name in used and used[name] != expr.strip():
        name = f'{base}{k}'
        k += 1
    used[name] = expr.strip()
    return name


def escape_text(t, q):
    return t


def build(src, g, func):
    used = {}
    pieces = []
    for l in g:
        for k, t in l.parts:
            if k == 't':
                pieces.append(t)
            else:
                pieces.append('{' + placeholder_name(t, used) + '}')
    key = ''.join(pieces)
    q = g[0].quote
    if q in ("'''", '"""'):
        lit = q + key + q
    else:
        # Mantém as quebras de linha dos literais longos: um literal por bocado original.
        lit = q + key + q
    if used:
        args = ', '.join(f"'{n}': {transform(e, func)}" for n, e in used.items())
        return f'{func}({lit}, {{{args}}})'
    return f'{func}({lit})'


def transform(src, func):
    lits = tokens(src)
    out = []
    last = 0
    for g in groups(src, lits):
        if looks_visible(g) and not context_skip(src, g):
            out.append(src[last:g[0].start])
            out.append(build(src, g, func))
            last = g[-1].end
    out.append(src[last:])
    return ''.join(out)


if __name__ == '__main__':
    func = sys.argv[1]
    for path in sys.argv[2:]:
        s = open(path, encoding='utf-8').read()
        t = transform(s, func)
        if t != s:
            open(path, 'w', encoding='utf-8', newline='').write(t)
            print('changed', path)
