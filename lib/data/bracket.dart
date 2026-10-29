import 'package:card_db/card_db.dart';
import '../l10n/l10n.dart';

/// Estimativa do bracket de Commander a partir das cartas do deck.
///
/// Olha para a lista oficial de Game Changers (marcada pela Scryfall), pelo
/// texto das cartas para turnos extra, destruição de terrenos em massa e
/// tutores, e para os combos de duas cartas mais conhecidos ([combos]). Os
/// outros combos não se detetam: por isso é um mínimo, para começar a conversa
/// da "regra zero".
class BracketEstimate {
  const BracketEstimate(this.gameChangers,
      {this.extraTurns = const [], this.landDenial = const [], this.tutors = const [], this.combos = const []});

  /// Nomes dos Game Changers no deck (comandante incluído).
  final List<String> gameChangers;

  /// Cartas que dão turnos extra (nos brackets 1–3 não se encadeiam).
  final List<String> extraTurns;

  /// Destruição (ou bloqueio) de terrenos em massa: só nos brackets 4–5.
  final List<String> landDenial;

  /// Cartas que procuram outra no grimório (sem contar as que procuram terrenos).
  final List<String> tutors;

  /// Combos de duas cartas conhecidos no deck, como "A + B".
  final List<String> combos;

  int get count => gameChangers.length;

  /// Vários turnos extra: arrisca encadear, o que os brackets 1–3 não querem.
  bool get chainsExtraTurns => extraTurns.length >= 2;

  /// Bracket mínimo: sem Game Changers cabe no 1–2; até 3 no 3; mais de 3,
  /// ou destruição de terrenos em massa, no 4 ou 5. Um combo de duas cartas
  /// tira-o do 1–2 (no 3 só se aceitam os que chegam tarde).
  int get minimum {
    if (landDenial.isNotEmpty || count > 3) return 4;
    return count == 0 && combos.isEmpty ? 2 : 3;
  }

  String get label => switch (minimum) {
        2 => tr('1–2 (Exhibition / Core)'),
        3 => tr('3 (Upgraded)'),
        _ => tr('4+ (Optimized / cEDH)'),
      };

  /// Rótulo curto, para o lobby.
  String get short => switch (minimum) {
        2 => tr('bracket 1–2'),
        3 => tr('bracket 3'),
        _ => tr('bracket 4+'),
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

  /// Combos de duas cartas que ganham (ou dão mana ou dano infinitos) e que
  /// toda a gente conhece. Pelos nomes em inglês, como na Scryfall.
  static const knownCombos = [
    ("Thassa's Oracle", 'Demonic Consultation'),
    ("Thassa's Oracle", 'Tainted Pact'),
    ('Laboratory Maniac', 'Demonic Consultation'),
    ('Isochron Scepter', 'Dramatic Reversal'),
    ('Kiki-Jiki, Mirror Breaker', 'Zealous Conscripts'),
    ('Kiki-Jiki, Mirror Breaker', 'Pestermite'),
    ('Kiki-Jiki, Mirror Breaker', 'Deceiver Exarch'),
    ('Kiki-Jiki, Mirror Breaker', 'Restoration Angel'),
    ('Kiki-Jiki, Mirror Breaker', 'Felidar Guardian'),
    ('Splinter Twin', 'Pestermite'),
    ('Splinter Twin', 'Deceiver Exarch'),
    ('Saheeli Rai', 'Felidar Guardian'),
    ('Dualcaster Mage', 'Twinflame'),
    ('Dualcaster Mage', 'Heat Shimmer'),
    ('Heliod, Sun-Crowned', 'Walking Ballista'),
    ('Mikaeus, the Unhallowed', 'Triskelion'),
    ('Exquisite Blood', 'Sanguine Bond'),
    ('Exquisite Blood', 'Vito, Thorn of the Dusk Rose'),
    ('Niv-Mizzet, Parun', 'Curiosity'),
    ('Niv-Mizzet, the Firemind', 'Curiosity'),
    ('Basalt Monolith', 'Rings of Brighthearth'),
    ('Basalt Monolith', 'Power Artifact'),
    ('Grim Monolith', 'Power Artifact'),
    ('Basalt Monolith', 'Kinnan, Bonder Prodigy'),
    ('Devoted Druid', 'Vizier of Remedies'),
    ('Peregrine Drake', 'Deadeye Navigator'),
    ("Painter's Servant", 'Grindstone'),
    ('Worldgorger Dragon', 'Animate Dead'),
    ('Bloom Tender', 'Freed from the Real'),
    ('Spike Feeder', 'Archangel of Thune'),
    ('Food Chain', 'Eternal Scourge'),
    ('Food Chain', 'Misthollow Griffin'),
  ];

  static BracketEstimate of(Deck deck, Map<String, Card> cards) {
    final list = [
      for (final e in deck.entries.where((e) => e.board == Board.main || e.board == Board.command))
        if (cards[e.oracleId] case final c?) c,
    ];
    return BracketEstimate(
      [
        for (final c in list)
          if (c.gameChanger) c.name
      ],
      extraTurns: [
        for (final c in list)
          if (isExtraTurn(c)) c.name
      ],
      landDenial: [
        for (final c in list)
          if (isLandDenial(c)) c.name
      ],
      tutors: [
        for (final c in list)
          if (CardRoles.of(c).contains(CardRole.tutor)) c.name
      ],
      combos: () {
        final names = {for (final c in list) ...[c.name, c.frontName]};
        return [
          for (final (a, b) in knownCombos)
            if (names.contains(a) && names.contains(b)) '$a + $b'
        ];
      }(),
    );
  }
}
