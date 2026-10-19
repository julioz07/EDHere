import 'card.dart';
import 'colors.dart';
import 'deck.dart';
import 'formats.dart';
import 'i18n.dart';

enum IssueLevel { error, warning }

/// Problema encontrado num deck. São avisos: a app nunca impede de jogar.
class DeckIssue {
  const DeckIssue(this.level, this.message, {this.oracleId});
  final IssueLevel level;
  final String message;
  final String? oracleId;

  @override
  String toString() => message;
}

/// Valida um deck segundo as regras do formato.
///
/// [cards] tem de conter todas as cartas do deck; [legality] tem o estado
/// de cada carta no formato (`legal`, `banned`, `restricted`; ausente =
/// não legal).
List<DeckIssue> validateDeck(
  Deck deck,
  GameFormat format,
  Map<String, Card> cards,
  Map<String, String> legality,
) {
  if (!format.validates) return const [];
  final issues = <DeckIssue>[];
  void err(String m, [String? id]) => issues.add(DeckIssue(IssueLevel.error, m, oracleId: id));
  void warn(String m, [String? id]) =>
      issues.add(DeckIssue(IssueLevel.warning, m, oracleId: id));

  final command = deck.inBoard(Board.command).toList();
  final commanderCards = [for (final e in command) cards[e.oracleId]].whereType<Card>().toList();

  // Zona de comando.
  var identity = ManaColors.all;
  if (format.commandZone == CommandZone.commander) {
    if (command.isEmpty) {
      err(cardDbTr('Falta escolher o comandante.'));
    } else {
      _checkCommanders(commanderCards, format, err);
      identity = commanderCards.fold(0, (m, c) => m | c.identityMask);
      // The Prismatic Piper / Faceless One: ficam da cor escolhida antes do
      // jogo, por isso o deck pode ter mais uma cor à escolha.
      if (commanderCards.any((c) => isDraftWildCommander(c.name))) {
        final extra = deck.entries
                .where((e) => e.board == Board.main)
                .map((e) => cards[e.oracleId]?.identityMask ?? 0)
                .fold(0, (m, x) => m | x) &
            ~identity;
        if (_bits(extra) <= 1) identity |= extra;
      }
    }
  } else if (format.commandZone == CommandZone.oathbreaker) {
    final walkers = commanderCards.where((c) => c.frontType.contains('Planeswalker')).toList();
    final spells = commanderCards
        .where((c) => c.frontType.contains('Instant') || c.frontType.contains('Sorcery'))
        .toList();
    if (walkers.length != 1) err(cardDbTr('Oathbreaker precisa de exatamente um planeswalker na zona de comando.'));
    if (spells.length != 1) err(cardDbTr('Oathbreaker precisa de exatamente um signature spell (instantâneo ou feitiço).'));
    if (walkers.isNotEmpty) identity = walkers.first.identityMask;
    for (final s in spells) {
      if (s.identityMask & ~identity != 0) {
        err(cardDbTr('O signature spell {v} está fora da identidade de cor do oathbreaker.', {'v': s.name}), s.oracleId);
      }
    }
  } else if (command.isNotEmpty) {
    warn(cardDbTr('Este formato não tem zona de comando; as cartas lá contam como fora do deck.'));
  }

  // Tamanho.
  final size = format.hasCommandZone ? deck.playableCount : deck.count(Board.main);
  if (format.exactDeck != null && size != format.exactDeck) {
    err(cardDbTr('O deck tem {size} cartas; {v} pede exatamente {exactDeck}.', {'size': size, 'v': format.label, 'exactDeck': format.exactDeck}));
  }
  if (format.minDeck != null && size < format.minDeck!) {
    err(cardDbTr('O deck tem {size} cartas; {v} pede pelo menos {minDeck}.', {'size': size, 'v': format.label, 'minDeck': format.minDeck}));
  }
  if (format.maxSideboard != null && deck.count(Board.side) > format.maxSideboard!) {
    err(cardDbTr('O sideboard tem {v} cartas; o máximo é {maxSideboard}.', {'v': deck.count(Board.side), 'maxSideboard': format.maxSideboard}));
  }

  // Cópias, legalidade e identidade, por carta.
  final countBoards = format.hasCommandZone
      ? const [Board.command, Board.main]
      : const [Board.main, Board.side];
  final copies = <String, int>{};
  for (final e in deck.entries.where((e) => countBoards.contains(e.board))) {
    copies[e.oracleId] = (copies[e.oracleId] ?? 0) + e.qty;
  }
  for (final MapEntry(key: id, value: n) in copies.entries) {
    final card = cards[id];
    if (card == null) {
      warn(cardDbTr('Carta desconhecida na base local ({id}).', {'id': id}), id);
      continue;
    }
    final status = legality[id];
    final limit = status == 'restricted' ? 1 : card.copyLimit(format.maxCopies);
    if (limit != null && n > limit) {
      err(format.isSingleton && limit == 1
          ? cardDbTr('{v}: {n} cópias num formato singleton.', {'v': card.name, 'n': n})
          : cardDbTr('{v}: {n} cópias; o máximo é {limit}.', {'v': card.name, 'n': n, 'limit': limit}), id);
    }
    if (status == 'banned') {
      err(cardDbTr('{v} está banida em {v2}.', {'v': card.name, 'v2': format.label}), id);
    } else if (status == null && format.legalityKey != null) {
      // Formatos sem lista de legalidade (Limited) aceitam tudo o que sai.
      err(cardDbTr('{v} não é legal em {v2}.', {'v': card.name, 'v2': format.label}), id);
    }
    if (format.hasCommandZone &&
        commanderCards.isNotEmpty &&
        card.identityMask & ~identity != 0) {
      err(cardDbTr('{v} está fora da identidade de cor do comandante.', {'v': card.name}), id);
    }
  }
  return issues;
}

