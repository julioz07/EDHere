/// Cores de Magic como máscara de bits: W=1, U=2, B=4, R=8, G=16.
abstract final class ManaColors {
  static const w = 1, u = 2, b = 4, r = 8, g = 16;
  static const all = 31;
  static const order = 'WUBRG';

  static int maskOf(Iterable<String> letters) {
    var m = 0;
    for (final l in letters) {
      final i = order.indexOf(l.toUpperCase());
      if (i >= 0) m |= 1 << i;
    }
    return m;
  }

  static List<String> lettersOf(int mask) => [
        for (var i = 0; i < 5; i++)
          if (mask & (1 << i) != 0) order[i],
      ];

  static int count(int mask) {
    var c = 0;
    for (var m = mask; m != 0; m >>= 1) {
      c += m & 1;
    }
    return c;
  }

  /// Nomes aceites na pesquisa (`c:azorius`, `id:esper`, `c:red`...).
  static const Map<String, String> named = {
    'white': 'w', 'blue': 'u', 'black': 'b', 'red': 'r', 'green': 'g',
    'branco': 'w', 'azul': 'u', 'preto': 'b', 'vermelho': 'r', 'verde': 'g',
    'azorius': 'wu', 'dimir': 'ub', 'rakdos': 'br', 'gruul': 'rg', 'selesnya': 'gw',
    'orzhov': 'wb', 'izzet': 'ur', 'golgari': 'bg', 'boros': 'rw', 'simic': 'gu',
    'bant': 'gwu', 'esper': 'wub', 'grixis': 'ubr', 'jund': 'brg', 'naya': 'rgw',
    'abzan': 'wbg', 'jeskai': 'urw', 'sultai': 'bgu', 'mardu': 'rwb', 'temur': 'gur',
    'chaos': 'ubrg', 'aggression': 'wbrg', 'altruism': 'wrgu', 'growth': 'wubg',
    'artifice': 'wubr', 'wubrg': 'wubrg', 'fivecolor': 'wubrg',
  };
}
