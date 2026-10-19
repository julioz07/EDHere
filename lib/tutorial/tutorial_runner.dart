import 'dart:async';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/foundation.dart';
import 'package:mesa_core/mesa_core.dart';

import '../game/game_controller.dart';
import 'tutorial.dart';

/// Corre a parte jogada de um capítulo: monta a mesa, deixa o jogador fazer
/// só o que o passo pede e faz jogar os adversários.
class TutorialRunner extends ChangeNotifier implements TableView {
  TutorialRunner({required this.chapter, required this.repo, required this.playerName, this.resolvePrint});

  final Chapter chapter;
  final db.CardRepository repo;
  final String playerName;
  final db.Card Function(db.Card base, String? printId)? resolvePrint;

  late final GameController ctrl;

  /// Multiplica as pausas (os testes usam 0 para correr sem esperas).
  static double timeScale = 1;
  static Duration _ms(int ms) => Duration(milliseconds: (ms * timeScale).round());

  /// Passo atual (-1 antes de começar).
  int step = -1;

  /// O que dizer depois de uma ação que não era a pedida.
  String? hint;

  /// O que os adversários fizeram nesta vez, por ordem (enquanto [busy]).
  final List<String> narrated = [];
  String? get narration => narrated.lastOrNull;
  bool busy = false;
  bool finished = false;

  /// Cartas que não existem na base (base desatualizada).
  final Set<String> missing = {};

  bool _scripting = false;
  bool _disposed = false;
  final Map<String, String> _oracle = {};

  TStep? get current => step >= 0 && step < chapter.steps.length ? chapter.steps[step] : null;

  // -------------------------------------------------------------------
  // Montar a mesa
  // -------------------------------------------------------------------

  String? oracleOf(String name) {
    if (_oracle.containsKey(name)) return _oracle[name];
    final c = repo.findByName(name);
    if (c == null) {
      missing.add(name);
      return null;
    }
    return _oracle[name] = c.oracleId;
  }

  /// Monta a mesa. Devolve false se faltarem cartas na base.
  bool build() {
    final setup = chapter.setup!;
    for (final s in setup.seats) {
      for (final n in [if (s.commander != null) s.commander!, ...s.battlefield, ...s.hand, ...s.library]) {
        oracleOf(n);
      }
    }
    if (missing.isNotEmpty) return false;
    final seats = {for (var i = 0; i < setup.seats.length; i++) i};
    final table = Table(format: 'commander', localSeats: seats);
    ctrl = GameController(table: table, repo: repo, mySeats: {0}, viewSeat: 0)
      ..scripted = true
      ..resolvePrint = resolvePrint
      ..guard = _guard;
    ctrl.openingDone.addAll(seats);
    _script(() {
      for (var i = 0; i < setup.seats.length; i++) {
        final s = setup.seats[i];
        ctrl.sendAs(
            i, Intent(Ev.joinTable, {'seat': i, 'name': i == 0 ? playerName : s.name, 'life': s.life}));
      }
      for (var i = 0; i < setup.seats.length; i++) {
        final s = setup.seats[i];
        ctrl.sendAs(
          i,
          table.loadDeck(
            i,
            [
              for (final n in [...s.battlefield, ...s.hand, ...s.library]) _oracle[n]!
            ],
            [if (s.commander != null) _oracle[s.commander]!],
            keepOrder: true,
          ),
        );
      }
      ctrl.sendAs(setup.active, Intent(Ev.startGame, {'first': setup.active}));
      for (var i = 0; i < setup.seats.length; i++) {
        final s = setup.seats[i];
        for (final n in s.battlefield) {
          _fromLibrary(i, n, Zone.battlefield);
        }
        if (s.hand.isNotEmpty) ctrl.sendAs(i, table.draw(i, s.hand.length));
      }
      // O guião conta os turnos de cada um ("o teu 3.º turno"): a mesa conta
      // os de todos, por isso converte-se para que a ronda dê certo.
      table.state.turn = (setup.turn - 1) * setup.seats.length + 1 + setup.active;
    });
    return true;
  }

  /// Prepara e mostra o primeiro passo.
  Future<void> start() async {
    await _runActs(chapter.setup!.prepare, quiet: true);
    ctrl.addListener(_changed);
    await _enter(0);
  }

