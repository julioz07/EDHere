/// Formatos 1 contra 1 (Modern, Limited…) com mais de 2 pessoas na sala:
/// rondas todos-contra-todos, cada encontro à melhor de 3. O Commander é que
/// junta todos na mesma mesa.
library;

/// Quem joga com quem em cada ronda. Com número ímpar, quem não aparece numa
/// ronda tem folga (conta como vitória).
class MatchPlan {
  MatchPlan(this.rounds, {this.bestOf = 3});

  final List<List<(int, int)>> rounds;
  final int bestOf;

  int get winsNeeded => bestOf ~/ 2 + 1;

  /// Método do círculo: cada um joga com todos uma vez.
  factory MatchPlan.roundRobin(List<int> seats, {int bestOf = 3}) {
    final list = [...seats];
    if (list.length.isOdd) list.add(-1); // folga
    final n = list.length;
    final rounds = <List<(int, int)>>[];
    for (var r = 0; r < n - 1; r++) {
      final pairs = <(int, int)>[];
      for (var i = 0; i < n ~/ 2; i++) {
        final a = list[i], b = list[n - 1 - i];
        if (a >= 0 && b >= 0) pairs.add((a, b));
      }
      rounds.add(pairs);
      // o primeiro fica; os outros rodam
      list.insert(1, list.removeLast());
    }
    return MatchPlan(rounds, bestOf: bestOf);
  }

  Map<String, dynamic> toJson() => {
        'bestOf': bestOf,
        'rounds': [
          for (final r in rounds)
            [
              for (final (a, b) in r) [a, b]
            ]
        ],
      };

  factory MatchPlan.fromJson(Map<String, dynamic> j) => MatchPlan(
        [
          for (final r in (j['rounds'] as List))
            [
              for (final p in (r as List).cast<List>()) ((p[0] as num).toInt(), (p[1] as num).toInt()),
            ]
        ],
        bestOf: (j['bestOf'] as num?)?.toInt() ?? 3,
      );
}

/// Um encontro: os jogos entre [a] e [b] numa ronda.
class MatchResult {
  MatchResult(this.a, this.b, this.winsNeeded, this.maxGames);
  final int a, b, winsNeeded, maxGames;

  /// Vencedor de cada jogo acabado (null = empate).
  final List<int?> games = [];

  int wins(int seat) => games.where((w) => w == seat).length;
  bool has(int seat) => seat == a || seat == b;
  int other(int seat) => seat == a ? b : a;

  bool get done => wins(a) >= winsNeeded || wins(b) >= winsNeeded || games.length >= maxGames;

  /// Quem ganhou o encontro (null = empate ou ainda a decorrer).
  int? get winner {
    if (!done) return null;
    final wa = wins(a), wb = wins(b);
    return wa == wb ? null : (wa > wb ? a : b);
  }
}

/// Uma linha da classificação.
class Standing {
  Standing(this.seat);
  final int seat;
  int points = 0, matchWins = 0, matchLosses = 0, matchDraws = 0, byes = 0, gameWins = 0, gameLosses = 0;
}

/// O estado do torneio, igual em todos os dispositivos (vem dos eventos).
class Tournament {
  Tournament(this.plan)
      : results = [
          for (final r in plan.rounds) [for (final (a, b) in r) MatchResult(a, b, plan.winsNeeded, plan.bestOf)]
        ];

  final MatchPlan plan;
  final List<List<MatchResult>> results;
  int round = 0;

  Set<int> get seats => {
        for (final r in plan.rounds)
          for (final (a, b) in r) ...[a, b]
      };

  int get roundCount => plan.rounds.length;

  MatchResult? matchOf(int round, int seat) =>
      round < results.length ? results[round].where((m) => m.has(seat)).firstOrNull : null;

  /// Quem não joga nesta ronda (número ímpar de jogadores).
  List<int> byes(int round) => [
        for (final s in seats)
          if (matchOf(round, s) == null) s
      ]..sort();

  bool roundDone(int round) => results[round].every((m) => m.done);
  bool get finished => round >= roundCount - 1 && roundDone(roundCount - 1);

  /// Pontos de encontro: vitória e folga 3, empate 1. Desempata pelos jogos.
  List<Standing> standings() {
    final t = {for (final s in seats) s: Standing(s)};
    for (var r = 0; r <= round && r < roundCount; r++) {
      for (final m in results[r]) {
        for (final s in [m.a, m.b]) {
          t[s]!
            ..gameWins += m.wins(s)
            ..gameLosses += m.wins(m.other(s));
        }
        if (!m.done) continue;
        final w = m.winner;
        if (w == null) {
          t[m.a]!
            ..matchDraws += 1
            ..points += 1;
          t[m.b]!
            ..matchDraws += 1
            ..points += 1;
        } else {
          t[w]!
            ..matchWins += 1
            ..points += 3;
          t[m.other(w)]!.matchLosses += 1;
        }
      }
      for (final s in byes(r)) {
        t[s]!
          ..byes += 1
          ..points += 3;
      }
    }
    return t.values.toList()
      ..sort((x, y) {
        final p = y.points.compareTo(x.points);
        if (p != 0) return p;
        return (y.gameWins - y.gameLosses).compareTo(x.gameWins - x.gameLosses);
      });
  }
}
