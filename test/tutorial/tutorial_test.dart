import 'dart:ffi';
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:edhoff/tutorial/chapters_basics.dart';
import 'package:edhoff/tutorial/chapters_commander.dart';
import 'package:edhoff/tutorial/tutorial_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesa_core/mesa_core.dart';
import 'package:sqlite3/open.dart';

/// Ações que um jogador pode tentar na mesa (todas as que o tutorial usa).
/// O guarda do tutorial bloqueia as que o passo não pede.
List<Intent> _candidates(TutorialRunner r) {
  final c = r.ctrl;
  final t = c.table;
  final s = c.state;
  final mine = s.cards.values.where((x) => x.owner == 0).toList();
  return [
    for (final pc in c.zones(0).hand) t.moveHidden(0, Zone.hand, pc.pid, Zone.battlefield),
    for (final pc in c.zones(0).hand) t.moveHidden(0, Zone.hand, pc.pid, Zone.graveyard),
    for (final x in mine.where((x) => x.zone == Zone.battlefield && !x.tapped))
      Intent(Ev.tap, {
        'ids': [x.id],
        'value': true
      }),
    for (final x in mine.where((x) => x.isCommander && x.zone == Zone.command)) t.movePublic(x.id, Zone.battlefield),
    for (final x in mine.where((x) => x.isCommander && (x.zone == Zone.exile || x.zone == Zone.graveyard)))
      t.movePublic(x.id, Zone.command),
    for (final x in mine.where((x) => x.zone == Zone.battlefield && !x.isCommander)) t.movePublic(x.id, Zone.graveyard),
    for (final x in mine.where((x) => x.zone == Zone.battlefield))
      Intent(Ev.counter, {'id': x.id, 'kind': CounterKind.plus, 'delta': 1}),
    // Lealdade: usar o +1 (habilidade) ou tirar com o −.
    for (final x in mine.where((x) => x.zone == Zone.battlefield && x.counters.containsKey(CounterKind.loyalty)))
      Intent(Ev.counter, {'id': x.id, 'kind': CounterKind.loyalty, 'delta': 1, 'ability': '+1'}),
    for (final x in mine.where((x) => x.zone == Zone.battlefield && x.counters.containsKey(CounterKind.loyalty)))
      Intent(Ev.counter, {'id': x.id, 'kind': CounterKind.loyalty, 'delta': -1}),
    // Desvirar e anexar (equipamentos).
    for (final x in mine.where((x) => x.zone == Zone.battlefield && x.tapped))
      Intent(Ev.tap, {
        'ids': [x.id],
        'value': false
      }),
    for (final x in mine.where((x) => x.zone == Zone.battlefield && x.attachedTo == null))
      for (final y in mine.where((y) => y.zone == Zone.battlefield && y.id != x.id))
        Intent(Ev.attach, {'id': x.id, 'to': y.id}),
    t.draw(0, 1),
    t.mulligan(0),
    // Bloqueios: setas das minhas criaturas para as dos outros.
    for (final x in mine.where((x) => x.zone == Zone.battlefield))
      for (final y in s.cards.values.where((y) => y.owner != 0 && y.zone == Zone.battlefield))
        Intent(Ev.arrow, {'from': x.id, 'to': y.id}),
    for (final seat in [1, 2]) Intent(Ev.life, {'seat': seat, 'delta': -1}),
    for (final seat in [1, 2])
      for (final x in mine.where((x) => x.isCommander))
        Intent(Ev.commanderDamage, {'seat': seat, 'cmdId': x.id, 'delta': 1}),
    const Intent(Ev.passTurn, {}),
  ];
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late CardRepository repo;

  setUpAll(() async {
    if (Platform.isWindows) {
      open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(r'C:\Python313\DLLs\sqlite3.dll'));
    }
    TutorialRunner.timeScale = 0;
    final dir = Directory.systemTemp.createTempSync('tutorial');
    final imp = CardImporter('${dir.path}/c.sqlite')..open();
    await imp.importLines(Stream.fromIterable(File('test/fixtures/tutorial_cards.jsonl').readAsLinesSync()));
    imp.finish({});
    repo = CardRepository.open('${dir.path}/c.sqlite')!;
  });

  final all = [...basicsChapters, ...commanderChapters];

  test('os capítulos têm ids únicos e as duas versões estão completas', () {
    expect(all.map((c) => c.id).toSet().length, all.length);
    expect(commanderChapters.length, greaterThanOrEqualTo(5));
    expect(basicsChapters.length, greaterThanOrEqualTo(5));
    for (final c in all) {
      expect(c.pages.isNotEmpty || c.hasGame, isTrue, reason: c.id);
    }
  });

  for (final chapter in all.where((c) => c.hasGame)) {
    test('o capítulo "${chapter.title}" joga-se até ao fim', () async {
      final r = TutorialRunner(chapter: chapter, repo: repo, playerName: 'Eu');
      expect(r.build(), isTrue, reason: 'faltam cartas: ${r.missing}');
      await r.start();
      await _settle();
      var guard = 0;
      while (!r.finished) {
        expect(++guard, lessThan(400), reason: 'preso no passo ${r.step + 1}: ${r.current?.text}');
        final s = r.current!;
        if (s.done == null) {
          // Num passo de leitura, a mesa não deixa fazer nada.
          final before = r.ctrl.state.seq;
          r.ctrl.sendAs(0, const Intent(Ev.passTurn, {}));
          expect(r.ctrl.state.seq, before, reason: 'passo de leitura deixou jogar');
          r.next();
          await _settle();
          continue;
        }
        final step = r.step;
        var moved = false;
        for (final i in _candidates(r)) {
          final before = r.ctrl.state.seq;
          r.ctrl.sendAs(0, i);
          if (r.ctrl.state.seq != before) {
            moved = true;
            // Uma seta não pedida fica na mesa e não acaba o passo: tenta outra.
            if (i.type == Ev.arrow && !(s.done!(r))) {
              r.ctrl.sendAs(0, const Intent(Ev.arrow, {}));
              moved = false;
              continue;
            }
            break;
          }
        }
        expect(moved, isTrue, reason: 'nenhuma ação aceite no passo ${step + 1}: ${s.text}');
        await _settle();
      }
      r.dispose();
    });
  }

  test('fora do passo, a mesa explica em vez de jogar', () async {
    final chapter = commanderChapters.firstWhere((c) => c.id == 'cmd-cast');
    final r = TutorialRunner(chapter: chapter, repo: repo, playerName: 'Eu');
    expect(r.build(), isTrue);
    await r.start();
    await _settle();
    // O primeiro passo pede um Forest: lançar a Marwyn agora é bloqueado.
    final marwynCard = r.state.cards.values.firstWhere((c) => c.isCommander && c.owner == 0);
    final before = r.state.seq;
    r.ctrl.sendAs(0, r.ctrl.table.movePublic(marwynCard.id, Zone.battlefield));
    expect(r.state.seq, before);
    expect(r.hint, isNotNull);
    r.dispose();
  });

  test('o capítulo de responder bloqueia e resolve a cadeia', () async {
    final chapter = commanderChapters.firstWhere((c) => c.id == 'cmd-respond');
    final r = TutorialRunner(chapter: chapter, repo: repo, playerName: 'Eu');
    expect(r.build(), isTrue);
    await r.start();
    await _settle();
    // Uma seta para outra criatura que não ataca não conta como bloqueio.
    expect(r.step, 0);
    final warrior = r.cardsNamed('Elvish Warrior', zone: Zone.battlefield, seat: 0).single;
    final isamaru = r.cardsNamed('Isamaru, Hound of Konda', zone: Zone.battlefield).single;
    r.ctrl.sendAs(0, Intent(Ev.arrow, {'from': warrior.id, 'to': isamaru.id}));
    await _settle();
    expect(r.step, greaterThan(0));
    r.dispose();
  });

  test('o mulligan de treino devolve a mão do guião', () async {
    final chapter = commanderChapters.firstWhere((c) => c.id == 'cmd-start');
    final r = TutorialRunner(chapter: chapter, repo: repo, playerName: 'Eu');
    expect(r.build(), isTrue);
    await r.start();
    await _settle();
    r.next();
    await _settle();
    r.next();
    await _settle();
    r.ctrl.mulligan();
    await _settle();
    expect(r.ctrl.zones(0).hand.map((c) => repo.get(c.oracleId)!.name),
        unorderedEquals(['Forest', 'Forest', 'Forest', 'Elvish Mystic', 'Grizzly Bears', 'Elvish Visionary',
            'Leatherback Baloth']));
    expect(r.state.players[0]!.handCount, 7);
    r.dispose();
  });

  test('os grimórios do tutorial não são baralhados', () async {
    final chapter = basicsChapters.firstWhere((c) => c.id == 'mtg-mana');
    final r = TutorialRunner(chapter: chapter, repo: repo, playerName: 'Eu');
    expect(r.build(), isTrue);
    final hand = r.ctrl.zones(0).hand.map((c) => repo.get(c.oracleId)!.name).toList();
    expect(hand, chapter.setup!.seats[0].hand);
    expect(repo.get(r.ctrl.zones(0).library.first.oracleId)!.name, chapter.setup!.seats[0].library.first);
    r.dispose();
  });
}