void _checkCommanders(
    List<Card> cmds, GameFormat format, void Function(String, [String?]) err) {
  for (final c in cmds) {
    final ok = c.canBeCommander ||
        (format.commanderMayBePlaneswalker && c.isLegendary && c.frontType.contains('Planeswalker')) ||
        (cmds.length == 2 && _isBackground(c));
    if (!ok) err(cardDbTr('{v} não pode ser comandante.', {'v': c.name}), c.oracleId);
  }
  if (cmds.length > 2) {
    err(cardDbTr('No máximo dois comandantes (parceiros).'));
  } else if (cmds.length == 2 &&
      !canPartner(cmds[0], cmds[1]) &&
      // No commander draft, duas lendas monocolores também podem.
      !(format.id == 'commanderdraft' && cmds.every((c) => c.canBeCommander && _bits(c.colorMask) == 1))) {
    err(cardDbTr('{v} e {v2} não podem ser comandantes juntos (precisam de Partner, Friends forever, Background ou Doctor\'s companion).', {'v': cmds[0].name, 'v2': cmds[1].name}));
  }
}

bool _isBackground(Card c) => c.frontType.contains('Background');
int _bits(int m) {
  var n = 0;
  for (var x = m; x != 0; x &= x - 1) {
    n++;
  }
  return n;
}

/// Comandantes que o commander draft deixa sempre usar, mesmo sem os tirar.
const draftWildCommanders = ['The Prismatic Piper', 'Faceless One'];
bool isDraftWildCommander(String name) => draftWildCommanders.contains(name);
bool _has(Card c, String kw) =>
    c.keywords.any((k) => k.toLowerCase() == kw.toLowerCase()) || c.oracleText.contains(kw);

/// Se [a] e [b] podem ser comandantes juntos (Partner, Partner with,
/// Friends forever, Background, Doctor's companion).
bool canPartner(Card a, Card b) {
  // "Partner with X" só com X; "Partner" genérico com outro "Partner".
  final pw = RegExp(r'Partner with ([^\n(]+)');
  final aw = pw.firstMatch(a.oracleText)?.group(1)?.trim();
  final bw = pw.firstMatch(b.oracleText)?.group(1)?.trim();
  if (aw != null || bw != null) return aw == b.name && bw == a.name;
  bool plainPartner(Card c) => RegExp(r'(^|\n)Partner( \(|$|\n)').hasMatch(c.oracleText);
  if (plainPartner(a) && plainPartner(b)) return true;
  if (_has(a, 'Friends forever') && _has(b, 'Friends forever')) return true;
  if (_has(a, 'Choose a Background') && _isBackground(b)) return true;
  if (_has(b, 'Choose a Background') && _isBackground(a)) return true;
  bool doctor(Card c) => c.frontType.contains('Time Lord Doctor');
  if (_has(a, "Doctor's companion") && doctor(b)) return true;
  if (_has(b, "Doctor's companion") && doctor(a)) return true;
  // Variantes recentes com o mesmo nome de grupo ("Partner—Survivors").
  final group = RegExp(r'Partner—([A-Za-z \-]+)');
  final ga = group.firstMatch(a.oracleText)?.group(1);
  final gb = group.firstMatch(b.oracleText)?.group(1);
  return ga != null && ga == gb;
}
