/// Separa um custo de mana nos seus símbolos: "{2}{W}{U/P}" -> ["2","W","U/P"].
/// Os separadores " // " de cartas divididas aparecem como "//".
List<String> parseManaSymbols(String? cost) {
  if (cost == null || cost.isEmpty) return const [];
  final out = <String>[];
  final re = RegExp(r'\{([^}]+)\}|(//)');
  for (final m in re.allMatches(cost)) {
    out.add(m.group(1) ?? '//');
  }
  return out;
}

/// Quantos símbolos de cada cor um custo tem (os híbridos contam para ambas).
Map<String, int> colorPips(String? cost) {
  final pips = <String, int>{};
  for (final s in parseManaSymbols(cost)) {
    for (final c in 'WUBRG'.split('')) {
      if (s.split('/').contains(c)) pips[c] = (pips[c] ?? 0) + 1;
    }
  }
  return pips;
}
