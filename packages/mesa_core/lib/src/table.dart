import 'dart:math';

import 'events.dart';
import 'model.dart';
import 'i18n.dart';

/// A mesa vista por um dispositivo: o estado público (igual em todos) mais
/// as zonas ocultas dos lugares que este dispositivo controla.
///
/// [apply] é determinista: dados os mesmos eventos pela mesma ordem, todos
/// os dispositivos chegam ao mesmo estado público.
class Table {
  Table({required String format, Set<int> localSeats = const {}, Random? random})
      : state = GameState(format: format, players: {}),
        localSeats = {...localSeats},
        _random = random ?? Random();

  GameState state;

  /// Lugares cujas zonas ocultas estão neste dispositivo (o meu; no
  /// hot-seat, todos).
  final Set<int> localSeats;
  final Map<int, PrivateZones> private = {};
  final Random _random;
  final List<_Snapshot> _history = [];
  final Map<int, int> _idCounters = {};
  final Map<int, List<PrivateCard>> _pendingDecks = {};
  int _pid = 1;

  static const historyLimit = 60;

  PrivateZones zonesOf(int seat) => private.putIfAbsent(seat, PrivateZones.new);

  /// Novo id de instância para cartas que o lugar [seat] torna públicas.
  int newId(int seat) {
    final n = (_idCounters[seat] ?? 0) + 1;
    _idCounters[seat] = n;
    return seat * 1000000 + n;
  }

  int _newPid() => _pid++;

  // ---------------------------------------------------------------------
  // Aplicar eventos
  // ---------------------------------------------------------------------

  /// Aplica um evento já ordenado. Devolve false se foi ignorado (por
  /// exemplo um undo que já não é válido).
  bool apply(int seq, String type, int actor, Map<String, dynamic> p) {
    if (type == Ev.undo) return _undo(seq, actor, (p['seq'] as num).toInt());

    final snapshot =
        _Snapshot(seq, actor, type, state.clone(), {for (final e in private.entries) e.key: e.value.clone()});
    state.seq = seq;
    String? text;
    try {
      text = _applyInner(type, actor, p);
    } catch (_) {
      // Evento inválido (lugar inexistente, payload estragado...): é
      // ignorado da mesma forma em todos os dispositivos.
      state = snapshot.state;
      private
        ..clear()
        ..addAll(snapshot.private);
      state.seq = seq;
      return false;
    }
    if (!Ev.silent.contains(type)) {
      _history.add(snapshot);
      if (_history.length > historyLimit) _history.removeAt(0);
    }
    if (text != null && !Ev.silent.contains(type)) {
      state.log.add(LogEntry(seq, actor, type, text));
    }
    return true;
  }

  /// Último evento que entrou no registo (para saber o que se pode desfazer).
  LogEntry? get lastLogged => state.log.isEmpty ? null : state.log.last;

  bool canUndo(int seat) {
    final last = _history.isEmpty ? null : _history.last;
    return last != null && last.actor == seat && last.type != Ev.startGame && last.type != Ev.joinTable;
  }

  int? get lastUndoableSeq => _history.isEmpty ? null : _history.last.seq;

  bool _undo(int seq, int actor, int target) {
    if (_history.isEmpty) return false;
    final last = _history.last;
    if (last.seq != target || last.actor != actor) return false;
    _history.removeLast();
    final undone = state.log.isNotEmpty ? state.log.last.text : last.type;
    state = last.state;
    private
      ..clear()
      ..addAll(last.private);
    state.seq = seq;
    state.log.add(LogEntry(seq, actor, Ev.undo, mesaTr('{v} desfez: {undone}', {'v': _n(actor), 'undone': undone})));
    return true;
  }

  String _n(int seat) => state.players[seat]?.name ?? mesaTr('Jogador {seat}', {'seat': seat});
  String _cardName(CardInstance c) => c.oracleId == null ? (c.tokenName ?? 'token') : '[[${c.oracleId}]]';

