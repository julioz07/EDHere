"""Gera lib/ui/widgets/set_glyphs.dart a partir do keyrune.css do projeto Keyrune.

Uso: python -I tool/gen_keyrune_glyphs.py caminho/para/keyrune.css

Fonte: https://github.com/andrewgioia/keyrune (fonte SIL OFL 1.1, ícones e código GPL 3.0).
A fonte em si está em assets/fonts/keyrune.ttf. Para um set novo: atualizar a
fonte e o CSS para a versão mais recente e voltar a correr este script.
"""
import re
import sys

# Sem comentários: "/* 2026 Sets */" antes de um seletor estragava esse seletor.
css = re.sub(r'/\*.*?\*/', '', open(sys.argv[1], encoding='utf8').read(), flags=re.S)
glyphs = {}
for m in re.finditer(r'([^{}]+)\{([^}]*)\}', css):
    selectors, body = m.group(1), m.group(2)
    c = re.search(r'content:\s*"\\([0-9a-fA-F]+)"', body)
    if not c:
        continue
    for s in selectors.split(','):
        mm = re.fullmatch(r'\.ss-([a-z0-9]+)::?before', s.strip())
        if mm and mm.group(1) not in glyphs:
            glyphs[mm.group(1)] = int(c.group(1), 16)

out = [
    '// GERADO a partir do keyrune.css (Keyrune, de Andrew Gioia; fonte SIL OFL 1.1).',
    '// Não editar à mão: python -I tool/gen_keyrune_glyphs.py keyrune.css',
    '',
    '/// Código do set em minúsculas (classe "ss-" sem o prefixo) -> caractere na fonte Keyrune.',
    'const Map<String, int> setGlyphs = {',
]
for k in sorted(glyphs):
    out.append(f"  '{k}': 0x{glyphs[k]:x},")
out.append('};')
with open('lib/ui/widgets/set_glyphs.dart', 'w', encoding='utf8', newline='\n') as f:
    f.write('\n'.join(out) + '\n')
print(len(glyphs), 'símbolos')