  void _script(VoidCallback fn) {
    _scripting = true;
    try {
      fn();
    } finally {
      _scripting = false;
    }
  }

  // -------------------------------------------------------------------
  // Passos
  // -------------------------------------------------------------------

  Future<void> _enter(int i) async {
    if (_disposed) return;
    if (i >= chapter.steps.length) {
      finished = true;
      ctrl.coachFocus = const {};
      if (ctrl.viewSeat != 0) ctrl.setView(0);
      notifyListeners();
      return;
    }
    step = i;
    hint = null;
    ctrl.coachFocus = const {};
    final s = chapter.steps[i];
    if (s.run.isNotEmpty) await _runActs(s.run);
    if (_disposed) return;
    ctrl.coachFocus = {for (final n in s.focus) _oracle[n] ?? oracleOf(n)}.whereType<String>().toSet();
    ctrl.setView(s.view ?? 0);
    notifyListeners();
    // Um passo que já está feito (por exemplo, depois de os adversários jogarem).
    if (s.done != null && s.done!(this)) unawaited(_next());
  }

  /// Passo só de leitura: o jogador toca em "Continuar".
  void next() {
    if (busy || current == null || current!.done != null) return;
    _enter(step + 1);
  }

  bool _advancing = false;
  Future<void> _next() async {
    if (_advancing) return;
    _advancing = true;
    await Future<void>.delayed(_ms(700));
    _advancing = false;
    await _enter(step + 1);
  }

  void _changed() {
    if (_scripting || busy || _advancing) return;
    final s = current;
    if (s?.done != null && s!.done!(this)) _next();
  }

  bool _guard(int seat, Intent i) {
    if (_scripting) return true;
    const free = {Ev.highlight, Ev.position, Ev.arrow, Ev.emote};
    if (free.contains(i.type)) return true;
    final s = current;
    if (busy || s == null) return false;
    final a = _describe(seat, i);
    if (s.allow != null && s.allow!(a)) {
      if (hint != null) {
        hint = null;
        notifyListeners();
      }
      return true;
    }
    hint = s.hint ??
        (s.done == null
            ? 'Lê o texto e toca em "Continuar".'
            : 'Ainda não: faz primeiro o que o passo pede.');
    notifyListeners();
    return false;
  }

  /// Os nomes das cartas e as zonas de uma ação.
  TAction _describe(int seat, Intent i) {
    final p = i.payload;
    final names = <String>[];
    Zone? from, to;
    String? nameOf(String? oracle) => oracle == null ? null : repo.get(oracle)?.name;
    switch (i.type) {
      case Ev.move:
        to = Zone.values.firstWhere((z) => z.id == p['to'], orElse: () => Zone.battlefield);
        if (p['pid'] != null) {
          from = Zone.values.firstWhere((z) => z.id == p['from'], orElse: () => Zone.hand);
          final zones = ctrl.zones(seat);
          final list = from == Zone.hand ? zones.hand : zones.library;
          final pc = list.where((c) => c.pid == p['pid']).firstOrNull;
          if (nameOf(pc?.oracleId) case final n?) names.add(n);
        } else {
          final c = ctrl.state.cards[p['id']];
          from = c?.zone;
          if (nameOf(c?.oracleId) case final n?) names.add(n);
        }
      case Ev.tap:
        for (final id in (p['ids'] as List).cast<num>()) {
          if (nameOf(ctrl.state.cards[id.toInt()]?.oracleId) case final n?) names.add(n);
        }
      case Ev.attach:
        // A carta anexada e depois aquela a que fica anexada.
        for (final k in ['id', 'to']) {
          if (p[k] is num) {
            if (nameOf(ctrl.state.cards[(p[k] as num).toInt()]?.oracleId) case final n?) names.add(n);
          }
        }
      default:
        if (p['id'] is num) {
          if (nameOf(ctrl.state.cards[(p['id'] as num).toInt()]?.oracleId) case final n?) names.add(n);
        }
    }
    return TAction(seat, i, names: names, from: from, to: to);
  }

  // -------------------------------------------------------------------
  // Adversários
  // -------------------------------------------------------------------