  String? _applyInner(String type, int actor, Map<String, dynamic> p) {
    int i(String k) => (p[k] as num).toInt();
    int? oi(String k) => (p[k] as num?)?.toInt();
    final s = state;

    switch (type) {
      case Ev.joinTable:
        final seat = i('seat');
        s.players[seat] = PlayerState(seat: seat, name: p['name'] as String, life: i('life'));
        return mesaTr('{v} sentou-se à mesa', {'v': p['name']});

      case Ev.startGame:
        s.started = true;
        s.activeSeat = oi('first') ?? s.players.keys.first;
        s.turn = 1;
        s.phase = 'main1';
        return mesaTr('Jogo começou. {v} joga primeiro', {'v': _n(s.activeSeat)});

      case Ev.deckLoaded:
        final seat = i('seat');
        final pl = s.players[seat]!;
        pl.libraryCount = i('size');
        pl.handCount = 0;
        for (final c in (p['commanders'] as List? ?? const []).cast<Map<String, dynamic>>()) {
          final id = (c['id'] as num).toInt();
          s.cards[id] = CardInstance(
            id: id,
            oracleId: c['o'] as String,
            owner: seat,
            controller: seat,
            zone: Zone.command,
            isCommander: true,
            order: s.maxOrder() + 1,
            printId: c['p'] as String?,
          );
        }
        if (localSeats.contains(seat)) {
          final deck = _pendingDecks.remove(seat) ?? const [];
          zonesOf(seat)
            ..library.clear()
            ..library.addAll(deck)
            ..hand.clear();
          // O tutorial usa grimórios com ordem fixa (o topo é o primeiro).
          if (p['keep'] != true) zonesOf(seat).library.shuffle(_random);
        }
        return mesaTr('{v} baralhou um deck de {v2} cartas', {'v': _n(seat), 'v2': i('size')});

      case Ev.passTurn:
        final seats = s.players.keys.toList()..sort();
        final alive = seats.where((x) => !s.players[x]!.defeated).toList();
        if (alive.isEmpty) return null;
        var next = oi('next');
        if (next == null) {
          final idx = alive.indexOf(s.activeSeat);
          next = alive[(idx + 1) % alive.length];
        }
        s.activeSeat = next;
        s.turn++;
        s.phase = 'upkeep';
        s.storm = 0;
        s.targets.clear();
        s.highlight = null;
        for (final c in s.cards.values) {
          if (c.zone == Zone.battlefield && c.controller == next) c.tapped = false;
        }
        return mesaTr('Turno {turn}: {v}', {'turn': s.turn, 'v': _n(next)});

      case Ev.setPhase:
        s.phase = p['phase'] as String;
        return null;

      case Ev.untapAll:
        final seat = i('seat');
        for (final c in s.cards.values) {
          if (c.zone == Zone.battlefield && c.controller == seat) c.tapped = false;
        }
        return mesaTr('{v} desvirou tudo', {'v': _n(seat)});

      case Ev.move:
        return _move(actor, p);

      case Ev.tap:
        final value = p['value'] == true;
        final ids = (p['ids'] as List).cast<num>().map((e) => e.toInt());
        final names = <String>[];
        for (final id in ids) {
          final c = s.cards[id];
          if (c == null || c.zone != Zone.battlefield) continue;
          c.tapped = value;
          names.add(_cardName(c));
        }
        if (names.isEmpty) return null;
        return '${_n(actor)} ${value ? 'virou' : 'desvirou'} ${names.join(', ')}';

      case Ev.flip:
        final c = s.cards[i('id')];
        if (c == null) return null;
        c.faceIndex = c.faceIndex == 0 ? 1 : 0;
        return mesaTr('{v} transformou {v2}', {'v': _n(actor), 'v2': _cardName(c)});

      case Ev.faceDown:
        final c = s.cards[i('id')];
        if (c == null) return null;
        c.faceDown = p['value'] == true;
        return c.faceDown
            ? mesaTr('{v} virou uma carta para baixo', {'v': _n(actor)})
            : mesaTr('{v} revelou {v2}', {'v': _n(actor), 'v2': _cardName(c)});

      case Ev.attach:
        final c = s.cards[i('id')];
        if (c == null) return null;
        final to = oi('to');
        c.attachedTo = to;
        if (to == null) return mesaTr('{v} desanexou {v2}', {'v': _n(actor), 'v2': _cardName(c)});
        final target = s.cards[to];
        if (target != null) {
          c
            ..x = target.x
            ..y = target.y;
        }
        return mesaTr('{v} anexou {v2} a {v3}', {'v': _n(actor), 'v2': _cardName(c), 'v3': target == null ? '?' : _cardName(target)});

      case Ev.control:
        final c = s.cards[i('id')];
        if (c == null) return null;
        c.controller = i('seat');
        for (final a in s.cards.values.where((a) => a.attachedTo == c.id)) {
          a.controller = c.controller;
        }
        return mesaTr('{v} passou a controlar {v2}', {'v': _n(c.controller), 'v2': _cardName(c)});

      case Ev.position:
        final c = s.cards[i('id')];
        if (c == null) return null;
        final dx = (p['x'] as num).toDouble() - c.x;
        final dy = (p['y'] as num).toDouble() - c.y;
        c
          ..x = (p['x'] as num).toDouble()
          ..y = (p['y'] as num).toDouble();
        for (final a in s.cards.values.where((a) => a.attachedTo == c.id)) {
          a
            ..x += dx
            ..y += dy;
        }
        return null;

      case Ev.counter:
        final c = s.cards[i('id')];
        if (c == null) return null;
        final kind = p['kind'] as String;
        final before = c.counters[kind] ?? 0;
        // "value" fixa o valor; "delta" soma.
        final v = oi('value') ?? before + i('delta');
        final signed = CounterKind.isSigned(kind);
        if (v == 0 || (!signed && v < 0)) {
          c.counters.remove(kind);
        } else {
          c.counters[kind] = v;
        }
        final now = c.counters[kind] ?? 0;
        // Habilidade de lealdade de um planeswalker ("+1", "−4"…).
        if (p['ability'] is String) {
          return mesaTr('{v} usou {v2} de {v3} (lealdade {now})', {'v': _n(actor), 'v2': p['ability'], 'v3': _cardName(c), 'now': now});
        }
        if (kind.startsWith(CounterKind.keyword)) {
          final kw = kind.substring(CounterKind.keyword.length);
          return now > 0
              ? mesaTr('{v} deu {kw} a {v2}', {'v': _n(actor), 'kw': kw, 'v2': _cardName(c)})
              : mesaTr('{v} tirou {kw} a {v2}', {'v': _n(actor), 'kw': kw, 'v2': _cardName(c)});
        }
        final label = switch (kind) {
          CounterKind.modPower => mesaTr('poder'),
          CounterKind.modToughness => mesaTr('resistência'),
          _ => mesaTr('contadores {kind}', {'kind': kind}),
        };
        return mesaTr('{v}: {v2} com {v3}{now} {label}', {'v': _n(actor), 'v2': _cardName(c), 'v3': signed && now > 0 ? '+' : '', 'now': now, 'label': label});

      case Ev.token:
        final id = i('newId');
        final seat = oi('seat') ?? actor;
        final c = CardInstance(
          id: id,
          oracleId: p['o'] as String?,
          owner: seat,
          controller: seat,
          zone: Zone.battlefield,
          isToken: true,
          tokenName: p['name'] as String?,
          tokenPt: p['pt'] as String?,
          printId: p['p'] as String?,
          stackQty: oi('qty') ?? 1,
          x: (p['x'] as num?)?.toDouble() ?? 0.5,
          y: (p['y'] as num?)?.toDouble() ?? 0.5,
          order: s.maxOrder() + 1,
        );
        s.cards[id] = c;
        final copyOf = oi('copyOf');
        if (copyOf != null && s.cards[copyOf] != null) {
          c.faceIndex = s.cards[copyOf]!.faceIndex;
        }
        return mesaTr('{v} criou {v2}{v3}{v4}', {'v': _n(actor), 'v2': c.stackQty > 1 ? '${c.stackQty}× ' : '', 'v3': _cardName(c), 'v4': copyOf != null ? mesaTr(' (cópia)') : ''});

      case Ev.tokenQty:
        final c = s.cards[i('id')];
        if (c == null) return null;
        final q = i('qty');
        if (q <= 0) {
          _removeCard(c);
          return mesaTr('{v} removeu {v2}', {'v': _n(actor), 'v2': _cardName(c)});
        }
        c.stackQty = q;
        return '${_n(actor)}: ${_cardName(c)} ×$q';

      case Ev.life:
        final pl = s.players[i('seat')]!;
        final d = i('delta');
        pl.life += d;
        return mesaTr('{v}: vida {v2}{d} ({life})', {'v': pl.name, 'v2': d > 0 ? '+' : '', 'd': d, 'life': pl.life});

      case Ev.commanderDamage:
        final pl = s.players[i('seat')]!;
        final cmd = i('cmdId');
        final d = i('delta');
        pl.commanderDamage[cmd] = ((pl.commanderDamage[cmd] ?? 0) + d).clamp(0, 999);
        pl.life -= d;
        final c = s.cards[cmd];
        return mesaTr('{v}: {v2}{d} dano de comandante de {v3} ({v4}; vida {life})', {'v': pl.name, 'v2': d > 0 ? '+' : '', 'd': d, 'v3': c == null ? '?' : _cardName(c), 'v4': pl.commanderDamage[cmd], 'life': pl.life});

      case Ev.playerCounter:
        final pl = s.players[i('seat')]!;
        final kind = p['kind'] as String;
        final v = ((pl.counters[kind] ?? 0) + i('delta')).clamp(0, 9999);
        v == 0 ? pl.counters.remove(kind) : pl.counters[kind] = v;
        return '${pl.name}: $kind $v';

      case Ev.monarch:
        s.monarch = oi('seat');
        return s.monarch == null ? mesaTr('Ninguém é o monarca') : mesaTr('{v} é o monarca', {'v': _n(s.monarch!)});

      case Ev.initiative:
        s.initiative = oi('seat');
        return s.initiative == null ? mesaTr('Ninguém tem a iniciativa') : mesaTr('{v} tem a iniciativa', {'v': _n(s.initiative!)});

      case Ev.defeated:
        final pl = s.players[i('seat')]!;
        pl.defeated = p['value'] != false;
        return pl.defeated ? mesaTr('{v} foi derrotado', {'v': pl.name}) : mesaTr('{v} voltou ao jogo', {'v': pl.name});

      case Ev.draw:
        final seat = i('seat');
        final pl = s.players[seat]!;
        final n = min(i('n'), pl.libraryCount);
        pl
          ..libraryCount -= n
          ..handCount += n;
        if (localSeats.contains(seat)) {
          final z = zonesOf(seat);
          final take = min(n, z.library.length);
          z.hand.addAll(z.library.take(take));
          z.library.removeRange(0, take);
        }
        return n == 1
            ? mesaTr('{v} comprou 1 carta', {'v': pl.name})
            : mesaTr('{v} comprou {n} cartas', {'v': pl.name, 'n': n});

      case Ev.shuffle:
        final seat = i('seat');
        if (localSeats.contains(seat)) zonesOf(seat).library.shuffle(_random);
        return mesaTr('{v} baralhou o grimório', {'v': _n(seat)});

      case Ev.mulligan:
        final seat = i('seat');
        final pl = s.players[seat]!;
        final size = oi('size') ?? 7;
        final total = pl.handCount + pl.libraryCount;
        pl
          ..handCount = min(size, total)
          ..libraryCount = total - pl.handCount;
        if (localSeats.contains(seat)) {
          final z = zonesOf(seat);
          z.library.addAll(z.hand);
          z.hand.clear();
          z.library.shuffle(_random);
          final take = min(size, z.library.length);
          z.hand.addAll(z.library.take(take));
          z.library.removeRange(0, take);
        }
        return mesaTr('{v} fez mulligan', {'v': pl.name});

      case Ev.bottom:
        final seat = i('seat');
        final pl = s.players[seat]!;
        final pids = (p['pids'] as List).cast<num>().map((e) => e.toInt()).toList();
        pl
          ..handCount -= pids.length
          ..libraryCount += pids.length;
        if (localSeats.contains(seat)) {
          final z = zonesOf(seat);
          for (final pid in pids) {
            final idx = z.hand.indexWhere((c) => c.pid == pid);
            if (idx >= 0) z.library.add(z.hand.removeAt(idx));
          }
        }
        return pids.length == 1
            ? mesaTr('{v} pôs 1 carta da mão no fundo do grimório', {'v': pl.name})
            : mesaTr('{v} pôs {n} cartas da mão no fundo do grimório', {'v': pl.name, 'n': pids.length});

      case Ev.mill:
        final seat = i('seat');
        final pl = s.players[seat]!;
        final items = (p['cards'] as List).cast<Map<String, dynamic>>();
        final to = Zone.byId(p['to'] as String? ?? 'graveyard');
        final names = <String>[];
        for (final it in items) {
          final id = (it['newId'] as num).toInt();
          s.cards[id] = CardInstance(
            id: id,
            oracleId: it['o'] as String,
            owner: seat,
            controller: seat,
            zone: to,
            order: s.maxOrder() + 1,
            faceDown: to == Zone.exile && it['fd'] == true,
            printId: it['p'] as String?,
          );
          names.add('[[${it['o']}]]');
          pl.libraryCount--;
          if (localSeats.contains(seat)) {
            zonesOf(seat).library.removeWhere((c) => c.pid == (it['pid'] as num).toInt());
          }
        }
        return to == Zone.exile
            ? mesaTr('{v} exilou do topo do grimório: {v3}', {'v': pl.name, 'v3': names.join(', ')})
            : mesaTr('{v} pôs do topo do grimório no cemitério: {v3}', {'v': pl.name, 'v3': names.join(', ')});

      case Ev.reveal:
        final seat = i('seat');
        final oids = (p['os'] as List).cast<String>();
        s.revealed = Reveal(seat, oids, p['what'] as String? ?? 'cartas', to: oi('to'));
        return mesaTr('{v} revelou {v2}{v3}: {v4}', {'v': _n(seat), 'v2': p['what'] ?? '', 'v3': oi('to') == null ? '' : mesaTr(' a {v}', {'v': _n(oi('to')!)}), 'v4': oids.map((o) => '[[$o]]').join(', ')});

      case Ev.scryDone:
        final seat = i('seat');
        final top = (p['top'] as List).cast<num>().map((e) => e.toInt()).toList();
        final bottom = (p['bottom'] as List).cast<num>().map((e) => e.toInt()).toList();
        final grave = (p['grave'] as List? ?? const []).cast<Map<String, dynamic>>();
        final pl = s.players[seat]!;
        for (final it in grave) {
          final id = (it['newId'] as num).toInt();
          s.cards[id] = CardInstance(
            id: id,
            oracleId: it['o'] as String,
            owner: seat,
            controller: seat,
            zone: Zone.graveyard,
            order: s.maxOrder() + 1,
            printId: it['p'] as String?,
          );
          pl.libraryCount--;
        }
        if (localSeats.contains(seat)) {
          final z = zonesOf(seat);
          final all = {for (final c in z.library) c.pid: c};
          final graveP = grave.map((g) => (g['pid'] as num).toInt()).toSet();
          final moved = {...top, ...bottom, ...graveP};
          final rest = z.library.where((c) => !moved.contains(c.pid)).toList();
          z.library
            ..clear()
            ..addAll([
              for (final pid in top)
                if (all[pid] != null) all[pid]!
            ])
            ..addAll(rest)
            ..addAll([
              for (final pid in bottom)
                if (all[pid] != null) all[pid]!
            ]);
        }
        final kind = p['kind'] as String? ?? 'scry';
        final n = top.length + bottom.length + grave.length;
        if (kind == 'look') return mesaTr('{v} reordenou o topo do grimório', {'v': pl.name});
        return mesaTr('{v} fez {kind} {n}: {n2} no topo, {v2}', {'v': pl.name, 'kind': kind, 'n': n, 'n2': top.length, 'v2': grave.isEmpty ? mesaTr('{n} no fundo', {'n': bottom.length}) : mesaTr('{n} no cemitério', {'n': grave.length})});

      case Ev.highlight:
        s.highlight = oi('id');
        return null;

      case Ev.arrow:
        final from = oi('from');
        final card = oi('to');
        final seat = oi('seat');
        if (card == null && seat == null) {
          // Sem alvo: limpa os alvos deste jogador.
          s.targets.removeWhere((t) => t.actor == actor);
          return null;
        }
        s.targets.add(TargetMark(actor: actor, from: from, card: card, seat: seat));
        final src = from == null ? null : s.cards[from];
        final what = card != null ? (s.cards[card] == null ? '?' : _cardName(s.cards[card]!)) : _n(seat!);
        return src == null
            ? mesaTr('{v} aponta para {what}', {'v': _n(actor), 'what': what})
            : mesaTr('{v} aponta {v2} para {what}', {'v': _n(actor), 'v2': _cardName(src), 'what': what});

      case Ev.rollDie:
        return mesaTr('{v} lançou um d{v2}: {v3}', {'v': _n(actor), 'v2': p['sides'], 'v3': p['value']});

      case Ev.flipCoin:
        return mesaTr('{v} lançou a moeda: {v2}', {'v': _n(actor), 'v2': p['heads'] == true ? mesaTr('cara') : mesaTr('coroa')});

      case Ev.randomPlayer:
        return mesaTr('{v} sorteou um jogador: {v2}', {'v': _n(actor), 'v2': _n(i('seat'))});

      case Ev.emote:
        return '${_n(actor)}: ${p['text']}';

      case Ev.storm:
        s.storm = oi('value') ?? max(0, s.storm + i('delta'));
        return mesaTr('Storm: {storm}', {'storm': s.storm});

      case Ev.dayNight:
        s.dayNight = p['value'] as String?;
        return switch (s.dayNight) {
          'day' => mesaTr('Passou a ser dia'),
          'night' => mesaTr('Passou a ser noite'),
          _ => mesaTr('Já não é dia nem noite'),
        };

      case Ev.gameOver:
        s
          ..over = true
          ..winner = oi('winner');
        return s.winner == null ? mesaTr('Jogo terminado, sem vencedor') : mesaTr('Jogo terminado: {v} venceu', {'v': _n(s.winner!)});

      default:
        return null;
    }
  }

