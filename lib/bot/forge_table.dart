import 'package:card_db/card_db.dart' as db;
import 'package:mesa_core/mesa_core.dart';

/// Um jogador num estado do Forge.
class ForgePlayer {
  ForgePlayer.fromMap(Map m)
      : id = m['id'] as int,
        name = m['name'] as String? ?? '',
        life = m['life'] as int? ?? 0,
        handCount = m['hand'] as int? ?? 0,
        libraryCount = m['library'] as int? ?? 0,
        lost = m['lost'] == true,
        counters = {for (final e in ((m['cn'] as Map?) ?? const {}).entries) e.key as String: e.value as int},
        commanderDamage = {
          for (final e in ((m['cmdDmg'] as Map?) ?? const {}).entries) int.parse(e.key as String): e.value as int,
        };

  final int id;
  final String name;
  final int life;
  final int handCount;
  final int libraryCount;
  final bool lost;
  final Map<String, int> counters;

  /// Dano sofrido por comandante (id da carta -> dano).
  final Map<int, int> commanderDamage;

  int get poison => counters['poison'] ?? 0;
}

/// O que o Forge espera da pessoa: a mensagem, os dois botões e o que se pode escolher.
class ForgePrompt {
  ForgePrompt.fromMap(Map m)
      : message = m['msg'] as String? ?? '',
        cardId = m['pcard'] as int?,
        ok = ForgeButton.fromMap(m['ok'] as Map?),
        cancel = ForgeButton.fromMap(m['cancel'] as Map?),
        selectableCards = {for (final id in (m['sel'] as List? ?? const [])) id as int},
        selectablePlayers = {for (final id in (m['selP'] as List? ?? const [])) id as int},
        chosen = {for (final id in (m['chosen'] as List? ?? const [])) id as int},
        playable = {for (final id in (m['play'] as List? ?? const [])) id as int};

  final String message;
  final int? cardId;
  final ForgeButton ok;
  final ForgeButton cancel;
  final Set<int> selectableCards;
  final Set<int> selectablePlayers;

  /// Já escolhidos (alvos, atacantes...).
  final Set<int> chosen;

  /// Com a prioridade: as cartas com alguma jogada possível agora.
  final Set<int> playable;
}

class ForgeButton {
  const ForgeButton(this.label, this.enabled);
  ForgeButton.fromMap(Map? m)
      : label = m?['label'] as String? ?? '',
        enabled = m?['on'] == true;

  final String label;
  final bool enabled;
}

/// Uma opção de uma pergunta: o texto e, se for, a carta ou o jogador.
class ForgeOption {
  ForgeOption.fromMap(Map m)
      : label = m['label'] as String? ?? '',
        cardId = m['card'] as int?,
        cardName = m['n'] as String?,
        playerId = m['player'] as int?;

  final String label;
  final int? cardId;
  final String? cardName;
  final int? playerId;
}

/// Uma pergunta do Forge à espera de resposta (o jogo fica parado até lá).
class ForgeAsk {
  ForgeAsk.fromMap(Map m)
      : id = m['id'] as int,
        kind = m['kind'] as String? ?? 'choose',
        title = m['title'] as String?,
        message = m['msg'] as String?,
        cardId = m['card'] as int?,
        min = m['min'] as int? ?? 1,
        max = m['max'] as int? ?? 1,
        amount = m['amount'] as int? ?? 0,
        atLeastOne = m['atLeastOne'] == true,
        numeric = m['numeric'] == true,
        initial = m['initial'] as String? ?? '',
        labels = [for (final l in (m['labels'] as List? ?? const [])) l as String],
        selected = [for (final i in (m['selected'] as List? ?? const [])) i as int],
        options = [for (final o in (m['options'] as List? ?? const [])) ForgeOption.fromMap(o as Map)];

  final int id;

  /// choose, order, confirm, input ou distribute.
  final String kind;
  final String? title;
  final String? message;
  final int? cardId;
  final int min;
  final int max;
  final int amount;
  final bool atLeastOne;
  final bool numeric;
  final String initial;

  /// Os textos dos botões de "confirm" (sim, não).
  final List<String> labels;
  final List<int> selected;
  final List<ForgeOption> options;
}

/// Um objeto na pilha.
class ForgeStackItem {
  ForgeStackItem.fromMap(Map m)
      : id = m['id'] as int?,
        sourceId = m['src'] as int?,
        name = m['n'] as String?,
        text = m['text'] as String? ?? '',
        controller = m['ctrl'] as int?;

  final int? id;
  final int? sourceId;
  final String? name;
  final String text;
  final int? controller;
}

/// Uma carta como a mesa a desenha: a instância e a carta da base (para a imagem).
class ForgeCardView {
  ForgeCardView(this.instance, this.card,
      {this.sick = false, this.attacking = false, this.blocking = false, this.damage = 0});

  final CardInstance instance;
  final db.Card? card;
  final bool sick;
  final bool attacking;
  final bool blocking;
  final int damage;
}

/// Um estado da mesa enviado pelo Forge, já com as cartas da base de dados.
class ForgeTableState {
  ForgeTableState._({
    required this.turn,
    required this.phase,
    required this.active,
    required this.priority,
    required this.players,
    required this.cards,
    required this.stack,
    required this.log,
    required this.over,
    required this.winner,
  });

