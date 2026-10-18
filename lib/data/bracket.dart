import 'package:card_db/card_db.dart';

/// Estimativa do bracket de Commander a partir dos Game Changers do deck.
///
/// Só olha para a lista oficial de Game Changers (marcada pela Scryfall).
/// Combos de duas cartas, destruição de terrenos em massa e turnos extra
/// também contam nos brackets, mas não se detetam pela lista de cartas: por
/// isso é um mínimo, para começar a conversa da "regra zero".
class BracketEstimate {
  const BracketEstimate(this.gameChangers);

  /// Nomes dos Game Changers no deck (comandante incluído).
  final List<String> gameChangers;

  int get count => gameChangers.length;

  /// Bracket mínimo pelas regras: sem Game Changers cabe no 1–2; até 3 no
  /// 3; mais de 3 no 4 ou 5.
  int get minimum => count == 0 ? 2 : (count <= 3 ? 3 : 4);

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

  static BracketEstimate of(Deck deck, Map<String, Card> cards) => BracketEstimate([
        for (final e in deck.entries.where((e) => e.board == Board.main || e.board == Board.command))
          if (cards[e.oracleId] case final c? when c.gameChanger) c.name,
      ]);
}
