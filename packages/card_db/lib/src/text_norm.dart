const Map<String, String> _fold = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n', 'ý': 'y', 'ÿ': 'y', 'š': 's', 'ž': 'z',
  'æ': 'ae', 'œ': 'oe', 'ß': 'ss',
  '’': "'", '‘': "'", '“': '"', '”': '"', '–': '-', '—': '-',
};

/// Forma normalizada de um nome para comparações: minúsculas, sem acentos,
/// apóstrofos retos e espaços simples. "Æther Vial" -> "aether vial".
String normalizeName(String s) {
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    out.write(_fold[ch] ?? ch);
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
