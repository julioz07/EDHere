"""Gera lib/ui/widgets/mana_glyphs.dart a partir do mana.css do projeto Mana.

Uso: python -I tool/gen_mana_glyphs.py caminho/para/mana.css

Fonte: https://github.com/andrewgioia/mana (fonte SIL OFL 1.1, CSS MIT).
A fonte em si está em assets/fonts/mana.ttf.
"""
import re
import sys

css = open(sys.argv[1], encoding='utf8').read()
glyphs = {}
for m in re.finditer(r'([^{}]+)\{([^}]*)\}', css):
    selectors, body = m.group(1), m.group(2)
    c = re.search(r'content:\s*"\\([0-9a-fA-F]+)"', body)
    if not c:
        continue
    for s in selectors.split(','):
        mm = re.fullmatch(r'\.ms-([a-z0-9-]+)::?before', s.strip())
        if mm and mm.group(1) not in glyphs:
            glyphs[mm.group(1)] = int(c.group(1), 16)

out = [
    '// GERADO a partir do mana.css (Mana, de Andrew Gioia; CSS MIT, fonte SIL OFL 1.1).',
    '// Não editar à mão: python -I tool/gen_mana_glyphs.py mana.css',
    '',
    '/// Classe do Mana (sem o prefixo "ms-") -> caractere na fonte Mana.',
    'const Map<String, int> manaGlyphs = {',
]
for k in sorted(glyphs):
    out.append(f"  '{k}': 0x{glyphs[k]:x},")
out.append('};')
with open('lib/ui/widgets/mana_glyphs.dart', 'w', encoding='utf8', newline='\n') as f:
    f.write('\n'.join(out) + '\n')
print(len(glyphs), 'símbolos')