  final int turn;
  final String? phase;
  final int? active;
  final int? priority;
  final List<ForgePlayer> players;
  final List<ForgeCardView> cards;
  final List<ForgeStackItem> stack;

  /// O registo, do mais recente para o mais antigo.
  final List<String> log;
  final bool over;
  final int? winner;

  ForgePlayer? player(int id) => players.where((p) => p.id == id).firstOrNull;

  ForgeCardView? card(int id) => cards.where((c) => c.instance.id == id).firstOrNull;

  Iterable<ForgeCardView> zone(int playerId, Zone z) =>
      cards.where((c) => c.instance.zone == z && c.instance.controller == playerId);

  /// Converte o mapa do canal. [names] guarda as cartas já procuradas por nome.
  static ForgeTableState fromMap(Map m, ForgeCardLookup names) {
    final cards = <ForgeCardView>[];
    for (final raw in (m['cards'] as List? ?? const [])) {
      final c = raw as Map;
      final zone = _zone(c['z'] as String?);
      // as cartas de efeito do Forge (a regra do comandante, emblemas) não se desenham
      if (zone == null || c['fx'] == true) continue;
      cards.add(names.view(c, zone));
    }
    return ForgeTableState._(
      turn: m['turn'] as int? ?? 0,
      phase: m['phase'] as String?,
      active: m['active'] as int?,
      priority: m['priority'] as int?,
      players: [for (final p in (m['players'] as List? ?? const [])) ForgePlayer.fromMap(p as Map)],
      cards: cards,
      stack: [for (final s in (m['stack'] as List? ?? const [])) ForgeStackItem.fromMap(s as Map)],
      log: [for (final l in (m['log'] as List? ?? const [])) l as String],
      over: m['type'] == 'over',
      winner: m['winner'] as int?,
    );
  }

  static Zone? _zone(String? forgeZone) => switch (forgeZone) {
        'battlefield' => Zone.battlefield,
        'hand' => Zone.hand,
        'graveyard' => Zone.graveyard,
        'exile' => Zone.exile,
        'command' => Zone.command,
        _ => null,
      };
}

/// Procura as cartas do Forge na base da app (pelo nome Oracle), com cache.
class ForgeCardLookup {
  ForgeCardLookup(this.repo);

  final db.CardRepository repo;
  final _byName = <String, db.Card?>{};

  db.Card? byName(String name) => _byName.putIfAbsent(name, () {
        final hit = repo.findByName(name);
        if (hit != null || !name.contains(' // ')) return hit;
        return repo.findByName(name.substring(0, name.indexOf(' // ')));
      });

  db.Card? token(String name, int? pow, int? tou) => _byName.putIfAbsent('token:$name:$pow/$tou', () {
        // "Goblin Token" no Forge, "Goblin" na base
        final base = name.endsWith(' Token') ? name.substring(0, name.length - 6) : name;
        return repo.tokenNamed(db.TokenHint(base, pt: pow == null ? null : '$pow/$tou'));
      });

  ForgeCardView view(Map c, Zone zone) {
    final isToken = c['tk'] == true;
    final pow = c['pow'] as int?;
    final tou = c['tou'] as int?;
    final card = isToken ? token(c['tn'] as String? ?? '', pow, tou) : byName(c['n'] as String);
    final counters = <String, int>{
      for (final e in ((c['cn'] as Map?) ?? const {}).entries) e.key as String: e.value as int,
    };
    final faceIndex = c['fi'] as int? ?? 0;
    final inst = CardInstance(
      id: c['id'] as int,
      oracleId: card?.oracleId,
      owner: c['ow'] as int,
      controller: c['c'] as int,
      zone: zone,
      tapped: c['t'] == true,
      faceDown: c['fd'] == true,
      faceIndex: faceIndex,
      counters: counters,
      attachedTo: c['at'] as int?,
      isToken: isToken,
      isCommander: c['cmd'] == true,
      tokenName: isToken ? c['tn'] as String? : null,
      tokenPt: isToken && pow != null ? '$pow/$tou' : null,
    );
    // O Forge já dá o P/R final; a mesa soma contadores e modificadores ao da
    // carta, por isso a diferença vai para os modificadores.
    if (pow != null && tou != null && card != null) {
      final face = card.faces.length > faceIndex ? card.faces[faceIndex] : null;
      final basePow = int.tryParse(face?.power ?? card.power ?? '');
      final baseTou = int.tryParse(face?.toughness ?? card.toughness ?? '');
      final net = (counters[CounterKind.plus] ?? 0) - (counters[CounterKind.minus] ?? 0);
      if (basePow != null && baseTou != null) {
        final dp = pow - basePow - net;
        final dt = tou - baseTou - net;
        if (dp != 0) counters[CounterKind.modPower] = dp;
        if (dt != 0) counters[CounterKind.modToughness] = dt;
      }
    }
    return ForgeCardView(inst, card,
        sick: c['sick'] == true, attacking: c['atk'] == true, blocking: c['blk'] == true, damage: c['dmg'] as int? ?? 0);
  }
}
