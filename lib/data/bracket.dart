import 'package:card_db/card_db.dart';

/// Estimativa do bracket de Commander a partir das cartas do deck.
///
/// Olha para a lista oficial de Game Changers (marcada pela Scryfall) e, pelo
/// texto das cartas, para turnos extra e destruição de terrenos em massa.
/// Combos de duas cartas não se detetam pela lista: por isso é um mínimo,
/// para começar a conversa da "regra zero".
class BracketEstimate {
  const BracketEstimate(this.gameChangers, {this.extraTurns = const [], this.landDenial = const []});

  /// Nomes dos Game Changers no deck (comandante incluído).
  final List<String> gameChangers;

  /// Cartas que dão turnos extra (nos brackets 1–3 não se encadeiam).
  final List<String> extraTurns;

  /// Destruição (ou bloqueio) de terrenos em massa: só nos brackets 4–5.
  final List<String> landDenial;

  int get count => gameChangers.length;

  /// Vários turnos extra: arrisca encadear, o que os brackets 1–3 não querem.
  bool get chainsExtraTurns => extraTurns.length >= 2;

  /// Bracket mínimo: sem Game Changers cabe no 1–2; até 3 no 3; mais de 3,
  /// ou destruição de terrenos em massa, no 4 ou 5.
  int get minimum {
    if (landDenial.isNotEmpty || count > 3) return 4;
    return count == 0 ? 2 : 3;
  }

  String get label => switch (minimum) {
        2 => '1–2 (Exhibition / Core)',
        3 => '3 (Upgraded)',
        _ => '4+ (Optimized / cEDH)',
      };

  /// Rótulo curto, para o lobby.
  String get short => switch (minimum) {
        2 => 'bracket 1–2',
        3 => 'bracket 3',
        _ => 'bracket 4+',
      };

  static final _extraTurn = RegExp(r'takes? an extra turn|extra turn after this one', caseSensitive: false);
  static final _landDenial = RegExp(
    r"(destroy|exile) all [^.]*lands|return all lands|each player sacrifices [^.]*lands|"
    r"can't untap more than (one|two) lands?|lands don't untap",
    caseSensitive: false,
  );

  /// Se o texto de uma carta é de turno extra (sem contar o texto de lembrete).
  static bool isExtraTurn(Card c) => _extraTurn.hasMatch(_rules(c));

  /// Se o texto de uma carta é de destruição de terrenos em massa.
  static bool isLandDenial(Card c) => _landDenial.hasMatch(_rules(c));

  static String _rules(Card c) => [
        c.oracleText,
        for (final f in c.faces) f.oracleText,
      ].join('\n').replaceAll(RegExp(r'\([^)]*\)'), '');

  static BracketEstimate of(Deck deck, Map<String, Card> cards) {
    final list = [
      for (final e in deck.entries.where((e) => e.board == Board.main || e.board == Board.command))
        if (cards[e.oracleId] case final c?) c,
    ];
    return BracketEstimate(
      [for (final c in list) if (c.gameChanger) c.name],
      extraTurns: [for (final c in list) if (isExtraTurn(c)) c.name],
      landDenial: [for (final c in list) if (isLandDenial(c)) c.name],
    );
  }
}
