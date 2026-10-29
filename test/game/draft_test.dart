import 'package:card_db/card_db.dart' as db;
import 'package:edhoff/game/draft.dart';
import 'package:edhoff/ui/limited/limited_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Packs de teste: [rondas][lugares], cada um com [size] cartas numeradas.
List<List<List<DraftCard>>> packs(int rounds, int seats, int size) {
  var id = 1;
  return [
    for (var r = 0; r < rounds; r++)
      [
        for (var s = 0; s < seats; s++)
          [
            for (var i = 0; i < size; i++)
              DraftCard(id++, db.BoosterPrint('s$id', 'o$id', i == 0 ? 'R' : 'C', '$i')),
          ],
      ],
  ];
}

void main() {
  test('o pack passa para a esquerda na 1.ª ronda e para a direita na 2.ª', () {
    final e = DraftEngine(packs: packs(2, 3, 3))..start();
    final first = e.current(0)!;
    // O lugar 0 escolhe; o resto do pack vai para o lugar 1.
    e.pick(0, [first.first.id]);
    expect(e.queues[1].length, 2);
    expect(e.queues[1].last.length, 2);
    // Termina a ronda 1 (todos escolhem até os packs acabarem).
    while (e.round == 0) {
      for (var p = 0; p < 3; p++) {
        final pack = e.current(p);
        if (pack != null) e.pick(p, [pack.first.id]);
      }
    }
    expect(e.round, 1);
    expect(e.direction, -1);
    final r2 = e.current(1)!;
    e.pick(1, [r2.first.id]);
    expect(e.queues[0].length, 2, reason: 'na 2.ª ronda passa para a direita (lugar anterior)');
  });

  test('pick-two: tira 2 de cada vez e 1 quando só resta uma', () {
    final e = DraftEngine(packs: packs(1, 2, 5), picks: 2)..start();
    expect(e.picksNow(0), 2);
    expect(e.pick(0, [e.current(0)!.first.id]), isEmpty, reason: 'só uma carta não chega');
    var turns = 0;
    while (!e.finished && turns < 50) {
      turns++;
      for (var p = 0; p < 2; p++) {
        final pack = e.current(p);
        if (pack == null) continue;
        e.pick(p, [for (final c in pack.take(e.picksNow(p))) c.id]);
      }
    }
    expect(e.finished, isTrue);
    expect(e.pools[0].length + e.pools[1].length, 10);
  });

  test('um draft inteiro reparte todas as cartas, sem repetidas', () {
    final e = DraftEngine(packs: packs(3, 4, 14))..start();
    while (!e.finished) {
      for (var p = 0; p < 4; p++) {
        final pack = e.current(p);
        if (pack != null) e.pick(p, botPick(pack, e.pools[p], e.picksNow(p), (_) => 0));
      }
    }
    final all = [for (final pool in e.pools) ...pool];
    expect(all.length, 3 * 4 * 14);
    expect(all.map((c) => c.id).toSet().length, all.length);
    for (final pool in e.pools) {
      expect(pool.length, 42);
    }
  });

  test('o bot prefere raridade e depois as suas cores', () {
    const red = 1 << 3, blue = 1 << 1;
    final colors = {'r1': red, 'r2': red, 'r3': red, 'r4': red, 'bR': blue, 'rC': red};
    DraftCard c(int id, String o, String rarity) => DraftCard(id, db.BoosterPrint('x$id', o, rarity, ''));
    final pool = [c(1, 'r1', 'C'), c(2, 'r2', 'C'), c(3, 'r3', 'C'), c(4, 'r4', 'C')];
    // Uma rara azul contra uma comum vermelha: com 4 vermelhas na pool, vai a vermelha.
    final pick = botPick([c(10, 'bR', 'R'), c(11, 'rC', 'C')], pool, 1, (o) => colors[o] ?? 0);
    expect(pick, [11]);
    // Sem pool ainda, vai a rara.
    expect(botPick([c(10, 'bR', 'R'), c(11, 'rC', 'C')], const [], 1, (o) => colors[o] ?? 0), [10]);
    // Duas comuns nas suas cores: vai a que vale mais (a remoção).
    final value = {'rC': 0.0, 'bolt': 2.5};
    colors['bolt'] = red;
    expect(
        botPick([c(11, 'rC', 'C'), c(12, 'bolt', 'C')], pool, 1, (o) => colors[o] ?? 0,
            valueOf: (o) => value[o] ?? 0),
        [12]);
  });

  test('a configuração passa por JSON', () {
    const cfg = DraftConfig(
      title: 'Tarkir',
      setCode: 'TDM',
      picks: 2,
      timer: 45,
      seats: [(seat: 0, name: 'Ana'), (seat: null, name: 'Bot 1')],
    );
    final back = DraftConfig.fromJson(cfg.toJson());
    expect(back.setCode, 'TDM');
    expect(back.picks, 2);
    expect(back.seats[1].seat, isNull);
    expect(back.commander, isFalse);
    expect(DraftConfig.fromJson(const DraftConfig(title: 'CMR', commander: true, seats: []).toJson()).commander,
        isTrue);
  });

  test('commander draft: pares de comandantes', () {
    db.Card legend(String n, int c, [String text = '']) => db.Card(
        oracleId: n, name: n, typeLine: 'Legendary Creature — Elf', oracleText: text, colorMask: c);
    const bg = db.Card(oracleId: 'bg', name: 'Bg', typeLine: 'Legendary Enchantment — Background');
    final g = legend('G', db.ManaColors.g), r = legend('R', db.ManaColors.r);
    final gr = legend('GR', db.ManaColors.g | db.ManaColors.r);
    expect(commanderPairOk([g]), isTrue);
    expect(commanderPairOk([bg]), isFalse);
    expect(commanderPairOk([g, r]), isTrue);
    expect(commanderPairOk([gr, r]), isFalse);
    expect(commanderPairOk([legend('X', db.ManaColors.g | db.ManaColors.u, 'Choose a Background'), bg]), isTrue);
    expect(commanderPairOk([g, r, legend('W', db.ManaColors.w)]), isFalse);
  });
}