  Future<void> _runActs(List<Act> acts, {bool quiet = false}) async {
    busy = true;
    narrated.clear();
    notifyListeners();
    for (final act in acts) {
      if (_disposed) return;
      if (!quiet && act.say != null) {
        narrated.add(act.say!);
        notifyListeners();
        // Tempo para ler o que vai acontecer antes de acontecer.
        await Future<void>.delayed(_ms(1200));
      }
      // A mesa mostra o campo de quem está a jogar, para se ver o que fez.
      final who = _seatOf(act);
      if (!quiet && who != null && who != ctrl.viewSeat) ctrl.setView(who);
      _script(() => _perform(act));
      // Cada jogada fica uns segundos na mesa, para se ver o que mudou.
      if (!quiet) await Future<void>.delayed(_ms(act is Pause ? act.ms * 2 : 2300));
    }
    if (!quiet && ctrl.viewSeat != 0) {
      // Uma pausa no campo do adversário, e volta ao teu.
      await Future<void>.delayed(_ms(1500));
      if (!_disposed) ctrl.setView(0);
    }
    narrated.clear();
    busy = false;
    notifyListeners();
  }

  /// O lugar que faz a ação (para mostrar o campo dele).
  int? _seatOf(Act act) => switch (act) {
        Play(:final seat) || Cast(:final seat) || Tap(:final seat) || Token(:final seat) => seat,
        CastCommander(:final seat) || UntapAll(:final seat) || Draw(:final seat) => seat,
        CommanderHit(:final to) => to,
        Life(:final seat) => seat,
        MoveCard(:final seat) => seat,
        Target(:final targetSeat) => targetSeat ?? 0,
        Attack(:final seat) => seat,
        _ => null,
      };

