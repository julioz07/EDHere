import 'package:edhoff/game/match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('4 jogadores: 3 rondas, cada um joga com todos uma vez', () {
    final plan = MatchPlan.roundRobin([0, 1, 2, 3]);
    expect(plan.rounds.length, 3);
    final pairs = <String>{};
    for (final r in plan.rounds) {
      expect(r.length, 2);
      final seats = [for (final (a, b) in r) ...[a, b]]..sort();
      expect(seats, [0, 1, 2, 3], reason: 'todos jogam em cada ronda');
      for (final (a, b) in r) {
        pairs.add(a < b ? '$a-$b' : '$b-$a');
      }
    }
    expect(pairs.length, 6, reason: 'os 6 encontros possíveis, sem repetir');
  });

  test('3 jogadores: em cada ronda um tem folga, que conta como vitória', () {
    final t = Tournament(MatchPlan.roundRobin([0, 1, 2]));
    expect(t.roundCount, 3);
    for (var r = 0; r < 3; r++) {
      expect(t.byes(r).length, 1);
    }
    expect({for (var r = 0; r < 3; r++) ...t.byes(r)}, {0, 1, 2}, reason: 'a folga roda');
    final bye = t.byes(0).single;
    expect(t.standings().firstWhere((s) => s.seat == bye).points, 3);
  });

  test('melhor de 3: acaba aos 2 jogos ganhos e a classificação conta pontos e jogos', () {
    final t = Tournament(MatchPlan([
      [(0, 1), (2, 3)]
    ]));
    final m = t.matchOf(0, 0)!;
    m.games.add(0);
    expect(m.done, isFalse);
    m.games.add(1);
    m.games.add(0);
    expect(m.done, isTrue);
    expect(m.winner, 0);
    final o = t.matchOf(0, 2)!;
    o.games.addAll([3, 3]);
    expect(o.done, isTrue, reason: '2-0 acaba sem terceiro jogo');
    expect(t.finished, isTrue);
    final s = t.standings();
    expect(s.first.seat, 3, reason: '3 pontos e +2 em jogos ganha a 0 com +1');
    expect(s[1].seat, 0);
    expect(s.map((x) => x.points), [3, 3, 0, 0]);
  });

  test('o plano passa pela rede (JSON) sem mudar', () {
    final plan = MatchPlan.roundRobin([0, 2, 5]);
    final back = MatchPlan.fromJson(plan.toJson());
    expect(back.rounds, plan.rounds);
    expect(back.bestOf, 3);
  });
}