  void _removeCard(CardInstance c) {
    state.cards.remove(c.id);
    for (final a in state.cards.values.where((a) => a.attachedTo == c.id)) {
      a.attachedTo = null;
    }
    if (state.highlight == c.id) state.highlight = null;
    state.targets.removeWhere((t) => t.from == c.id || t.card == c.id);
  }

  /// Movimentos entre zonas. Quatro casos, conforme origem e destino são
  /// públicos ou ocultos.
  String? _move(int actor, Map<String, dynamic> p) {
    final s = state;
    final to = Zone.byId(p['to'] as String);
    final pos = p['pos'] as String? ?? 'top';
    final x = (p['x'] as num?)?.toDouble();
    final y = (p['y'] as num?)?.toDouble();

    // Origem pública: carta com id.
    final id = (p['id'] as num?)?.toInt();
    if (id != null) {
      final c = s.cards[id];
      if (c == null) return null;
      final from = c.zone;
      final owner = c.owner;
      final name = _cardName(c);
      if (c.isToken && to != Zone.battlefield) {
        _removeCard(c);
        return mesaTr('{v} tirou {name} do jogo', {'v': _n(actor), 'name': name});
      }
      if (to.hidden) {
        // Pública -> oculta: deixa de ser pública.
        _removeCard(c);
        final pl = s.players[owner]!;
        if (to == Zone.hand) {
          pl.handCount++;
        } else {
          pl.libraryCount++;
        }
        if (localSeats.contains(owner) && c.oracleId != null) {
          final card = PrivateCard(_newPid(), c.oracleId!, isCommander: c.isCommander, printId: c.printId);
          final z = zonesOf(owner);
          if (to == Zone.hand) {
            z.hand.add(card);
          } else if (pos == 'bottom') {
            z.library.add(card);
          } else {
            z.library.insert(0, card);
          }
        }
        return mesaTr('{v} pôs {name} {v2}', {'v': _n(actor), 'name': name, 'v2': _where(to, pos, owner)});
      }
      // Pública -> pública.
      // Lançar o comandante: conta para o imposto (2 por cada vez anterior).
      int? castTax;
      if (from == Zone.command && c.isCommander && to == Zone.battlefield) {
        final pl = s.players[owner]!;
        castTax = pl.commanderTax(c.id);
        pl.commanderCasts[c.id] = (pl.commanderCasts[c.id] ?? 0) + 1;
      }
      final leavingField = from == Zone.battlefield && to != Zone.battlefield;
      c.zone = to;
      if (leavingField) {
        c
          ..tapped = false
          ..counters.clear()
          ..faceIndex = 0
          ..faceDown = false
          ..attachedTo = null
          ..controller = c.owner;
        for (final a in s.cards.values.where((a) => a.attachedTo == c.id)) {
          a.attachedTo = null;
        }
      }
      if (to == Zone.battlefield) {
        if (x != null) c.x = x;
        if (y != null) c.y = y;
        if (p['fd'] == true) c.faceDown = true;
        if (from != Zone.battlefield) _entersWith(c, p);
      } else {
        c.controller = c.owner;
      }
      c.order = s.maxOrder() + 1;
      if (from == to) return null;
      if (castTax != null) {
        return mesaTr('{v} lançou o comandante {name}{v2}', {'v': _n(actor), 'name': name, 'v2': castTax > 0 ? mesaTr(' (imposto +{castTax})', {'castTax': castTax}) : ''});
      }
      return mesaTr('{v} moveu {name} {v2}', {'v': _n(actor), 'name': name, 'v2': _whereTo(to, pos)});
    }

    // Origem oculta: carta do dono com pid.
    final seat = (p['seat'] as num).toInt();
    final from = Zone.byId(p['from'] as String);
    final pid = (p['pid'] as num?)?.toInt();
    final pl = s.players[seat]!;
    PrivateCard? card;
    if (localSeats.contains(seat) && pid != null) {
      final z = zonesOf(seat);
      final list = from == Zone.hand ? z.hand : z.library;
      final idx = list.indexWhere((c) => c.pid == pid);
      if (idx >= 0) card = list.removeAt(idx);
    }
    if (from == Zone.hand) {
      pl.handCount = max(0, pl.handCount - 1);
    } else {
      pl.libraryCount = max(0, pl.libraryCount - 1);
    }

    if (to.hidden) {
      // Oculta -> oculta (mão <-> grimório): ninguém mais sabe que carta é.
      if (to == Zone.hand) {
        pl.handCount++;
      } else {
        pl.libraryCount++;
      }
      if (card != null) {
        final z = zonesOf(seat);
        if (to == Zone.hand) {
          z.hand.add(card);
        } else if (pos == 'bottom') {
          z.library.add(card);
        } else {
          z.library.insert(0, card);
        }
      }
      return mesaTr('{v} pôs uma carta {v2} {v3}', {'v': pl.name, 'v2': from == Zone.hand ? mesaTr('da mão') : mesaTr('do grimório'), 'v3': _where(to, pos, seat)});
    }

    // Oculta -> pública: a carta passa a ter id e identidade.
    final newId = (p['newId'] as num).toInt();
    final oid = p['o'] as String;
    s.cards[newId] = CardInstance(
      id: newId,
      oracleId: oid,
      owner: seat,
      controller: seat,
      zone: to,
      x: x ?? 0.5,
      y: y ?? 0.5,
      faceDown: p['fd'] == true,
      isCommander: card?.isCommander ?? (p['cmd'] == true),
      order: s.maxOrder() + 1,
      printId: p['p'] as String?,
    );
    if (to == Zone.battlefield) _entersWith(s.cards[newId]!, p);
    final shown = p['fd'] == true ? mesaTr('uma carta virada para baixo') : '[[$oid]]';
    final who = {'v': pl.name, 'shown': shown};
    return switch ((from, to)) {
      (Zone.hand, Zone.battlefield) => mesaTr('{v} jogou {shown}', who),
      (Zone.hand, Zone.graveyard) =>
        p['cast'] == true ? mesaTr('{v} lançou {shown}', who) : mesaTr('{v} descartou {shown}', who),
      _ => mesaTr('{v} moveu {shown} {v2}', {...who, 'v2': _whereTo(to, pos)}),
    };
  }

