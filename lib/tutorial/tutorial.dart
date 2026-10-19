import 'package:mesa_core/mesa_core.dart';

import '../l10n/l10n.dart';

/// Um tutorial é uma lista de capítulos. Cada capítulo tem páginas para ler
/// e, quase sempre, um bocado de jogo guiado: os passos dizem o que fazer,
/// a mesa só deixa fazer isso e os adversários jogam por guião.
///
/// Os textos estão em português e traduzem-se ao serem lidos (os getters).
class Chapter {
  const Chapter({
    required this.id,
    required String title,
    required String summary,
    this.pages = const [],
    this.setup,
    this.steps = const [],
    this.minutes = 3,
  })  : _title = title,
        _summary = summary;

  final String id;
  final String _title;
  final String _summary;
  String get title => tr(_title);

  /// Uma frase para a lista de capítulos.
  String get summary => tr(_summary);
  final List<TPage> pages;

  /// A mesa no início da parte jogada (null = só páginas).
  final TSetup? setup;
  final List<TStep> steps;
  final int minutes;

  bool get hasGame => setup != null && steps.isNotEmpty;
}

/// Uma página de explicação, com cartas de exemplo opcionais.
class TPage {
  const TPage(String title, String body, {this.cards = const []})
      : _title = title,
        _body = body;
  final String _title;
  final String _body;
  String get title => tr(_title);

  /// Texto; **assim** fica a negrito. Linhas começadas por "• " são listas.
  String get body => tr(_body);
  final List<TCard> cards;
}

/// Uma carta de exemplo numa página: [ok] mostra um visto (pode) ou uma cruz
/// (não pode); null não mostra nada.
class TCard {
  const TCard(this.name, {String? caption, this.ok}) : _caption = caption;
  final String name;
  final String? _caption;
  String? get caption => _caption == null ? null : tr(_caption);
  final bool? ok;
}

/// Um lugar à mesa no início do capítulo.
class TSeat {
  const TSeat({
    required this.name,
    this.commander,
    this.battlefield = const [],
    this.hand = const [],
    this.library = const [],
    this.life = 40,
  });

  final String name;
  final String? commander;

  /// Cartas já em campo (os terrenos ficam em baixo).
  final List<String> battlefield;

  /// Mão inicial (fica na mão por esta ordem).
  final List<String> hand;

  /// O resto do grimório, do topo para o fundo.
  final List<String> library;
  final int life;
}

/// A mesa no início da parte jogada. O lugar 0 é o jogador.
class TSetup {
  const TSetup({required this.seats, this.active = 0, this.turn = 1, this.prepare = const []});
  final List<TSeat> seats;
  final int active;
  final int turn;

  /// Ações de preparação (contadores, dano já sofrido, comandante em campo…),
  /// feitas antes de o jogador ver a mesa.
  final List<Act> prepare;
}

/// O que o jogador tentou fazer, já com os nomes das cartas.
class TAction {
  const TAction(this.seat, this.intent, {this.names = const [], this.from, this.to});
  final int seat;
  final Intent intent;
  final List<String> names;
  final Zone? from;
  final Zone? to;

  String get type => intent.type;
  Map<String, dynamic> get p => intent.payload;
  bool has(String name) => names.contains(name);
}

/// Um passo: o texto do guia, o que se pode fazer e quando está feito.
/// Sem [done], o passo é só para ler (botão "Continuar").
class TStep {
  const TStep(String text,
      {this.allow,
      this.done,
      String? hint,
      this.run = const [],
      this.focus = const [],
      this.view,
      String? title})
      : _text = text,
        _hint = hint,
        _title = title;

  final String? _title;
  final String _text;
  final String? _hint;
  String? get title => _title == null ? null : tr(_title);
  String get text => tr(_text);

  /// Ações do jogador aceites neste passo; as outras são bloqueadas.
  final bool Function(TAction a)? allow;

  /// Condição (sobre a mesa) que termina o passo.
  final bool Function(TableView t)? done;

  /// O que dizer quando o jogador faz outra coisa.
  String? get hint => _hint == null ? null : tr(_hint);

  /// O que acontece antes do texto aparecer (os adversários jogam).
  final List<Act> run;

  /// Cartas a destacar (na mão, no campo e na zona de comando): onde tocar.
  final List<String> focus;

  /// Mostra o campo deste lugar durante o passo (para ver o que o texto diz).
  final int? view;
}

/// Uma ação com guião, feita por um lugar (normalmente um adversário).
/// [say] aparece no guia enquanto acontece.
sealed class Act {
  const Act({String? say}) : _say = say;
  final String? _say;
  String? get say => _say == null ? null : tr(_say);
}

/// Jogar uma carta da mão (ou do grimório) para o campo.
class Play extends Act {
  const Play(this.seat, this.name, {super.say});
  final int seat;
  final String name;
}

/// Lançar um instantâneo ou feitiço: vai para o cemitério.
class Cast extends Act {
  const Cast(this.seat, this.name, {super.say});
  final int seat;
  final String name;
}

/// Lançar o comandante (paga a taxa).
class CastCommander extends Act {
  const CastCommander(this.seat, {super.say});
  final int seat;
}

class Tap extends Act {
  const Tap(this.seat, this.names, {super.say, this.value = true});
  final int seat;
  final List<String> names;
  final bool value;
}

class UntapAll extends Act {
  const UntapAll(this.seat, {super.say});
  final int seat;
}

/// Mudar a vida de um lugar.
class Life extends Act {
  const Life(this.seat, this.delta, {super.say});
  final int seat;
  final int delta;
}

