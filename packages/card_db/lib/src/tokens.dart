/// Um token que uma carta cria, lido do texto ("create a 1/1 red Goblin
/// creature token" -> Goblin 1/1).
class TokenHint {
  const TokenHint(this.name, {this.pt});
  final String name;

  /// Poder/resistência ("1/1"), ou null (Treasure, Clue, X/X...).
  final String? pt;

  @override
  bool operator ==(Object other) => other is TokenHint && other.name == name && other.pt == pt;

  @override
  int get hashCode => Object.hash(name, pt);

  @override
  String toString() => pt == null ? name : '$name $pt';
}

final _create = RegExp(r"\bcreates? ([^.;:\n]*?)\btokens?\b", caseSensitive: false);
final _pt = RegExp(r'\b(\d+)/(\d+)\b');
final _capital = RegExp(r"^[A-Z][A-Za-z'\-]+$");

/// Palavras com maiúscula que não são o nome do token.
const _notNames = {'X', 'Equipment', 'Aura', 'Legendary', 'Snow', 'Basic'};

/// Tokens que um texto de regras cria. Ignora cópias ("a token that's a
/// copy of...") porque dependem da carta copiada.
List<TokenHint> tokenHintsIn(String oracleText) {
  final out = <TokenHint>[];
  for (final m in _create.allMatches(oracleText)) {
    final phrase = m.group(1)!;
    if (phrase.contains('copy')) continue;
    final pt = _pt.firstMatch(phrase);
    final words = phrase.split(RegExp(r'\s+'));
    final name = <String>[];
    for (final w in words) {
      final clean = w.replaceAll(RegExp(r'[,"]'), '');
      if (_capital.hasMatch(clean) && !_notNames.contains(clean)) {
        name.add(clean);
      } else if (name.isNotEmpty) {
        break;
      }
    }
    if (name.isEmpty) continue;
    final hint = TokenHint(name.join(' '), pt: pt == null ? null : '${pt.group(1)}/${pt.group(2)}');
    if (!out.contains(hint)) out.add(hint);
  }
  return out;
}

/// Tokens que quase todos os decks usam, para criar com um toque.
const commonTokens = [
  TokenHint('Treasure'),
  TokenHint('Clue'),
  TokenHint('Food'),
  TokenHint('Blood'),
  TokenHint('Map'),
  TokenHint('Soldier', pt: '1/1'),
  TokenHint('Zombie', pt: '2/2'),
  TokenHint('Spirit', pt: '1/1'),
  TokenHint('Goblin', pt: '1/1'),
  TokenHint('Elf Warrior', pt: '1/1'),
  TokenHint('Saproling', pt: '1/1'),
  TokenHint('Beast', pt: '3/3'),
];