  /// Contadores com que a carta entra em campo (a lealdade inicial de um
  /// planeswalker), na mesma ação, para o desfazer apagar tudo de uma vez.
  void _entersWith(CardInstance c, Map<String, dynamic> p) {
    if (c.faceDown || p['ctr'] is! Map) return;
    for (final e in (p['ctr'] as Map).entries) {
      if (e.value is num && (e.value as num) > 0) c.counters[e.key as String] = (e.value as num).toInt();
    }
  }

  /// Destino de um movimento ("moveu X para o cemitério").
  String _whereTo(Zone to, String pos) => switch (to) {
        Zone.library => pos == 'bottom' ? mesaTr('para o fundo do grimório') : mesaTr('para o topo do grimório'),
        Zone.hand => mesaTr('para a mão'),
        Zone.battlefield => mesaTr('para o campo'),
        Zone.graveyard => mesaTr('para o cemitério'),
        Zone.exile => mesaTr('para o exílio'),
        Zone.command => mesaTr('para a zona de comando'),
      };

  String _where(Zone to, String pos, int owner) {
    return switch (to) {
      Zone.library => pos == 'bottom' ? mesaTr('no fundo do grimório') : mesaTr('no topo do grimório'),
      Zone.hand => mesaTr('na mão'),
      Zone.battlefield => mesaTr('no campo'),
      Zone.graveyard => mesaTr('no cemitério'),
      Zone.exile => mesaTr('no exílio'),
      Zone.command => mesaTr('na zona de comando'),
    };
  }