  void _perform(Act act) {
    final t = ctrl.table;
    switch (act) {
      case Play(:final seat, :final name):
        if (!_fromHand(seat, name, Zone.battlefield)) _fromLibrary(seat, name, Zone.battlefield);
      case Cast(:final seat, :final name):
        if (!_fromHand(seat, name, Zone.graveyard)) _fromLibrary(seat, name, Zone.graveyard);
      case CastCommander(:final seat):
        final c = ctrl.state.cards.values
            .where((c) => c.isCommander && c.owner == seat && c.zone == Zone.command)
            .firstOrNull;
        if (c != null) {
          final (x, y) = ctrl.nextSpot(seat: seat);
          ctrl.sendAs(seat, t.movePublic(c.id, Zone.battlefield, x: x, y: y));
        }
      case Tap(:final seat, :final names, :final value):
        final ids = [
          for (final n in names)
            ...cardsNamed(n, zone: Zone.battlefield, seat: seat)
                .where((c) => c.tapped != value)
                .take(1)
                .map((c) => c.id),
        ];
        if (ids.isNotEmpty) ctrl.sendAs(seat, Intent(Ev.tap, {'ids': ids, 'value': value}));
      case UntapAll(:final seat):
        ctrl.sendAs(seat, Intent(Ev.untapAll, {'seat': seat}));
      case Life(:final seat, :final delta):
        ctrl.sendAs(seat, Intent(Ev.life, {'seat': seat, 'delta': delta}));
      case CommanderHit(:final from, :final to, :final amount):
        final cmd = ctrl.state.cards.values.where((c) => c.isCommander && c.owner == from).firstOrNull;
        if (cmd != null) {
          ctrl.sendAs(from, Intent(Ev.commanderDamage, {'seat': to, 'cmdId': cmd.id, 'delta': amount}));
        }
      case MoveCard(:final seat, :final name, :final to):
        final c = cardsNamed(name, seat: seat).where((c) => c.zone != to).firstOrNull;
        if (c != null) ctrl.sendAs(seat, t.movePublic(c.id, to));
      case Counter(:final seat, :final name, :final kind, :final delta):
        final c = cardsNamed(name, zone: Zone.battlefield, seat: seat).firstOrNull;
        if (c != null) ctrl.sendAs(seat, Intent(Ev.counter, {'id': c.id, 'kind': kind, 'delta': delta}));
      case Token(:final seat, :final tokenName, :final pt, :final qty):
        final (x, y) = ctrl.nextSpot(seat: seat);
        ctrl.sendAs(seat, t.createToken(seat, name: tokenName, pt: pt, qty: qty, x: x, y: y));
      case Target(:final seat, :final name, :final targetSeat):
        final c = cardsNamed(name, zone: Zone.battlefield, seat: targetSeat).firstOrNull;
        if (c != null) ctrl.sendAs(seat, Intent(Ev.arrow, {'to': c.id}));
      case Attack(:final seat, :final name, :final target):
        final c = cardsNamed(name, zone: Zone.battlefield, seat: seat).where((c) => !c.tapped).firstOrNull;
        if (c != null) {
          ctrl.sendAs(
              seat,
              Intent(Ev.tap, {
                'ids': [c.id],
                'value': true
              }));
          ctrl.sendAs(seat, Intent(Ev.arrow, {'from': c.id, 'seat': target}));
        }
      case AttackCard(:final seat, :final name, :final target, :final targetSeat):
        final c = cardsNamed(name, zone: Zone.battlefield, seat: seat).where((c) => !c.tapped).firstOrNull;
        final t = cardsNamed(target, zone: Zone.battlefield, seat: targetSeat).firstOrNull;
        if (c != null && t != null) {
          ctrl.sendAs(
              seat,
              Intent(Ev.tap, {
                'ids': [c.id],
                'value': true
              }));
          ctrl.sendAs(seat, Intent(Ev.arrow, {'from': c.id, 'to': t.id}));
        }
      case ClearTargets(:final seat):
        ctrl.sendAs(seat, const Intent(Ev.arrow, {}));
      case SetHand(:final seat, :final names):
        final z = ctrl.zones(seat);
        final all = [...z.hand, ...z.library];
        final hand = <PrivateCard>[];
        for (final n in names) {
          final o = _oracle[n] ?? oracleOf(n);
          final pc = all.where((c) => c.oracleId == o && !hand.contains(c)).firstOrNull;
          if (pc != null) hand.add(pc);
        }
        final rest = all.where((c) => !hand.contains(c)).toList();
        z.hand
          ..clear()
          ..addAll(hand);
        z.library
          ..clear()
          ..addAll(rest);
        ctrl.state.players[seat]
          ?..handCount = hand.length
          ..libraryCount = rest.length;
        ctrl.notifyListeners();
      case Draw(:final seat, :final n):
        ctrl.sendAs(seat, t.draw(seat, n));
      case PassTurn():
        ctrl.sendAs(ctrl.state.activeSeat, const Intent(Ev.passTurn, {}));
      case Concede(:final seat):
        ctrl.sendAs(seat, Intent(Ev.defeated, {'seat': seat, 'value': true}));
        // Quem perde sai do jogo com as suas cartas.
        for (final c
            in ctrl.state.cards.values.where((c) => c.owner == seat && c.zone == Zone.battlefield).toList()) {
          ctrl.sendAs(seat, t.movePublic(c.id, Zone.exile));
        }
      case Pause():
        break;
    }
  }

  bool _fromHand(int seat, String name, Zone to) {
    final o = _oracle[name] ?? oracleOf(name);
    final pc = ctrl.zones(seat).hand.where((c) => c.oracleId == o).firstOrNull;
    if (pc == null) return false;
    final (x, y) = ctrl.nextSpot(isLand: repo.get(o!)?.isLand ?? false, seat: seat);
    ctrl.sendAs(
        seat, ctrl.table.moveHidden(seat, Zone.hand, pc.pid, to, x: x, y: y, cast: to == Zone.graveyard));
    return true;
  }

  void _fromLibrary(int seat, String name, Zone to, {double? x, double? y}) {
    final o = _oracle[name] ?? oracleOf(name);
    final pc = ctrl.zones(seat).library.where((c) => c.oracleId == o).firstOrNull;
    if (pc == null) return;
    final spot = ctrl.nextSpot(isLand: repo.get(o!)?.isLand ?? false, seat: seat);
    ctrl.sendAs(
        seat,
        ctrl.table.moveHidden(seat, Zone.library, pc.pid, to,
            x: x ?? spot.$1, y: y ?? spot.$2, cast: to == Zone.graveyard));
  }

  // -------------------------------------------------------------------
  // TableView
  // -------------------------------------------------------------------

  @override
  GameState get state => ctrl.state;

  @override
  String? nameOf(String? oracleId) => oracleId == null ? null : repo.get(oracleId)?.name;

