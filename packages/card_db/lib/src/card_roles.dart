import 'card.dart';
import 'deck.dart';

/// O papel de uma carta num deck, pelo texto de regras (a ideia das etiquetas
/// do Grimório, github.com/hubertdungen/grimorio). É uma estimativa: chega
/// para contar rampa, compra e remoção, não para julgar uma carta.
enum CardRole { ramp, draw, removal, wipe, tutor }

class CardRoles {
  CardRoles._();

  static final _ramp = [
    RegExp(r'search your library for [^.]*\b(lands?|plains|islands?|swamps?|mountains?|forests?)\b[^.]*onto the battlefield'),
    RegExp(r'put (a|up to \w+) land cards? from your hand onto the battlefield'),
    RegExp(r'play an additional land|play (two|three) additional lands'),
    RegExp(r'create (a|an|two|three|x|\w+) (tapped )?treasure tokens?'),
  ];
  static final _draw = [
    RegExp(r'\bdraws? (a|an|two|three|four|five|seven|x|that many|\w+) (additional )?cards?\b'),
    RegExp(r'\bdraws? cards equal to\b'),
  ];
  static final _removal = [
    // "exila uma criatura tua e devolve-a" (Ephemerate) não é remoção
    RegExp(r'\b(destroy|exile) (up to (one|two|three|x) )?(another )?target (?!cards?\b|players?\b|spells?\b)'
        r"(?![^.]*\byou (control|own)\b)"),
    RegExp(r'\bdeals? (\d+|x|damage equal to [^.]*?) damage to (any target|target creature|target planeswalker|'
        r'target (attacking|blocking|tapped|nonland|creature or|artifact or))'),
    RegExp(r'\bdeals? damage equal to [^.]*? to (any target|target creature)'),
    RegExp(r"return (up to one )?target (nonland )?(creature|permanent|artifact|enchantment)[^.]*? to (its|their) owner'?s'? hands?"),
    RegExp(r'target creature (an opponent controls )?gets -(\d+|x)/-(\d+|x)'),
    RegExp(r'(target player|target opponent|each opponent) sacrifices (a|an) (creature|permanent|nonland)'),
    RegExp(r'\bcounter target\b'),
    RegExp(r'\bfights? (up to one )?(another )?target creature'),
  ];
  static final _wipe = [
    RegExp(r'\b(destroy|exile) all (other )?(nontoken |nonland |non-\w+ |\w+ )*(creatures|permanents|artifacts|enchantments|planeswalkers)'),
    RegExp(r'\breturn all (nonland |other )?(creatures|permanents|nonland permanents) to'),
    RegExp(r'\bdeals? (\d+|x) damage to each (other )?creature'),
    RegExp(r'\ball (other )?creatures get -(\d+|x)/-(\d+|x)'),
    RegExp(r'\beach player sacrifices (all|\w+) (creatures|nonland permanents|permanents)'),
  ];
  // "a card named X" (Elvish Clancaller, Rat Colony...) só procura cópias de si
  static final _tutor = RegExp(r'search your library for ([^.]*?)\bcards?\b(?! named)');

  static String _text(Card c) => [c.oracleText, for (final f in c.faces) f.oracleText]
      .join('\n')
      // sem o texto de lembrete
      .replaceAll(RegExp(r'\([^)]*\)'), '')
      .toLowerCase();

  /// Os papéis de uma carta (pode ter vários, ou nenhum).
  static Set<CardRole> of(Card c) => ofText(_text(c),
      isLand: c.isLand,
      producesMana: c.producedMana.isNotEmpty,
      permanent: !c.frontType.contains('Instant') && !c.frontType.contains('Sorcery'));

  /// O mesmo, a partir do texto já em minúsculas (para testar).
  static Set<CardRole> ofText(String t, {bool isLand = false, bool producesMana = false, bool permanent = true}) {
    final r = <CardRole>{};
    // os terrenos não contam: fazem parte da conta dos terrenos
    if (isLand) return r;
    if ((producesMana && permanent) || _ramp.any((x) => x.hasMatch(t))) r.add(CardRole.ramp);
    if (_draw.any((x) => x.hasMatch(t))) r.add(CardRole.draw);
    final wipe = _wipe.any((x) => x.hasMatch(t)) && !RegExp(r'all (\w+ )*lands\b').hasMatch(t);
    if (wipe) r.add(CardRole.wipe);
    if (_removal.any((x) => x.hasMatch(t))) r.add(CardRole.removal);
    for (final m in _tutor.allMatches(t)) {
      final what = m[1]!;
      // procurar terrenos é rampa (ou consertar a mana), não tutor
      if (!RegExp(r'\b(land|plains|island|swamp|mountain|forest)\b').hasMatch(what) || what.contains('nonland')) {
        r.add(CardRole.tutor);
        break;
      }
    }
    return r;
  }

  /// As cartas de cada papel no deck (um nome por cópia), por omissão no
  /// principal e na zona de comando.
  static Map<CardRole, List<String>> count(Deck deck, Map<String, Card> cards,
      {Set<Board> boards = const {Board.main, Board.command}}) {
    final out = {for (final r in CardRole.values) r: <String>[]};
    for (final e in deck.entries) {
      if (!boards.contains(e.board)) continue;
      final c = cards[e.oracleId];
      if (c == null) continue;
      for (final r in of(c)) {
        for (var i = 0; i < e.qty; i++) {
          out[r]!.add(c.name);
        }
      }
    }
    return out;
  }

  /// O que se costuma pôr num deck de Commander de 100 cartas (o modelo
  /// "8x8" / Command Zone): mínimo e máximo de cada papel.
  static const commanderRange = {
    CardRole.ramp: (8, 12),
    CardRole.draw: (8, 12),
    CardRole.removal: (7, 12),
    CardRole.wipe: (2, 4),
  };

  /// Valor de uma carta para um bot de draft (Limited): a remoção e as
  /// criaturas fazem os decks; as cartas muito caras, menos.
  static double limitedValue(Card c) {
    final roles = of(c);
    var v = 0.0;
    if (roles.contains(CardRole.removal) || roles.contains(CardRole.wipe)) v += 2.5;
    if (c.frontType.contains('Creature')) v += 1;
    if (roles.contains(CardRole.draw)) v += 0.5;
    if (c.isLand && !c.isBasicLand) v -= 0.5;
    if (c.mv >= 6) v -= 1;
    return v;
  }
}