  // ---------------------------------------------------------------------
  // Intenções: o dono usa o que sabe das suas zonas ocultas para as montar.
  // ---------------------------------------------------------------------

  /// Prepara o deck de um lugar local; fica no grimório quando o evento
  /// [Ev.deckLoaded] chegar.
  /// [prints] dá a impressão escolhida de cada carta (oracleId -> printId).
  /// Com [keepOrder] o grimório não é baralhado: o primeiro da lista fica
  /// no topo (para jogos com guião, como o tutorial).
  Intent loadDeck(int seat, List<String> library, List<String> commanders,
      {Map<String, String> prints = const {}, bool keepOrder = false}) {
    _pendingDecks[seat] = [
      for (final o in library) PrivateCard(_newPid(), o, printId: prints[o]),
    ];
    return Intent(Ev.deckLoaded, {
      'seat': seat,
      'size': library.length,
      if (keepOrder) 'keep': true,
      'commanders': [
        for (final o in commanders) {'id': newId(seat), 'o': o, if (prints[o] != null) 'p': prints[o]},
      ],
    });
  }

  Intent draw(int seat, [int n = 1]) => Intent(Ev.draw, {'seat': seat, 'n': n});

  Intent shuffle(int seat) => Intent(Ev.shuffle, {'seat': seat});

