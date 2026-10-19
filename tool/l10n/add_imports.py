"""Acrescenta o import de l10n aos ficheiros que usam tr() (e i18n.dart nos pacotes)."""
import glob
import os
import re

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))


def add_import(path, imp):
    s = open(path, encoding='utf-8').read()
    if imp in s:
        return
    ms = list(re.finditer(r"^import [^\n]+;\n", s, re.M))
    if ms:
        i = ms[-1].end()
        s = s[:i] + imp + s[i:]
    else:
        s = imp + '\n' + s
    open(path, 'w', encoding='utf-8', newline='').write(s)


for f in glob.glob('lib/**/*.dart', recursive=True):
    f = f.replace(os.sep, '/')
    if f.startswith('lib/l10n/'):
        continue
    s = open(f, encoding='utf-8').read()
    if not re.search(r'\btr\(', s) or 'l10n/l10n.dart' in s:
        continue
    rel = os.path.relpath('lib/l10n/l10n.dart', os.path.dirname(f)).replace(os.sep, '/')
    add_import(f, f"import '{rel}';\n")

for pkg, fn in (('mesa_core', 'mesaTr'), ('card_db', 'cardDbTr')):
    for f in glob.glob(f'packages/{pkg}/lib/src/*.dart'):
        s = open(f, encoding='utf-8').read()
        if re.search(rf'\b{fn}\(', s) and not f.endswith('i18n.dart'):
            add_import(f, "import 'i18n.dart';\n")
