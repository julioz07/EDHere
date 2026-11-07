import 'dart:async';
import 'dart:math';

import 'package:card_db/card_db.dart' as db;

import '../../bot/forge_engine.dart';
import '../../bot/forge_table.dart';

/// Só em builds de QA (`--dart-define=EDH_QA_MONKEY=true`): nas outras, o código
/// nem entra na app. Joga ao acaso em vez da pessoa para encontrar decisões sem
/// saída; `adb logcat | grep EDHQA` diz o que encontrou.
const kQaMonkey = bool.fromEnvironment('EDH_QA_MONKEY');

/// O jogador ao acaso. Toca só no que a mesa oferece a uma pessoa; quando não há
/// nada, regista DEAD e usa a saída de emergência, como ela faria.
class BotMonkey {
  BotMonkey(this._act);

  final void Function(String kind, [int? id]) _act;
  final _rnd = Random();
  final _seen = <String>{};
  Timer? _timer;
  Timer? _watch;
  String _lastSig = '';
  int _repeats = 0;
  ForgePrompt? _prompt;
  ForgeTableState? _state;
  bool _over = false;
  DateTime? _deadSince;

  static void _log(String s) => print('EDHQA $s'); // ignore: avoid_print

  static String _short(String s) => s.replaceAll('\n', ' | ').substring(0, min(s.length, 160));

  /// Decks ao acaso de toda a base de cartas, em vez dos escolhidos: os decks base
  /// são poucos e o que se procura são as cartas que pedem decisões raras.
  static List<ForgeSeat> randomSeats(List<ForgeSeat> seats, db.CardRepository repo) {
    final rnd = Random();
    db.Card? pick(String query, int span) {
      final r = repo.search(query, limit: 1, offset: rnd.nextInt(span));
      return r.cards.isEmpty ? null : r.cards.first;
    }

    return [
      for (final s in seats)
        () {
          final commander = pick('t:legendary t:creature', 2000);
          final entries = <db.DeckEntry>[
            if (commander != null) db.DeckEntry(oracleId: commander.oracleId, qty: 1, board: db.Board.command),
          ];
          for (var i = 0; i < 61; i++) {
            final c = pick('-t:land', 20000);
            if (c != null) entries.add(db.DeckEntry(oracleId: c.oracleId, qty: 1));
          }
          for (final land in ['Plains', 'Island', 'Swamp', 'Mountain', 'Forest']) {
            final c = repo.findByName(land);
            if (c != null) entries.add(db.DeckEntry(oracleId: c.oracleId, qty: 8));
          }
          _log('DECK ${s.name} commander=${commander?.name} cards=${entries.length}');
          return ForgeSeat(name: s.name, bot: s.bot, deck: db.Deck(name: s.deck.name, format: 'commander', entries: entries));
        }(),
    ];
  }

  void dispose() {
    _timer?.cancel();
    _watch?.cancel();
  }

  void error(String? e) => _log('ERROR ${_short(e ?? '')}');