  /// Move uma carta da mão ou do grimório (pid) para outra zona.
  /// [cast]: um instantâneo ou feitiço lançado (o registo diz "lançou").
  Intent moveHidden(int seat, Zone from, int pid, Zone to,
      {double? x, double? y, String pos = 'top', bool faceDown = false, bool cast = false}) {
    final z = zonesOf(seat);
    final list = from == Zone.hand ? z.hand : z.library;
    final card = list.firstWhere((c) => c.pid == pid);
    return Intent(Ev.move, {
      'seat': seat,
      'from': from.id,
      'pid': pid,
      'to': to.id,
      'pos': pos,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (faceDown) 'fd': true,
      if (cast) 'cast': true,
      if (!to.hidden) ...{
        'newId': newId(seat),
        'o': card.oracleId,
        if (card.printId != null) 'p': card.printId,
        if (card.isCommander) 'cmd': true,
      },
    });
  }

  /// Move uma carta pública (com id).
  Intent movePublic(int id, Zone to, {double? x, double? y, String pos = 'top', bool faceDown = false}) =>
      Intent(Ev.move, {
        'id': id,
        'to': to.id,
        'pos': pos,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (faceDown) 'fd': true,
      });

  /// Põe as [n] cartas do topo no cemitério (ou no exílio).
  Intent mill(int seat, int n, {Zone to = Zone.graveyard, bool faceDown = false}) {
    final z = zonesOf(seat);
    return Intent(Ev.mill, {
      'seat': seat,
      'to': to.id,
      'cards': [
        for (final c in z.library.take(n))
          {
            'pid': c.pid,
            'newId': newId(seat),
            'o': c.oracleId,
            if (c.printId != null) 'p': c.printId,
            if (faceDown) 'fd': true,
          },
      ],
    });
  }