/// Dano de combate do comandante de [from] a [to].
class CommanderHit extends Act {
  const CommanderHit(this.from, this.to, this.amount, {super.say});
  final int from;
  final int to;
  final int amount;
}

/// Mover uma carta pública (pelo nome) de [seat] para outra zona.
class MoveCard extends Act {
  const MoveCard(this.seat, this.name, this.to, {super.say});
  final int seat;
  final String name;
  final Zone to;
}

class Counter extends Act {
  const Counter(this.seat, this.name, this.kind, this.delta, {super.say});
  final int seat;
  final String name;
  final String kind;
  final int delta;
}

class Token extends Act {
  const Token(this.seat, this.tokenName, this.pt, {this.qty = 1, super.say});
  final int seat;
  final String tokenName;
  final String pt;
  final int qty;
}

class Draw extends Act {
  const Draw(this.seat, [this.n = 1, String? say]) : super(say: say);
  final int seat;
  final int n;
}

class PassTurn extends Act {
  const PassTurn({super.say});
}

class Concede extends Act {
  const Concede(this.seat, {super.say});
  final int seat;
}

/// Um adversário aponta para uma carta (o alvo de um feitiço, ou um ataque).
class Target extends Act {
  const Target(this.seat, this.name, {this.targetSeat, super.say});
  final int seat;
  final String name;

  /// Dono da carta apontada (null = qualquer um).
  final int? targetSeat;
}

/// Atacar: vira a criatura e aponta-a ao jogador atacado.
class Attack extends Act {
  const Attack(this.seat, this.name, this.target, {super.say});
  final int seat;
  final String name;
  final int target;
}

/// Atacar uma carta (um planeswalker): vira a criatura e aponta-a à carta.
class AttackCard extends Act {
  const AttackCard(this.seat, this.name, this.target, {this.targetSeat = 0, super.say});
  final int seat;
  final String name;
  final String target;
  final int targetSeat;
}

/// Apaga as setas de um lugar.
class ClearTargets extends Act {
  const ClearTargets(this.seat, {super.say});
  final int seat;
}

/// Repõe a mão de um lugar com estas cartas (depois de um mulligan de
/// treino, para o resto do capítulo continuar com o guião).
class SetHand extends Act {
  const SetHand(this.seat, this.names, {super.say});
  final int seat;
  final List<String> names;
}

/// Só uma pausa com texto (por exemplo "O Bruno pensa…").
class Pause extends Act {
  const Pause({super.say, this.ms = 900});
  final int ms;
}

/// Leitura da mesa para as condições dos passos.
abstract class TableView {
  GameState get state;
  String? nameOf(String? oracleId);
  List<CardInstance> cardsNamed(String name, {Zone? zone, int? seat});
  int handCount(int seat);
  int mulligans(int seat);
  bool inHand(int seat, String name);
}

/// Atalhos para escrever os passos.
abstract final class Allow {
  /// Jogar [name] da mão para o campo.
  static bool Function(TAction) play(String name) =>
      (a) => a.type == Ev.move && a.from == Zone.hand && a.to == Zone.battlefield && a.has(name);

  /// Lançar [name] da mão (instantâneo ou feitiço: vai para o cemitério).
  static bool Function(TAction) cast(String name) =>
      (a) => a.type == Ev.move && a.from == Zone.hand && a.to == Zone.graveyard && a.has(name);

  /// Virar (ou desvirar) só cartas com estes nomes.
  static bool Function(TAction) tap(List<String> names) =>
      (a) => a.type == Ev.tap && a.names.isNotEmpty && a.names.every(names.contains);

  /// Mover [name] para [to] (de qualquer zona, ou de [from]).
  static bool Function(TAction) move(String name, Zone to, {Zone? from}) =>
      (a) => a.type == Ev.move && a.to == to && (from == null || a.from == from) && a.has(name);

  static bool Function(TAction) life(int seat) => (a) => a.type == Ev.life && a.p['seat'] == seat;

  static bool Function(TAction) commanderDamage(int seat) =>
      (a) => a.type == Ev.commanderDamage && a.p['seat'] == seat;

  /// Anexar [name] (um equipamento ou uma aura) a [to].
  static bool Function(TAction) attach(String name, String to) =>
      (a) => a.type == Ev.attach && a.names.firstOrNull == name && a.names.skip(1).contains(to);

  /// Desvirar só cartas com estes nomes.
  static bool Function(TAction) untap(List<String> names) =>
      (a) => a.type == Ev.tap && a.p['value'] == false && a.names.isNotEmpty && a.names.every(names.contains);

  /// Mexer nos contadores [kind] de [name] (inclui as habilidades de lealdade).
  static bool Function(TAction) counter(String name, String kind) =>
      (a) => a.type == Ev.counter && a.p['kind'] == kind && a.has(name);

  /// Tirar contadores [kind] a [name] à mão (dano num planeswalker), sem usar habilidades.
  static bool Function(TAction) counterDown(String name, String kind) => (a) {
        if (a.type != Ev.counter || a.p['kind'] != kind || a.p['ability'] != null || !a.has(name)) {
          return false;
        }
        // "−" tira um; escrever o número também serve.
        return ((a.p['delta'] as num?) ?? 0) < 0 || a.p['value'] != null;
      };

  static bool passTurn(TAction a) => a.type == Ev.passTurn;
  static bool mulligan(TAction a) => a.type == Ev.mulligan || a.type == Ev.bottom;
  static bool draw(TAction a) => a.type == Ev.draw;

  static bool Function(TAction) any(List<bool Function(TAction)> list) => (a) => list.any((f) => f(a));
}
