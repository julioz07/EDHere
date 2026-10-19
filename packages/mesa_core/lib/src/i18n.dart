/// Tradução dos textos deste pacote (o registo, as mensagens). O texto está
/// em português e a app troca esta função pela da língua escolhida.
/// `{nome}` no texto é trocado por `args['nome']`.
String Function(String pt, [Map<String, Object?>? args]) mesaTr = _portuguese;

String _portuguese(String pt, [Map<String, Object?>? args]) {
  var s = pt;
  if (args != null) {
    for (final e in args.entries) {
      s = s.replaceAll('{${e.key}}', '${e.value}');
    }
  }
  return s;
}