  /// Revela cartas ocultas (pids) a todos ou a um lugar.
  Intent revealHidden(int seat, Zone from, List<int> pids, {int? to, String? what}) {
    final z = zonesOf(seat);
    final list = from == Zone.hand ? z.hand : z.library;
    final byPid = {for (final c in list) c.pid: c};
    return Intent(Ev.reveal, {
      'seat': seat,
      'os': [
        for (final p in pids)
          if (byPid[p] != null) byPid[p]!.oracleId
      ],
      'what': what ?? (from == Zone.hand ? mesaTr('da mão') : mesaTr('do grimório')),
      if (to != null) 'to': to,
    });
  }

  /// Resultado de scry/surveil: ordem final do topo, fundo e cemitério.
  Intent scryDone(int seat,
      {required List<int> top,
      List<int> bottom = const [],
      List<int> graveyard = const [],
      String kind = 'scry'}) {
    final z = zonesOf(seat);
    final byPid = {for (final c in z.library) c.pid: c};
    return Intent(Ev.scryDone, {
      'seat': seat,
      'kind': kind,
      'top': top,
      'bottom': bottom,
      'grave': [
        for (final p in graveyard)
          {
            'pid': p,
            'newId': newId(seat),
            'o': byPid[p]!.oracleId,
            if (byPid[p]!.printId != null) 'p': byPid[p]!.printId,
          },
      ],
    });
  }