  @override
  List<CardInstance> cardsNamed(String name, {Zone? zone, int? seat}) {
    final o = _oracle[name] ?? oracleOf(name);
    return [
      for (final c in ctrl.state.cards.values)
        if ((c.oracleId == o || (c.oracleId == null && c.tokenName == name)) &&
            (zone == null || c.zone == zone) &&
            (seat == null || c.owner == seat))
          c,
    ];
  }

  @override
  int handCount(int seat) => ctrl.zones(seat).hand.length;

  @override
  int mulligans(int seat) => ctrl.state.log.where((e) => e.type == Ev.mulligan && e.actor == seat).length;

  @override
  bool inHand(int seat, String name) => ctrl.zones(seat).hand.any((c) => c.oracleId == _oracle[name]);

  @override
  void dispose() {
    _disposed = true;
    ctrl.removeListener(_changed);
    ctrl.dispose();
    super.dispose();
  }
}

/// Condições frequentes dos passos.
abstract final class Done {
  static bool Function(TableView) onField(String name, {int seat = 0}) =>
      (t) => t.cardsNamed(name, zone: Zone.battlefield, seat: seat).isNotEmpty;

  static bool Function(TableView) inZone(String name, Zone zone, {int seat = 0}) =>
      (t) => t.cardsNamed(name, zone: zone, seat: seat).isNotEmpty;

  /// Pelo menos [n] cartas com este nome viradas.
  static bool Function(TableView) tapped(String name, {int n = 1, int seat = 0}) =>
      (t) => t.cardsNamed(name, zone: Zone.battlefield, seat: seat).where((c) => c.tapped).length >= n;

  static bool Function(TableView) life(int seat, int value) => (t) => t.state.players[seat]?.life == value;

  static bool Function(TableView) lifeAtMost(int seat, int value) =>
      (t) => (t.state.players[seat]?.life ?? 99) <= value;

  /// Dano de comandante de [from] já sofrido por [seat].
  static bool Function(TableView) commanderDamage(int seat, int from, int atLeast) => (t) {
        final cmd = t.state.cards.values.where((c) => c.isCommander && c.owner == from).map((c) => c.id);
        final p = t.state.players[seat];
        return p != null && cmd.any((id) => (p.commanderDamage[id] ?? 0) >= atLeast);
      };

  static bool Function(TableView) turnOf(int seat) => (t) => t.state.activeSeat == seat;
  static bool Function(TableView) handAtLeast(int seat, int n) => (t) => t.handCount(seat) >= n;

  /// Uma seta de [from] (carta do jogador) para [to] (carta de outro): um bloqueio.
  static bool Function(TableView) arrow(String from, String to) => (t) {
        final f = t.cardsNamed(from, zone: Zone.battlefield, seat: 0).map((c) => c.id).toSet();
        final d = t.cardsNamed(to, zone: Zone.battlefield).map((c) => c.id).toSet();
        return t.state.targets.any((m) => f.contains(m.from) && d.contains(m.card));
      };

  /// Pelo menos [n] cartas com este nome desviradas.
  static bool Function(TableView) untapped(String name, {int n = 1, int seat = 0}) =>
      (t) => t.cardsNamed(name, zone: Zone.battlefield, seat: seat).where((c) => !c.tapped).length >= n;

  /// [name] anexada a [to] (um equipamento numa criatura).
  static bool Function(TableView) attached(String name, String to, {int seat = 0}) => (t) {
        final targets = t.cardsNamed(to, zone: Zone.battlefield, seat: seat).map((c) => c.id).toSet();
        return t
            .cardsNamed(name, zone: Zone.battlefield, seat: seat)
            .any((c) => targets.contains(c.attachedTo));
      };

  /// Contadores [kind] de [name] entre [min] e [max].
  static bool Function(TableView) counters(String name, String kind, {int min = 0, int max = 1 << 30}) =>
      (t) => t.cardsNamed(name, zone: Zone.battlefield, seat: 0).any((c) {
            final v = c.counters[kind] ?? 0;
            return v >= min && v <= max;
          });

  static bool Function(TableView) mulliganed(int seat) => (t) => t.mulligans(seat) >= 1;

  static bool Function(TableView) all(List<bool Function(TableView)> list) => (t) => list.every((f) => f(t));
}