  /// Cada estado novo. Espera um pouco: o Forge manda a mensagem, os botões e a
  /// seleção em eventos separados.
  void onState(ForgePrompt? prompt, ForgeTableState state) {
    _prompt = prompt ?? _prompt;
    _state = state;
    if (state.over || state.turn >= 30) {
      if (!_over) _log('OVER turn=${state.turn} winner=${state.winner}');
      _over = true;
      return;
    }
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), _decide);
    _watch?.cancel();
    _watch = Timer(const Duration(minutes: 3), () {
      _log('SILENT 3min input=${_prompt?.input} turn=${state.turn} msg=${_short(_prompt?.message ?? '')}');
    });
  }

  void _note(ForgePrompt p) {
    final key = '${p.input}|${p.ok.enabled}|${p.cancel.enabled}|${p.message.split(' ').take(3).join(' ')}';
    if (_seen.add(key)) {
      _log('P input=${p.input} ok=${p.ok.label}/${p.ok.enabled} cancel=${p.cancel.label}/${p.cancel.enabled} '
          'cards=${p.selectableCards.length} players=${p.selectablePlayers.length} play=${p.playable.length} '
          'unseen=${p.unseen.length} msg=${_short(p.message)}');
    }
  }

  void _decide() {
    final p = _prompt;
    final s = _state;
    if (p == null || s == null || _over || p.input == 'wait') return;
    _note(p);
    // o que uma pessoa consegue tocar: uma carta sem sítio na mesa nem na lista é um bug
    final hidden = p.selectableCards.where((id) => s.card(id) == null && !p.unseen.containsKey(id)).toList();
    if (hidden.isNotEmpty) _log('HIDDEN ids=$hidden input=${p.input} msg=${_short(p.message)}');

    final sig = '${p.input}|${p.message}|${p.ok.enabled}|${p.cancel.enabled}|${p.chosen.length}|${s.turn}|${s.phase}';
    _repeats = sig == _lastSig ? _repeats + 1 : 0;
    _lastSig = sig;
    if (_repeats == 12) {
      _log('LOOP input=${p.input} ok=${p.ok.label}/${p.ok.enabled} cancel=${p.cancel.label}/${p.cancel.enabled} '
          'cards=${p.selectableCards.length} play=${p.playable.length} msg=${_short(p.message)}');
    }
    if (_repeats >= 12) {
      // preso a repetir a mesma coisa: procura uma saída
      p.ok.enabled ? _act('ok') : _act('cancel');
      return;
    }
    if (p.canSkip && !p.hasOptions) {
      // logo depois de um toque, a seleção já foi limpa e o jogo ainda não avançou:
      // só é um beco se continuar assim passado o tempo em que a mesa oferece saltar
      _deadSince ??= DateTime.now();
      if (DateTime.now().difference(_deadSince!).inSeconds >= 3) {
        _log('DEAD input=${p.input} msg=${_short(p.message)}');
        _deadSince = null;
        _act('cancel');
      }
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 1), _decide);
      return;
    }
    _deadSince = null;
    final options = [...p.selectableCards.where((id) => s.card(id) != null || p.unseen.containsKey(id))];
    final play = p.playable.toList();
    switch (p.input) {
      case 'priority':
        if (play.isNotEmpty && _rnd.nextDouble() < 0.7) {
          _act('card', play[_rnd.nextInt(play.length)]);
        } else {
          _act('ok');
        }
      case 'pay':
        if (p.ok.enabled) {
          _act('ok');
        } else if (play.isNotEmpty && _repeats < 4) {
          _act('card', play[_rnd.nextInt(play.length)]);
        } else {
          _act('cancel');
        }
      case 'attack' || 'block':
        // os candidatos vêm como jogáveis; há bloqueios obrigatórios que o OK recusa
        final pool = [...options, ...play];
        if (pool.isNotEmpty && (_rnd.nextDouble() < 0.5 || _repeats > 2)) {
          _act('card', pool[_rnd.nextInt(pool.length)]);
        } else {
          _act('ok');
        }
      default:
        final canPlayer = p.selectablePlayers.isNotEmpty;
        if (p.ok.enabled && (_rnd.nextDouble() < 0.5 || (options.isEmpty && !canPlayer))) {
          _act('ok');
        } else if (canPlayer && (options.isEmpty || _rnd.nextBool())) {
          final l = p.selectablePlayers.toList();
          _act('player', l[_rnd.nextInt(l.length)]);
        } else if (options.isNotEmpty) {
          _act('card', options[_rnd.nextInt(options.length)]);
        } else {
          _act('cancel');
        }
    }
    // um toque que o Forge ignora não traz evento novo: tenta outra vez
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), _decide);
  }

  /// A resposta a uma pergunta, dentro do que o diálogo deixa.
  Object? answer(ForgeAsk a) {
    final n = a.options.length;
    final key = 'A${a.kind}|${a.min}|${a.max}|$n';
    if (_seen.add(key)) {
      _log('A kind=${a.kind} min=${a.min} max=${a.max} n=$n amount=${a.amount} msg=${_short(a.title ?? a.message ?? '')}');
    }
    if (a.kind == 'choose' && a.min > n) _log('ASKMIN min=${a.min} n=$n msg=${_short(a.title ?? a.message ?? '')}');
    if (a.kind == 'distribute' && a.atLeastOne && a.amount < n) _log('ASKSPLIT amount=${a.amount} n=$n');
    switch (a.kind) {
      case 'confirm':
        return _rnd.nextBool();
      case 'input':
        return a.numeric ? '${_rnd.nextInt(4)}' : a.initial;
      case 'order':
        return [for (var i = 0; i < n; i++) i]..shuffle(_rnd);
      case 'distribute':
        final split = List.filled(n, a.atLeastOne && a.amount >= n ? 1 : 0);
        var left = a.amount - split.fold(0, (x, y) => x + y);
        while (left > 0 && n > 0) {
          split[_rnd.nextInt(n)]++;
          left--;
        }
        return split;
      default:
        if (a.max <= 0 || n == 0) return <int>[];
        final lo = min(a.min, n);
        final hi = min(a.max, n);
        final count = lo + _rnd.nextInt(hi - lo + 1);
        return ([for (var i = 0; i < n; i++) i]..shuffle(_rnd)).take(count).toList()..sort();
    }
  }
}