  Intent mulligan(int seat, {int size = 7}) => Intent(Ev.mulligan, {'seat': seat, 'size': size});

  Intent bottom(int seat, List<int> pids) => Intent(Ev.bottom, {'seat': seat, 'pids': pids});

  Intent createToken(int seat,
          {String? oracleId,
          String? name,
          String? pt,
          int qty = 1,
          double x = 0.5,
          double y = 0.5,
          int? copyOf,
          String? printId}) =>
      Intent(Ev.token, {
        'newId': newId(seat),
        'seat': seat,
        if (oracleId != null) 'o': oracleId,
        if (name != null) 'name': name,
        if (pt != null) 'pt': pt,
        'qty': qty,
        'x': x,
        'y': y,
        if (copyOf != null) 'copyOf': copyOf,
        if (printId != null) 'p': printId,
      });

  Intent undo() => Intent(Ev.undo, {'seq': lastUndoableSeq});

  // ---------------------------------------------------------------------
  // Guardar e repor as zonas ocultas (voltar a um jogo em rede)
  // ---------------------------------------------------------------------

  /// Mão e grimório de [seat] e os contadores de ids, para guardar no disco.
  Map<String, dynamic> exportPrivate(int seat) {
    final z = zonesOf(seat);
    return {
      'lib': [for (final c in z.library) c.toJson()],
      'hand': [for (final c in z.hand) c.toJson()],
      'ids': _idCounters[seat] ?? 0,
      'pid': _pid,
    };
  }

  /// Repõe o que [exportPrivate] guardou e passa a tratar [seat] como local.
  void importPrivate(int seat, Map<String, dynamic> j) {
    List<PrivateCard> list(String k) => [
          for (final c in (j[k] as List? ?? const []).cast<Map>())
            PrivateCard.fromJson(c.cast<String, dynamic>())
        ];
    private[seat] = PrivateZones(library: list('lib'), hand: list('hand'));
    _idCounters[seat] = max(_idCounters[seat] ?? 0, (j['ids'] as num?)?.toInt() ?? 0);
    _pid = max(_pid, (j['pid'] as num?)?.toInt() ?? 1);
    localSeats.add(seat);
  }
}

extension TableSave on Table {
  /// A mesa toda (estado público, registo e zonas ocultas dos lugares
  /// locais), para gravar um jogo solo e continuar depois. O "desfazer" não
  /// passa para trás deste ponto.
  Map<String, dynamic> saveAll() => {
        'state': state.toJson(),
        'log': [
          for (final e in state.log) [e.seq, e.actor, e.type, e.text],
        ],
        'private': {for (final s in localSeats) '$s': exportPrivate(s)},
      };

  /// Repõe o que [saveAll] gravou numa mesa nova.
  void restoreAll(Map<String, dynamic> j) {
    state = GameState.fromJson((j['state'] as Map).cast<String, dynamic>());
    for (final e in (j['log'] as List? ?? const []).cast<List>()) {
      state.log.add(LogEntry((e[0] as num).toInt(), (e[1] as num).toInt(), e[2] as String, e[3] as String));
    }
    for (final MapEntry(:key, :value) in (j['private'] as Map? ?? const {}).entries) {
      importPrivate(int.parse(key as String), (value as Map).cast<String, dynamic>());
    }
  }
}

class _Snapshot {
  _Snapshot(this.seq, this.actor, this.type, this.state, this.private);
  final int seq;
  final int actor;
  final String type;
  final GameState state;
  final Map<int, PrivateZones> private;
}
