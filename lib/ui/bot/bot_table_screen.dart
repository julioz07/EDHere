import 'dart:async';
import 'dart:math';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart' hide Table;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesa_core/mesa_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/theme.dart';
import '../../bot/forge_engine.dart';
import '../../bot/forge_table.dart';
import '../../bot/sfx.dart';
import '../../data/providers.dart';
import '../../data/settings.dart';
import '../../l10n/l10n.dart';
import '../cards/card_detail_screen.dart';
import '../table/table_card.dart';
import '../widgets/card_view.dart';
import '../widgets/mana.dart';
import '../widgets/responsive.dart';
import 'bot_dialogs.dart';
import 'bot_effects.dart';
import 'bot_motion.dart';

/// A mesa de uma partida no motor do Forge. As regras e as jogadas do bot são
/// do Forge; a mesa desenha o estado e, se houver uma pessoa a jogar, manda os
/// toques dela (cartas, jogadores, pilha, botões) e responde às perguntas.
class BotTableScreen extends ConsumerStatefulWidget {
  const BotTableScreen({super.key, required this.seats, required this.commander});

  final List<ForgeSeat> seats;
  final bool commander;

  @override
  ConsumerState<BotTableScreen> createState() => _BotTableScreenState();
}

class _BotTableScreenState extends ConsumerState<BotTableScreen> with TickerProviderStateMixin {
  late final db.CardRepository _repo = ref.read(cardRepoProvider)!;
  late final ForgeCardLookup _lookup = ForgeCardLookup(_repo);
  late final bool _live = widget.seats.any((s) => s.bot == null);
  StreamSubscription<Map<String, dynamic>>? _sub;
  ForgeTableState? _state;
  ForgePrompt? _prompt;

  /// Depois de um toque, até chegar o prompt seguinte: os botões ficam parados.
  bool _waiting = false;
  String? _error;

  /// Cartas cujas imagens já foram pedidas.
  final _requested = <String>{};

  /// A jogada do bot em destaque (popup com a carta) e a faixa de início de turno.
  ForgeSpot? _spot;
  Timer? _spotTimer;
  Timer? _waitTimer;
  ({String text, bool mine})? _banner;

  /// O que o bot está a pensar fazer (a carta, os alvos, quem ataca): fica à vista
  /// um pouco antes de ele o fazer.
  BotThought? _think;
  Timer? _thinkTimer;

  /// Com vários adversários: o que está em foco (separadores) e o lado para onde
  /// a mesa desliza. O foco segue o jogo nos momentos que contam (turno, o bot a
  /// pensar, um ataque); tocar num separador escolhe até ao momento seguinte.
  int? _focus;
  int _slide = 1;
  Timer? _focusTimer;

  void _setFocus(int? id) {
    final s = _state;
    if (id == null || s == null || id == s.players.first.id || id == _focus) return;
    final from = s.players.indexWhere((p) => p.id == _focus);
    final to = s.players.indexWhere((p) => p.id == id);
    setState(() {
      _slide = to >= from ? 1 : -1;
      _focus = id;
    });
  }
  Timer? _bannerTimer;
  int _lastTurn = 0;

  /// A vida de cada jogador no início de cada turno (para o gráfico do fim).
  final _lifeHistory = <int, List<int>>{};
  bool _overShown = false;

  /// A moeda ao ar do início: null antes do primeiro prompt; depois quem ganhou (some sozinha).
  bool? _coinWon;
  bool _coinShown = false;

  late BotSpeed _speed = BotSpeed.byId(ref.read(prefsProvider).getString(BotSpeed.prefKey));
  late final BotStops _stops = BotStops.load(ref.read(prefsProvider));

  // Movimento: onde está cada carta, as que estão a voar (escondidas no
  // destino até chegarem), o abanão do dano e o pulsar das setas de combate.
  final _geo = TableGeometry();
  final _areaKey = GlobalKey();
  final _flightKey = GlobalKey<FlightLayerState>();
  final _hidden = <int>{};
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  double _shakeAmp = 0;
  bool _flashMine = false;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  /// A carta em grande (tocar sem largar).
  ForgeCardView? _peek;

  static const _shakeKey = 'bot_shake';
  static const _hapticsKey = 'bot_haptics';
  bool get _shakeOn => ref.read(prefsProvider).getBool(_shakeKey) ?? true;
  bool get _hapticsOn => ref.read(prefsProvider).getBool(_hapticsKey) ?? true;

  Duration get _flightTime => switch (_speed) {
        BotSpeed.slow => const Duration(milliseconds: 560),
        BotSpeed.normal => const Duration(milliseconds: 400),
        BotSpeed.fast => const Duration(milliseconds: 260),
      };

  @override
  void initState() {
    super.initState();
    // As imagens dos dois decks, para não aparecerem cartas de texto a meio.
    final ids = {for (final s in widget.seats) ...s.deck.entries.map((e) => e.oracleId)};
    _requested.addAll(ids);
    ref.read(imagesProvider).ensure(_repo.getMany(ids).values);
    _sub = ForgeEngine.events.listen(_onEvent);
    // o ecrã não se apaga enquanto o bot pensa
    WakelockPlus.enable();
    Sfx.enabled = ref.read(prefsProvider).getBool(Sfx.prefKey) ?? true;
    Sfx.warm();
    ForgeEngine.start(seats: widget.seats, repo: _repo, commander: widget.commander, paceMs: _speed.paceMs)
        .then((_) => ForgeEngine.setStops(_stops))
        .catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  void dispose() {
    _spotTimer?.cancel();
    _bannerTimer?.cancel();
    _waitTimer?.cancel();
    _thinkTimer?.cancel();
    _focusTimer?.cancel();
    _sub?.cancel();
    _shake.dispose();
    _pulse.dispose();
    WakelockPlus.disable();
    ForgeEngine.stop();
    super.dispose();
  }

  void _onEvent(Map<String, dynamic> e) {
    // só em debug: o que o Forge pede, para seguir uma partida pelo logcat
    assert(() {
      if (e['type'] == 'think') debugPrint('forge think: ${e['kind']} by ${e['by']} cards ${e['cards']} players ${e['players']}');
      if (e['type'] == 'prompt' || e['type'] == 'ask') {
        debugPrint(
            'forge ${e['type']} t${e['turn'] ?? ''}: ${'${e['msg'] ?? e['title'] ?? ''}'.replaceAll('\n', ' | ')}');
      }
      return true;
    }());
    if (!mounted) return;
    switch (e['type']) {
      case 'error':
        setState(() => _error = e['error'] as String?);
        return;
      case 'ask':
        _ask(ForgeAsk.fromMap(e));
        return;
      case 'spot':
        final spot = ForgeSpot.fromMap(e);
        if (spot.kind == 'attack') Sfx.attack();
        _spotTimer?.cancel();
        _spotTimer = Timer(spot.duration, () {
          if (mounted) setState(() => _spot = null);
        });
        setState(() => _spot = spot);
        return;
      case 'think':
        final think = BotThought.fromMap(e);
        _thinkTimer?.cancel();
        _thinkTimer = Timer(Duration(milliseconds: (e['ms'] as int? ?? 800) + 300), () {
          if (mounted) setState(() => _think = null);
        });
        setState(() => _think = think);
        final st = _state;
        if (st != null && st.players.length > 2 && think.by != st.players.first.id) {
          _focusTimer?.cancel();
          _setFocus(think.by);
          final me = st.players.first.id;
          final other = [
            ...think.players,
            for (final c in think.cards)
              if (st.card(c)?.instance.controller case final o?) o,
          ].where((id) => id != me && id != think.by).firstOrNull;
          if (other != null) {
            _focusTimer = Timer(Duration(milliseconds: e['ms'] as int? ?? 800), () {
              if (mounted) _setFocus(other);
            });
          }
        }
        return;
      case 'info':
        final msg = [e['title'], e['msg']].whereType<String>().where((s) => s.trim().isNotEmpty).join('\n');
        if (msg.isNotEmpty) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
    }
    final s = ForgeTableState.fromMap(e, _lookup);
    // tokens e cartas que só aparecem a meio (copiadas, roubadas...)
    final fresh = [
      for (final c in s.cards)
        if (c.card != null && _requested.add(c.card!.oracleId)) c.card!,
    ];
    if (fresh.isNotEmpty) ref.read(imagesProvider).ensure(fresh);
    // vida por turno, para o gráfico do fim
    if (s.players.isNotEmpty && (s.turn != _lastTurn || s.over)) {
      for (final p in s.players) {
        _lifeHistory.putIfAbsent(p.id, () => []).add(p.life);
      }
    }
    // faixa no início de cada turno, a dizer de quem é
    if (s.players.isNotEmpty && s.turn > 0 && s.turn != _lastTurn && !s.over) {
      _lastTurn = s.turn;
      Sfx.turn();
      final active = s.player(s.active ?? -1);
      final mine = _live && s.active == s.players.first.id;
      _bannerTimer?.cancel();
      _banner = (
        text: mine ? tr('O teu turno') : tr('Turno de {v}', {'v': active?.name ?? ''}),
        mine: mine,
      );
      _bannerTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _banner = null);
      });
      if (s.players.length > 2 && s.active != s.players.first.id) {
        _focusTimer?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setFocus(s.active);
        });
      }
    }
    final old = _state;
    final specs = old == null || s.players.isEmpty ? const <FlightSpec>[] : _changes(old, s);
    setState(() {
      if (s.players.isNotEmpty) _state = s;
      if (e['type'] == 'prompt') {
        _prompt = ForgePrompt.fromMap(e);
        _waiting = false;
        // o primeiro prompt diz quem ganhou a moeda: se me pergunta se começo, fui eu
        if (_live && !_coinShown && s.turn == 0 && _prompt!.input != 'wait') {
          _coinShown = true;
          _coinWon = _prompt!.input != 'mulligan';
          Timer(const Duration(milliseconds: 2600), () {
            if (mounted) setState(() => _coinWon = null);
          });
        }
      }
      if (s.over) _prompt = null;
    });
    if (s.over && !_overShown) {
      _overShown = true;
      // deixa ver o último golpe antes do ecrã do fim
      Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() {});
      });
    }
    if (specs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final box = _areaKey.currentContext?.findRenderObject();
        if (box is! RenderBox) {
          setState(_hidden.clear);
          return;
        }
        final layer = _flightKey.currentState;
        if (layer == null) {
          setState(_hidden.clear);
          return;
        }
        layer.launch(specs, (k) => _geo.rect(k, box));
      });
      // salvaguarda: nenhuma carta fica escondida se um voo não acabar
      Timer(_flightTime * 4, () {
        if (mounted && _hidden.isNotEmpty) setState(_hidden.clear);
      });
    }
  }

  /// Onde está uma carta (zona e dono) num estado; "stack" se estiver na pilha.
  static String? _where(ForgeTableState st, int id) {
    final c = st.card(id);
    if (c != null) return '${c.instance.zone.name}:${c.instance.controller}';
    if (st.stack.any((i) => i.sourceId == id)) return 'stack';
    return null;
  }

  /// O sítio onde uma carta aparece na mesa: ela própria, se estiver à vista
  /// (campo, a minha mão, comando, pilha), senão o contador da zona.
  String _placeOf(ForgeTableState st, int id, String where, int meId) {
    final c = st.card(id);
    final owner = c?.instance.owner ?? meId;
    final ctrl = c?.instance.controller ?? owner;
    if (where == 'stack' || where.startsWith('battlefield') || where.startsWith('command')) return 'c$id';
    if (where.startsWith('hand')) return ctrl == meId ? 'c$id' : 'hand:$ctrl';
    if (where.startsWith('exile')) return 'exile:$owner';
    return 'grave:$owner';
  }

  /// Compara o estado novo com o anterior: as cartas que mudaram de sítio
  /// voam (a carta jogada da mão para a pilha, da pilha para o campo, a
  /// criatura que morre para o cemitério...), o dano abana a mesa e vibra.
  List<FlightSpec> _changes(ForgeTableState old, ForgeTableState now) {
    final box = _areaKey.currentContext?.findRenderObject();
    if (box is! RenderBox || now.players.isEmpty) return const [];
    final before = _geo.snapshot(box);
    final meId = now.players.first.id;
    final ids = {
      for (final c in old.cards) c.instance.id,
      for (final c in now.cards) c.instance.id,
      for (final i in old.stack)
        if (i.sourceId != null) i.sourceId!,
      for (final i in now.stack)
        if (i.sourceId != null) i.sourceId!,
    };
    final specs = <FlightSpec>[];
    var played = false, died = false, landPlayed = false;
    for (final id in ids) {
      final a = _where(old, id), b = _where(now, id);
      // sem sítio conhecido (a meio de um lançamento, na biblioteca...): não voa
      if (a == b || b == null) continue;
      final c = now.card(id) ?? old.card(id);
      if (a != null && a.startsWith('hand') && (b == 'stack' || b.startsWith('battlefield'))) {
        if (a.startsWith('hand:$meId')) played = true;
        if (b.startsWith('battlefield') && (c?.card?.isLand ?? false)) {
          landPlayed = true;
        } else {
          Sfx.card();
        }
      }
      if ((a?.startsWith('battlefield') ?? false) && b.startsWith('graveyard')) died = true;
      // de onde vem: a própria carta, se se via, senão o contador da zona
      Rect? from = before['c$id'];
      if (from == null && a != null) from = before[_placeOf(old, id, a, meId)];
      if (from == null && a == null) {
        // carta nova à vista: do bot vem da mão dele, minha do grimório (comprar)
        final ctrl = c?.instance.controller ?? meId;
        if (b.startsWith('hand:$meId')) {
          from = before['lib:$meId'];
        } else if (b.startsWith('battlefield') && ctrl != meId && !(c?.instance.isToken ?? false)) {
          from = before['hand:$ctrl'];
        }
      }
      if (from == null) continue;
      final to = _placeOf(now, id, b, meId);
      final vanish = !to.startsWith('c');
      final card = c?.instance.faceDown ?? false ? null : (c?.card ?? _lookup.byName(_stackName(old, now, id) ?? ''));
      specs.add(FlightSpec(cardId: id, card: card, from: from, toKey: to, vanish: vanish));
      if (!vanish) _hidden.add(id);
      if (specs.length >= 10) break;
    }
    if (landPlayed) Sfx.land();
    if (died) Sfx.death();
    // dano: abanar a mesa (mais quando sou eu a sofrer) e vibrar
    for (final p in now.players) {
      final before = old.player(p.id);
      if (before != null && p.life > before.life) Sfx.gain();
      if (before == null || p.life >= before.life) continue;
      Sfx.hit();
      final dmg = before.life - p.life;
      final mine = _live && p.id == meId;
      if (_shakeOn) {
        _shakeAmp = mine ? min(4.0 + 2 * dmg, 16.0) : min(2.0 + dmg, 8.0);
        _flashMine = mine;
        _shake.forward(from: 0);
      }
      if (mine) _haptic(HapticFeedback.mediumImpact);
    }
    if (played) _haptic(HapticFeedback.lightImpact);
    if (died) _haptic(HapticFeedback.selectionClick);
    if (now.over && !old.over) {
      _haptic(HapticFeedback.heavyImpact);
      final meWon = _live && now.winner == meId;
      _live && now.winner != null && !meWon ? Sfx.lose() : Sfx.win();
    }
    return specs;
  }

  String? _stackName(ForgeTableState old, ForgeTableState now, int id) {
    for (final i in [...now.stack, ...old.stack]) {
      if (i.sourceId == id) return i.name;
    }
    return null;
  }

  void _haptic(Future<void> Function() f) {
    if (_hapticsOn) f();
  }

  void _landed(int id) {
    if (mounted && _hidden.remove(id)) setState(() {});
  }

  Future<void> _ask(ForgeAsk ask) async {
    final answer = await showForgeAsk(context, ask, _lookup, _state);
    await ForgeEngine.answer(ask.id, answer);
  }

  void _act(String kind, [int? id]) {
    if (!_live || _state?.over == true) return;
    setState(() => _waiting = true);
    ForgeEngine.act(kind, id);
    // um toque que o Forge ignora (pagar sem mana que chegue, carta que não se
    // pode jogar) não traz prompt novo: os botões voltam, senão ficava preso
    _waitTimer?.cancel();
    _waitTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && _waiting) setState(() => _waiting = false);
    });
  }

  void _peekCard(ForgeCardView c) {
    if (c.card == null || c.instance.faceDown) return;
    _haptic(HapticFeedback.selectionClick);
    setState(() => _peek = c);
  }

  void _openCard(ForgeCardView c) {
    final card = c.card;
    if (card == null || c.instance.faceDown) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CardDetailScreen(card: card)));
  }

  /// Tocar numa carta: a jogar, é uma jogada (o Forge decide o que faz); a ver, abre a ficha.
  void _tapCard(ForgeCardView c) => _live ? _act('card', c.instance.id) : _openCard(c);

  Future<void> _leave() async {
    final s = _state;
    if (_live && s != null && !s.over) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Desistir da partida?')),
          content: Text(tr('O bot ganha esta partida. As partidas contra o bot não ficam guardadas.')),
          // o botão principal é o que não perde nada; desistir fica como texto, a vermelho
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: GameColors.attack),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Desistir')),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Continuar a jogar'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    // antes do primeiro turno (moeda e mulligans) não há "Turno 0"
    final title = s == null
        ? (_live ? tr('Contra o bot') : tr('Bot contra bot'))
        : s.turn < 1
            ? tr('Preparar a mão')
            : tr('Turno {v}', {'v': s.turn});
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      // A mesa é densa: com a letra do sistema muito grande deixava de caber
      // (como em TableScreen; os diálogos ficam com o tamanho escolhido).
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              PopupMenuButton<String>(
                tooltip: tr('Velocidade do bot'),
                icon: const Icon(Icons.speed),
                onSelected: _option,
                itemBuilder: (_) => [
                  for (final v in BotSpeed.values)
                    CheckedPopupMenuItem(value: 'speed:${v.id}', checked: v == _speed, child: Text(v.label)),
                  const PopupMenuDivider(),
                  CheckedPopupMenuItem(value: 'shake', checked: _shakeOn, child: Text(tr('Abanar a mesa com o dano'))),
                  CheckedPopupMenuItem(value: 'haptics', checked: _hapticsOn, child: Text(tr('Vibração'))),
                  CheckedPopupMenuItem(value: 'sound', checked: Sfx.enabled, child: Text(tr('Som'))),
                  if (_live) ...[
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'stops', child: Text(tr('Paragens…'))),
                  ],
                ],
              ),
              if (s != null)
                IconButton(
                  tooltip: tr('Registo'),
                  icon: const Icon(Icons.receipt_long_outlined),
                  onPressed: () => _showLog(s),
                ),
            ],
          ),
          body: _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : s == null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(tr('A baralhar…')),
                    ]))
                  : Stack(key: _areaKey, children: [
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _shake,
                          builder: (context, child) {
                            final t = _shake.value;
                            final a = _shake.isAnimating ? _shakeAmp * (1 - t) : 0.0;
                            return Transform.translate(
                                offset: Offset(sin(t * pi * 9) * a, cos(t * pi * 7) * a * 0.4), child: child);
                          },
                          child: _table(s),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: CombatArrowsPainter(
                                geo: _geo, origin: _areaKey, arrows: s.over ? const [] : _arrows(s), pulse: _pulse),
                          ),
                        ),
                      ),
                      // clarão vermelho quando sou eu a levar dano
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _shake,
                            builder: (context, _) => _flashMine && _shake.isAnimating
                                ? Container(
                                    decoration: BoxDecoration(
                                      gradient: RadialGradient(
                                        radius: 1.1,
                                        colors: [
                                          Colors.transparent,
                                          GameColors.attack.withOpacity(0.45 * (1 - _shake.value)),
                                        ],
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      Positioned.fill(child: FlightLayer(key: _flightKey, duration: _flightTime, onLanded: _landed)),
                      if (_banner != null) Positioned.fill(child: TurnBanner(text: _banner!.text, mine: _banner!.mine)),
                      if (_coinWon != null) Positioned.fill(child: CoinFlip(won: _coinWon!)),
                      Positioned.fill(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _spot == null
                              ? const SizedBox.shrink()
                              : BotSpotlight(key: ValueKey(_spot), spot: _spot!, state: s, lookup: _lookup),
                        ),
                      ),
                      if (s.over && _overShown)
                        Positioned.fill(
                          child: GameOverPanel(
                            state: s,
                            meId: _live ? s.players.first.id : null,
                            history: _lifeHistory,
                            onRematch: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                              builder: (_) => BotTableScreen(seats: widget.seats, commander: widget.commander),
                            )),
                            onLog: () => _showLog(s),
                            onLeave: () => Navigator.of(context).pop(),
                          ),
                        ),
                      if (_peek?.card != null)
                        Positioned.fill(
                          child: CardPeek(
                            card: _peek!.card!,
                            onClose: () => setState(() => _peek = null),
                            onDetails: () {
                              final c = _peek!;
                              setState(() => _peek = null);
                              _openCard(c);
                            },
                          ),
                        ),
                    ]),
        ),
      ),
    );
  }

  void _option(String v) {
    final prefs = ref.read(prefsProvider);
    if (v.startsWith('speed:')) {
      final speed = BotSpeed.byId(v.substring(6));
      setState(() => _speed = speed);
      prefs.setString(BotSpeed.prefKey, speed.id);
      ForgeEngine.setPace(speed.paceMs);
    } else if (v == 'shake') {
      setState(() => prefs.setBool(_shakeKey, !_shakeOn));
    } else if (v == 'haptics') {
      setState(() => prefs.setBool(_hapticsKey, !_hapticsOn));
    } else if (v == 'sound') {
      setState(() => Sfx.enabled = !Sfx.enabled);
      prefs.setBool(Sfx.prefKey, Sfx.enabled);
    } else if (v == 'stops') {
      _editStops();
    }
  }

  /// As paragens (como no Arena): em que fases o jogo espera por mim, no meu
  /// turno e no do bot, e o controlo total.
  Future<void> _editStops() async {
    final labels = [tr('Início'), tr('Principal 1'), tr('Combate'), tr('Principal 2'), tr('Fim')];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void changed() {
          setSheet(() {});
          setState(() {});
          _stops.save(ref.read(prefsProvider));
          ForgeEngine.setStops(_stops);
        }

        final theme = Theme.of(ctx);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Paragens'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                  tr('Onde o jogo espera por ti. Nas outras fases passa sozinho, a não ser que tenhas de decidir alguma coisa.'),
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Row(children: [
                const Expanded(child: SizedBox()),
                SizedBox(
                    width: 88,
                    child: Text(tr('Meu turno'), textAlign: TextAlign.center, style: theme.textTheme.labelMedium)),
                SizedBox(
                    width: 88,
                    child: Text(tr('Turno do bot'), textAlign: TextAlign.center, style: theme.textTheme.labelMedium)),
              ]),
              for (var i = 0; i < labels.length; i++)
                Row(children: [
                  Expanded(child: Text(labels[i])),
                  SizedBox(
                    width: 88,
                    child: Checkbox(
                      value: _stops.full || _stops.mine.contains(i),
                      onChanged: _stops.full
                          ? null
                          : (v) {
                              v == true ? _stops.mine.add(i) : _stops.mine.remove(i);
                              changed();
                            },
                    ),
                  ),
                  SizedBox(
                    width: 88,
                    child: Checkbox(
                      value: _stops.full || _stops.theirs.contains(i),
                      onChanged: _stops.full
                          ? null
                          : (v) {
                              v == true ? _stops.theirs.add(i) : _stops.theirs.remove(i);
                              changed();
                            },
                    ),
                  ),
                ]),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Controlo total')),
                subtitle: Text(tr('Pára em todas as fases e nunca passa sozinho. Para jogadores experientes.')),
                value: _stops.full,
                onChanged: (v) {
                  _stops.full = v;
                  changed();
                },
              ),
            ]),
          ),
        );
      }),
    );
  }

  /// As setas de combate: cada atacante para quem ataca, cada bloqueador para quem bloqueia.
  List<CombatArrow> _arrows(ForgeTableState s) => [
        for (final c in s.cards)
          if (c.attacking && (c.attackCard != null || c.attackPlayer != null))
            CombatArrow('c${c.instance.id}', c.attackCard != null ? 'c${c.attackCard}' : 'player:${c.attackPlayer}',
                block: false),
        for (final c in s.cards)
          for (final a in c.blockingOf) CombatArrow('c${c.instance.id}', 'c$a', block: true),
      ];

  Widget _table(ForgeTableState s) {
    if (s.players.length < 2) return const SizedBox.shrink();
    final narrow = MediaQuery.sizeOf(context).width < 560;
    final settings = ref.watch(settingsProvider);
    final bg = settings.backgroundImage;
    final me = s.players[0];
    final opponents = s.players.skip(1).toList();
    final multi = opponents.length > 1;
    // com vários: o que está em foco (de início, o primeiro que ainda joga)
    final them = s.player(_focus ?? -1) ?? opponents.firstWhere((p) => !p.lost, orElse: () => opponents.first);
    final act = _Interaction(
      prompt: _live && !_waiting ? _prompt : null,
      onCard: _tapCard,
      onDetails: _peekCard,
      onPlayer: _live ? (id) => _act('player', id) : null,
      onStack: _live ? (id) => _act('stack', id) : null,
      geo: _geo,
      hidden: _hidden,
      meId: me.id,
      think: _think,
      thinkColor: _think == null ? null : seatColor(s, _think!.by),
      // arrastar: o atacante para a barra (ou o separador) de um adversário, o
      // bloqueador para o atacante. Com vários, primeiro diz-se ao Forge quem é atacado
      onAttack: _live
          ? (id, defender) {
              if (multi) ForgeEngine.act('player', defender);
              _act('card', id);
            }
          : null,
      onBlock: _live
          ? (attacker, blocker) {
              ForgeEngine.act('card', attacker);
              _act('card', blocker);
            }
          : null,
    );
    // o fundo da mesa escolhido nas Definições, como na mesa normal
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35),
        image: bg == null
            ? null
            : DecorationImage(
                image: bg,
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black.withOpacity(settings.backgroundDim), BlendMode.darken),
              ),
      ),
      child: SafeArea(
        child: Column(children: [
          if (multi)
            _OpponentTabs(
              state: s,
              focus: them.id,
              act: act,
              thinking: _live && !s.over && _prompt?.input == 'wait' ? s.priority : null,
              onPick: (id) {
                _focusTimer?.cancel();
                _setFocus(id);
                // a atacar: tocar num adversário escolhe-o como defensor; a escolher
                // um alvo, tocar no separador escolhe esse jogador
                if (act.attacking && _live) {
                  ForgeEngine.act('player', id);
                } else if (act.playerSelectable(id)) {
                  act.onPlayer?.call(id);
                }
              },
            ),
          _PlayerBar(
              state: s,
              player: them,
              act: act,
              anchored: !multi,
              thinking: _live && !s.over && (_waiting || _prompt?.input == 'wait') && (!multi || s.priority == them.id)),
          Expanded(
            child: !multi
                ? _Battlefield(state: s, player: them.id, flipped: true, act: act)
                : ClipRect(
                    // a mesa do adversário desliza para o lado do lugar dele, sem piscar
                    child: AnimatedSwitcher(
                      duration: Duration(milliseconds: _flightTime.inMilliseconds * 3 ~/ 4),
                      switchInCurve: Curves.easeInOut,
                      switchOutCurve: Curves.easeInOut,
                      transitionBuilder: (child, anim) {
                        final incoming = child.key == ValueKey(them.id);
                        final dx = (incoming ? 1.0 : -1.0) * _slide;
                        return SlideTransition(
                          position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim),
                          child: child,
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(them.id),
                        child: _Battlefield(state: s, player: them.id, flipped: true, act: act),
                      ),
                    ),
                  ),
          ),
          PhaseBar(
            phase: s.phase,
            mine: _live && s.active == me.id,
            compact: narrow,
            stops: !_live ? const {} : (s.active == me.id ? _stops.mine : _stops.theirs),
            onTap: _live ? _editStops : null,
            color: s.active == null ? null : seatColor(s, s.active!),
          ),
          if (!narrow || s.stack.isNotEmpty || !_live) _CenterStrip(state: s, act: act, lookup: _lookup),
          if (_live && !s.over)
            _PromptBar(
                prompt: _prompt,
                waiting: _waiting,
                onButton: _act,
                state: s,
                meId: me.id,
                lookup: _lookup,
                onPlayer: (id) => _act('player', id)),
          Expanded(child: _Battlefield(state: s, player: me.id, act: act)),
          _PlayerBar(state: s, player: me, act: act),
          _Hand(
            cards: s.zone(me.id, Zone.hand).toList(),
            act: act,
            big: _live,
            mulligan: _live && !_waiting && (_prompt?.input == 'mulligan' || _prompt?.input == 'bottom'),
          ),
        ]),
      ),
    );
  }

  void _showLog(ForgeTableState s) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (final l in s.log) Padding(padding: const EdgeInsets.only(bottom: 6), child: OracleText(logLine(l)))
        ],
      ),
    );
  }
}

/// O que cada parte da mesa precisa para reagir aos toques e mostrar o que se pode escolher.
class _Interaction {
  const _Interaction({
    required this.prompt,
    required this.onCard,
    required this.onDetails,
    required this.onPlayer,
    required this.onStack,
    required this.geo,
    required this.hidden,
    required this.meId,
    this.onAttack,
    this.onBlock,
    this.think,
    this.thinkColor,
  });

  final int meId;

  /// O que o bot está a pensar, e a cor dele.
  final BotThought? think;
  final Color? thinkColor;
  bool gazed(int id) => think?.cards.contains(id) ?? false;
  bool gazedPlayer(int id) => think?.players.contains(id) ?? false;
  final void Function(int attacker, int defender)? onAttack;
  final void Function(int attacker, int blocker)? onBlock;

  bool get attacking => prompt?.input == 'attack';
  bool get blocking => prompt?.input == 'block';

  final TableGeometry geo;

  /// Cartas a voar para o seu lugar: ocupam o espaço mas só aparecem quando chegam.
  final Set<int> hidden;

  /// null quando não há nada à espera da pessoa (ou a ver bot contra bot).
  final ForgePrompt? prompt;
  final void Function(ForgeCardView) onCard;
  final void Function(ForgeCardView) onDetails;
  final void Function(int id)? onPlayer;
  final void Function(int id)? onStack;

  bool selectable(int cardId) =>
      (prompt?.selectableCards.contains(cardId) ?? false) || (prompt?.playable.contains(cardId) ?? false);
  bool chosen(int id) => prompt?.chosen.contains(id) ?? false;

  /// A pagar: as fontes que o botão Auto vai virar (o Arena destaca-as assim).
  bool autoTap(int id) => prompt?.autoTap.contains(id) ?? false;
  bool playerSelectable(int id) => prompt?.selectablePlayers.contains(id) ?? false;

  /// Uma carta da mesa com os toques: tocar joga (ou abre a ficha, a ver), tocar sem largar abre a ficha.
  Widget card(ForgeCardView c, double width, {bool details = true}) {
    final view = _cardView(c, width, details: details);
    final id = c.instance.id;
    final mineCreature = c.instance.controller == meId &&
        c.instance.zone == Zone.battlefield &&
        ((c.card?.frontType.contains('Creature') ?? false) || c.instance.isToken);
    Widget out = view;
    // a criatura agarrada segue o dedo; a original fica meio transparente
    if ((attacking && onAttack != null && selectable(id) && mineCreature) ||
        (blocking && onBlock != null && mineCreature && !c.attacking)) {
      out = Draggable<int>(
        data: id,
        feedback: Material(
          color: Colors.transparent,
          child: Transform.rotate(
            angle: -0.05,
            child: SizedBox(
              width: width * 1.15,
              child: c.card == null ? const CardBack() : CardImage(c.card!),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: view),
        child: view,
      );
    }
    // a bloquear: largar a minha criatura em cima de um atacante
    if (blocking && onBlock != null && c.attacking) {
      // o builder corre depois: tem de ver a carta, não o próprio DragTarget
      final target = out;
      out = DragTarget<int>(
        onAcceptWithDetails: (d) => onBlock!(id, d.data),
        builder: (context, candidates, _) => Container(
          decoration: candidates.isEmpty
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(width * cardCorner),
                  boxShadow: const [BoxShadow(color: GameColors.block, blurRadius: 18, spreadRadius: 4)],
                ),
          child: target,
        ),
      );
    }
    return out;
  }

  Widget _cardView(ForgeCardView c, double width, {bool details = true}) {
    // a atacar a carta não se deita (ocupava o dobro do espaço): avança um
    // pouco para o adversário e inclina-se, como no Arena
    final lunge = c.attacking ? (c.instance.controller == meId ? -1.0 : 1.0) : 0.0;
    return GestureDetector(
      key: geo.key('c${c.instance.id}'),
      onTap: () => onCard(c),
      onLongPress: () => onDetails(c),
      child: Opacity(
        opacity: hidden.contains(c.instance.id) ? 0 : (c.sick ? 0.75 : 1),
        child: Transform.translate(
          offset: Offset(0, lunge * width * 0.12),
          child: Transform.rotate(
            angle: lunge * 0.05,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                // em combate: vermelho a atacar, azul a bloquear (como no Arena)
                decoration: gazed(c.instance.id) && !c.attacking && !c.blocking
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(width * cardCorner),
                        boxShadow: [BoxShadow(color: thinkColor!, blurRadius: 16, spreadRadius: 3)],
                      )
                    : autoTap(c.instance.id)
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(width * cardCorner),
                        boxShadow: const [BoxShadow(color: GameColors.playable, blurRadius: 12, spreadRadius: 3)],
                      )
                    : c.attacking || c.blocking
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(width * cardCorner),
                            boxShadow: [
                              BoxShadow(
                                color: (c.attacking ? GameColors.attack : GameColors.block).withOpacity(0.9),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          )
                        : null,
                child: TableCardView(
                  instance: c.instance,
                  card: c.card,
                  width: width,
                  showDetails: details,
                  showTapped: !c.attacking,
                  highlighted: selectable(c.instance.id),
                  targeted: chosen(c.instance.id),
                ),
              ),
              if (c.attacking || c.blocking)
                Positioned(
                  top: -6,
                  left: -6,
                  child: _Badge(
                    icon: c.attacking ? Icons.sports_martial_arts : Icons.shield,
                    color: c.attacking ? GameColors.attack : GameColors.block,
                  ),
                ),
              if (c.damage > 0)
                Positioned(
                  bottom: -4,
                  right: -4,
                  child: _Badge(text: '-${c.damage}', color: GameColors.damage),
                ),
              // o bot está a olhar para esta carta (é um alvo, ou quem ele vai atacar)
              if (gazed(c.instance.id) && c.instance.controller != think!.by)
                Positioned(top: -8, right: -8, child: _Badge(icon: Icons.visibility, color: thinkColor!)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Com vários adversários: um separador por cada um, na cor do lugar dele, com a
/// vida e o que está a acontecer (a pensar, a atacar, visado). Tocar põe-no em
/// foco; o que está em foco fica mais alto e claro, ligado à barra por baixo.
class _OpponentTabs extends StatelessWidget {
  const _OpponentTabs(
      {required this.state, required this.focus, required this.act, required this.onPick, this.thinking});

  final ForgeTableState state;
  final int focus;
  final _Interaction act;
  final void Function(int id) onPick;

  /// Quem está a pensar (tem a prioridade e é um bot).
  final int? thinking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final opponents = state.players.skip(1).toList();
    final narrow = MediaQuery.sizeOf(context).width < 560;
    // quem está a ser atacado e por quem (as criaturas a atacar e o jogador atacado)
    final attacked = {
      for (final c in state.cards)
        if (c.attacking && c.attackPlayer != null) c.attackPlayer!: c.instance.controller,
    };
    final attacking = {for (final c in state.cards) if (c.attacking) c.instance.controller};
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final p in opponents)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _tab(context, theme, scheme, p, narrow, attacked, attacking),
            ),
          ),
      ]),
    );
  }

  Widget _tab(BuildContext context, ThemeData theme, ColorScheme scheme, ForgePlayer p, bool narrow,
      Map<int, int> attacked, Set<int> attacking) {
    final sel = p.id == focus;
    final color = seatColor(state, p.id);
    final seat = state.players.indexWhere((x) => x.id == p.id);
    final pickable = act.playerSelectable(p.id);
    final fg = sel ? scheme.onSurface : const Color(0xFFE6EAF5);
    final Widget status;
    // a mira é sempre vermelha (pedido do utilizador): em quem posso escolher como
    // alvo, em todos os que posso atacar quando ataco, e em quem é atacado ou visado
    final target = pickable || (act.attacking && !p.lost) || attacked.containsKey(p.id) || act.gazedPlayer(p.id);
    if (target) {
      status = const Icon(Icons.gps_fixed, size: 18, color: GameColors.attack);
    } else if (thinking == p.id) {
      status = const ThinkingDots();
    } else if (attacking.contains(p.id)) {
      status = const Icon(Icons.sports_martial_arts, size: 16, color: GameColors.attack);
    } else {
      status = Text('${p.handCount}', style: theme.textTheme.labelSmall?.copyWith(color: fg));
    }
    // fora de foco: escuros e de texto claro, por cima da mesa (como na maqueta)
    final tab = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: sel ? (narrow ? 58 : 64) : (narrow ? 50 : 56),
      decoration: BoxDecoration(
        color: sel ? scheme.surface : const Color(0xFF1C2645).withOpacity(0.92),
        borderRadius: BorderRadius.vertical(
            top: const Radius.circular(EdhSize.radiusS + 2), bottom: Radius.circular(sel ? 0 : EdhSize.radiusS + 2)),
        boxShadow: pickable ? [BoxShadow(color: GameColors.target.withOpacity(0.6), blurRadius: 10)] : null,
      ),
      // pode ser escolhido como alvo: contorno na cor dos alvos, por cima (um
      // contorno na decoração tira altura ao conteúdo e o separador transbordava)
      foregroundDecoration: pickable
          ? BoxDecoration(
              border: Border.all(color: GameColors.target, width: 3),
              borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(EdhSize.radiusS + 2),
                  bottom: Radius.circular(sel ? 0 : EdhSize.radiusS + 2)),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(height: 4, color: color),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Opacity(
              opacity: p.lost ? 0.45 : 1,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(children: [
                  Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Text('$seat',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: const Color(0xFF10172E), fontWeight: FontWeight.w800, height: 1)),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: FitText(p.name,
                        alignment: Alignment.centerLeft,
                        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: fg)),
                  ),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  Text('${p.life}',
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: fg,
                          decoration: p.lost ? TextDecoration.lineThrough : null)),
                  const Spacer(),
                  status,
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
    final tappable = Semantics(
      button: true,
      selected: sel,
      label: tr('Mesa de {v}', {'v': p.name}),
      child: GestureDetector(onTap: () => onPick(p.id), child: tab),
    );
    // todos os separadores são o destino das setas e dos voos para esse jogador:
    // ao trocar de bot, a seta não salta do separador para a barra
    final keyed = KeyedSubtree(key: act.geo.key('player:${p.id}'), child: tappable);
    if (!act.attacking || act.onAttack == null) return keyed;
    // a atacar: largar a criatura no separador ataca esse adversário
    return DragTarget<int>(
      onAcceptWithDetails: (d) => act.onAttack!(d.data, p.id),
      builder: (context, candidates, _) => Container(
        foregroundDecoration: candidates.isEmpty
            ? null
            : BoxDecoration(
                border: Border.all(color: GameColors.attack, width: 3),
                borderRadius: BorderRadius.circular(EdhSize.radiusS)),
        child: keyed,
      ),
    );
  }
}

/// O que o bot está a pensar fazer, vindo do motor ("think").
class BotThought {
  BotThought({required this.by, required this.kind, required this.cards, required this.players});

  factory BotThought.fromMap(Map m) => BotThought(
        by: m['by'] as int,
        kind: m['kind'] as String? ?? '',
        cards: {for (final c in (m['cards'] as List? ?? const [])) c as int},
        players: {for (final p in (m['players'] as List? ?? const [])) p as int},
      );

  final int by;

  /// cast, attack ou block.
  final String kind;
  final Set<int> cards;
  final Set<int> players;
}

/// A mão de um adversário como versos em leque; o que está [lifted] sobe e
/// brilha na cor dele (é a carta que ele vai jogar).
class _HandBacks extends StatelessWidget {
  const _HandBacks({required this.count, required this.color, this.small = false, this.lifted});

  static const maxShown = 7;

  final int count;
  final Color color;
  final bool small;
  final int? lifted;

  @override
  Widget build(BuildContext context) {
    final n = min(count, maxShown);
    final w = small ? 16.0 : 26.0;
    final h = w / cardAspect;
    final step = w * 0.45;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: n == 0 ? 0 : w + step * (n - 1),
        height: h + 10,
        child: Stack(clipBehavior: Clip.none, children: [
          for (var i = 0; i < n; i++)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              left: step * i,
              top: i == lifted ? 0 : 10,
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: const Color(0xFF26345F),
                  borderRadius: BorderRadius.circular(w * cardCorner * 2),
                  border: Border.all(color: Colors.white.withOpacity(0.5), width: 0.8),
                  boxShadow: i == lifted ? [BoxShadow(color: color, blurRadius: 10, spreadRadius: 2)] : null,
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(width: 4),
      Text('$count', style: Theme.of(context).textTheme.labelMedium),
    ]);
  }
}

/// Uma marca sobre a carta: combate (ícone num círculo) ou dano (texto).
class _Badge extends StatelessWidget {
  const _Badge({required this.color, this.icon, this.text});

  final Color color;
  final IconData? icon;
  final String? text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(text == null ? 3 : 4),
      decoration: BoxDecoration(
        color: color,
        shape: text == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: text == null ? null : BorderRadius.circular(6),
      ),
      child: text == null
          ? Icon(icon, size: 14, color: Colors.white)
          : Text(text!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

/// A cor de um jogador: a do lugar dele na mesa (tu és o primeiro).
Color seatColor(ForgeTableState s, int playerId) {
  final i = s.players.indexWhere((p) => p.id == playerId);
  return GameColors.player(i < 0 ? 0 : i);
}

/// Uma linha do registo do Forge sem os ids internos ("Lightning Bolt (2)"). As
/// mudanças de vida vêm sempre em inglês ("Life: Bot 40 > 38"): essas são nossas.
String logLine(String t) {
  t = t.replaceAll(RegExp(r' \(\d+\)'), '');
  // o Forge regista a carta que resolveu como "Goblin Lackey - Criatura 1 / 1"
  final resolved = RegExp(r'^(.+?) - [^-\n]+ \d+ / \d+$').firstMatch(t.trim());
  if (resolved != null) return tr('{v} resolveu', {'v': resolved[1]!});
  t = forgeText(t);
  final life = RegExp(r'^Life: (.+) (\d+) > (\d+)$').firstMatch(t.trim());
  if (life == null) return t;
  return tr('{p}: vida {a} → {b}', {'p': life[1]!, 'a': life[2]!, 'b': life[3]!});
}

/// Arranjos às frases que o Forge monta sozinho, fora dos ficheiros de língua:
/// o possessivo inglês no português ("a carta de você's mão", "de Bot 1's
/// cemitério") e a descrição da carta a pagar ("Goblin Lackey - Criatura 1 / 1").
String forgeText(String t) {
  const article = {'mão': 'da', 'biblioteca': 'da', 'cemitério': 'do', 'grimório': 'do', 'exílio': 'do'};
  const mine = {'mão': 'da tua', 'biblioteca': 'do teu', 'cemitério': 'do teu', 'grimório': 'do teu', 'exílio': 'do teu'};
  t = t.replaceAllMapped(RegExp(r"\bde você's (\S+)"), (m) {
    final zone = m[1]!;
    return '${mine[zone] ?? 'da tua'} ${zone == 'biblioteca' ? 'grimório' : zone}';
  });
  t = t.replaceAllMapped(RegExp(r"\bde (.+?)'s (\S+)"), (m) => '${article[m[2]!] ?? 'de'} ${m[2]} de ${m[1]}');
  // a primeira linha do pagamento: só o nome da carta
  return t.replaceAllMapped(RegExp(r'^(.+?) - [^-\n]+ \d+ / \d+$', multiLine: true), (m) => m[1]!);
}

/// O que o jogo espera de mim e os dois botões. Na prioridade, as mensagens
/// são nossas ("A tua fase principal: joga uma carta ou passa") em vez das do
/// Forge ("Prioridade: Ana | Turno: 2 | Fase: ..."), e o OK diz o que faz.
class _PromptBar extends StatelessWidget {
  const _PromptBar(
      {required this.prompt,
      required this.waiting,
      required this.onButton,
      required this.state,
      required this.meId,
      this.lookup,
      this.onPlayer});

  /// Para achar a carta que se está a pagar pelo nome.
  final ForgeCardLookup? lookup;

  final ForgePrompt? prompt;
  final bool waiting;
  final void Function(String kind) onButton;
  final ForgeTableState state;
  final int meId;

  /// Escolher um jogador (como alvo): os mesmos botões que tocar na barra dele.
  final void Function(int id)? onPlayer;

  /// Quando o Forge pede um jogador, um botão por cada um, na cor do lugar: com
  /// vários adversários, tocar na barra ou no separador certo não é óbvio.
  Widget? _playerChoices(BuildContext context, ForgePrompt p) {
    if (onPlayer == null || p.selectablePlayers.isEmpty) return null;
    final theme = Theme.of(context);
    final chosen = p.chosen;
    // uma só linha que desliza: com 4 ou 5 jogadores no telemóvel, quebrar em
    // várias linhas esticava a barra e a mesa saía do ecrã
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          Text(tr('Escolhe um jogador:'), style: theme.textTheme.labelLarge),
          for (final pl in state.players)
            if (p.selectablePlayers.contains(pl.id))
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Semantics(
                  button: true,
                  label: tr('Escolher {v} como alvo', {'v': pl.name}),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, EdhSize.buttonCompact),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      side: BorderSide(color: GameColors.target, width: chosen.contains(pl.id) ? 3 : 1.5),
                      backgroundColor: chosen.contains(pl.id) ? GameColors.target.withOpacity(0.18) : null,
                    ),
                    onPressed: () => onPlayer!(pl.id),
                    icon: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: seatColor(state, pl.id), shape: BoxShape.circle),
                    ),
                    label: Text('${pl.id == meId ? tr('Tu') : pl.name} · ${pl.life}'),
                  ),
                ),
              ),
        ]),
      ),
    );
  }

  /// A pagar: a carta que se está a lançar ao lado do custo, como no Arena (já
  /// saiu da mão e ainda não está na pilha, e sem isto não se via em lado nenhum).
  static Widget _withCard(db.Card? card, Widget message, bool narrow) => card == null
      ? message
      : Row(children: [
          SizedBox(width: narrow ? 40 : 56, child: CardImage(card)),
          const SizedBox(width: 10),
          Expanded(child: message),
        ]);

  ({String message, String ok, String cancel}) _texts(ForgePrompt p) {
    // sem linhas em branco nem os ids internos do Forge ("Lightning Bolt (2)")
    final forge =
        forgeText(p.message.replaceAll(RegExp(r'\n\s*\n'), '\n').replaceAll(RegExp(r' \(\d+\)'), '').trim());
    // quando dá para desfazer, o Desfazer tem botão próprio (ver build) e este
    // continua a ser o Terminar o turno: o botão não muda de função debaixo do dedo
    String cancel() => switch (p.cancelKind) {
          'undo' || 'endTurn' => tr('Terminar o turno'),
          _ => p.cancel.label,
        };
    switch (p.input) {
      case 'priority':
        final mine = state.active == meId;
        final main = state.phase == 'MAIN1' || state.phase == 'MAIN2';
        if (state.stack.isNotEmpty) {
          final top = state.stack.first;
          final name = (top.name ?? top.text).replaceAll(RegExp(r' \(\d+\)'), '');
          final byMe = top.controller == meId;
          return (
            message: byMe
                ? tr('{v} está na pilha. Deixa resolver ou junta outra resposta.', {'v': name})
                : tr('{v} está na pilha. Respondes ou deixas resolver?', {'v': name}),
            ok: tr('Resolver'),
            cancel: cancel(),
          );
        }
        return (
          message: mine && main
              ? tr('A tua fase principal: joga uma carta ou passa.')
              : mine
                  ? tr('{v}: podes jogar instantâneos ou passar.', {'v': phaseLabel(state.phase)})
                  : tr('Turno do adversário ({v}): podes responder ou passar.', {'v': phaseLabel(state.phase)}),
          ok: tr('Passar'),
          cancel: cancel(),
        );
      case 'mulligan':
        return (message: tr('Ficas com esta mão?'), ok: p.ok.label, cancel: p.cancel.label);
      case 'bottom':
        final n = int.tryParse(RegExp(r'\d+').firstMatch(p.message)?.group(0) ?? '') ?? 1;
        return (
          // o Forge conta as que faltam: a 0, já está escolhido e só falta confirmar
          // (sem nenhuma escolhida e a 0: é o mulligan grátis do multijogador)
          message: n == 0
              ? p.chosen.isEmpty
                  ? tr('Este mulligan é grátis: não pões nenhuma carta no fundo. Toca em OK.')
                  : tr('Pronto. Toca em OK, ou na carta escolhida para mudar.')
              : n == 1
                  ? tr('Escolhe 1 carta da mão para pôr no fundo do grimório.')
                  : tr('Escolhe {n} cartas da mão para pôr no fundo do grimório.', {'n': n}),
          ok: p.ok.label,
          cancel: p.cancel.label,
        );
      // o OK do Forge não diz o que faz: como no Arena, "Não atacar" até haver
      // atacantes e depois "Atacar (n)"; o mesmo nos bloqueios
      case 'attack':
        final n = state.cards.where((c) => c.attacking && c.instance.controller == meId).length;
        return (
          message: tr('Escolhe quem ataca: toca nas tuas criaturas ou arrasta-as para o adversário.'),
          ok: n == 0 ? tr('Não atacar') : '${tr('Atacar')} ($n)',
          cancel: p.cancel.label,
        );
      case 'block':
        final n = state.cards.where((c) => c.blockingOf.isNotEmpty && c.instance.controller == meId).length;
        return (
          message: tr('Escolhe quem bloqueia: arrasta uma criatura tua para cima de um atacante.'),
          ok: n == 0 ? tr('Não bloquear') : '${tr('Bloquear')} ($n)',
          cancel: p.cancel.label,
        );
      default:
        return (message: forge, ok: p.ok.label, cancel: p.cancel.label);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = prompt;
    // "à espera do bot" (o Forge escreve "Waiting for ...", em inglês): é a vez dele
    final busy = waiting || p == null || p.input == 'wait';
    // a prioridade é minha mas o Forge passa sozinho: não há nada que eu possa jogar
    final passing = busy && !waiting && state.priority == meId;
    final narrow = MediaQuery.sizeOf(context).width < 560;
    final texts = busy ? null : _texts(p);
    final message = busy
        ? Row(children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Flexible(
                child: Text(
                    waiting
                        ? ''
                        : passing
                            ? tr('Nada para jogar agora · a passar…')
                            : tr('O bot está a pensar…'),
                    style: theme.textTheme.bodyMedium)),
          ])
        : _withCard(
            p.input == 'pay'
                ? state.card(p.cardId ?? -1)?.card ??
                    lookup?.byName(p.message.split('\n').first.replaceAll(RegExp(r' \(\d+\)| - .*'), '').trim())
                : null,
            OracleText(texts!.message, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            narrow);
    final priority = !busy && p.input == 'priority';
    // no telemóvel, com o Desfazer, os três não cabem a 360 dp com letra grande:
    // os botões dividem a linha e o texto encolhe em vez de sair do ecrã
    Widget fit(Widget b) => narrow ? Flexible(child: b) : b;
    Widget label(String t) => narrow ? FittedBox(fit: BoxFit.scaleDown, child: Text(t, maxLines: 1)) : Text(t);
    final pad = narrow ? const EdgeInsets.symmetric(horizontal: 14) : null;
    final buttons = [
      if (priority && p.cancelKind == 'undo')
        IconButton(
          tooltip: tr('Desfazer'),
          onPressed: () => onButton('undo'),
          icon: const Icon(Icons.undo),
        ),
      if (!busy && texts!.cancel.isNotEmpty) ...[
        const SizedBox(width: 6),
        fit(OutlinedButton(
          // o tema dá largura infinita aos botões; numa linha precisam de largura própria
          style: OutlinedButton.styleFrom(minimumSize: const Size(72, EdhSize.buttonCompact), padding: pad),
          onPressed: priority && p.cancelKind != null
              ? () => onButton('endTurn')
              : p.cancel.enabled
                  ? () => onButton('cancel')
                  : null,
          child: label(texts.cancel),
        )),
      ],
      if (!busy && texts!.ok.isNotEmpty) ...[
        const SizedBox(width: 6),
        fit(FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(72, EdhSize.buttonCompact), padding: pad),
          onPressed: p.ok.enabled ? () => onButton('ok') : null,
          child: label(texts.ok),
        )),
      ],
    ];
    // a faixa à esquerda na cor de quem tem de decidir: eu, ou o bot enquanto pensa
    final who = busy && !passing
        ? state.priority ?? state.players.firstWhere((p) => p.id != meId, orElse: () => state.players.first).id
        : meId;
    final choices = busy ? null : _playerChoices(context, p);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.95),
        border: Border(left: BorderSide(color: seatColor(state, who), width: 5)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              message,
              if (choices != null) choices,
              if (buttons.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons),
              ],
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [Expanded(child: message), ...buttons]),
              if (choices != null) choices,
            ]),
    );
  }
}

/// Nome, vida e contadores de um jogador, mais o comandante e as zonas públicas.
/// Tocar no nome ou na vida escolhe o jogador (como alvo, por exemplo).
class _PlayerBar extends StatelessWidget {
  const _PlayerBar(
      {required this.state, required this.player, required this.act, this.thinking = false, this.anchored = true});

  /// Se é a barra o destino das setas e voos para este jogador (com separadores, não é).
  final bool anchored;

  /// O bot está a decidir: reticências a pulsar ao lado do nome.
  final bool thinking;

  final ForgeTableState state;
  final ForgePlayer player;
  final _Interaction act;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = state.active == player.id;
    final pickable = act.playerSelectable(player.id);
    final chosen = act.chosen(player.id);
    final command = state.zone(player.id, Zone.command).toList();
    final graveyard = state.zone(player.id, Zone.graveyard).toList();
    final exile = state.zone(player.id, Zone.exile).toList();
    final narrow = MediaQuery.sizeOf(context).width < 560;
    Widget chip(IconData icon, String text, {VoidCallback? onTap, String? anchor}) => KeyedSubtree(
        key: anchor == null ? null : act.geo.key(anchor),
        child: narrow
            ? InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 14, color: onTap == null ? null : theme.colorScheme.primary),
                    const SizedBox(width: 2),
                    Text(text, style: theme.textTheme.labelMedium),
                  ]),
                ),
              )
            : Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(icon, size: 16),
                  label: Text(text),
                  onPressed: onTap,
                ),
              ));
    // cada jogador tem a sua cor: uma faixa à esquerda e, no turno dele, o fundo nesse tom
    final color = seatColor(state, player.id);
    final surface = theme.colorScheme.surface;
    final bar = Container(
      // com separadores, o destino das setas é o separador (ver _OpponentTabs)
      key: anchored ? act.geo.key('player:${player.id}') : null,
      decoration: BoxDecoration(
        // fundo próprio: por cima do fundo da mesa, o nome e a vida têm de se ler
        color: active ? Color.alphaBlend(color.withOpacity(0.22), surface) : surface.withOpacity(0.92),
        border: pickable || chosen
            ? Border.all(color: chosen ? targetGlow : GameColors.target, width: 3)
            : act.gazedPlayer(player.id)
                ? Border.all(color: act.thinkColor!, width: 3)
                : Border(left: BorderSide(color: color, width: 5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        Expanded(
          child: InkWell(
            onTap: act.onPlayer == null ? null : () => act.onPlayer!(player.id),
            child: Row(children: [
              Expanded(
                child: Row(children: [
                  // no telemóvel o nome encolhe em vez de ser cortado ("Bot (Nor…")
                  Flexible(
                    child: FitText(
                      player.lost ? '${player.name} · ${tr('perdeu')}' : player.name,
                      alignment: Alignment.centerLeft,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (thinking) const Padding(padding: EdgeInsets.only(left: 6), child: ThinkingDots()),
                  if (pickable)
                    const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.gps_fixed, size: 18, color: GameColors.attack)),
                  if (act.gazedPlayer(player.id))
                    Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(Icons.visibility, size: 18, color: act.thinkColor)),
                ]),
              ),
              AnimatedLife(
                  life: player.life,
                  style: (narrow ? theme.textTheme.titleLarge : theme.textTheme.headlineSmall)
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
        if (player.poison > 0) chip(Icons.coronavirus_outlined, '${player.poison}'),
        // dano de comandante que este jogador já levou, por comandante, na cor de
        // quem o controla; a vermelho perto dos 21, que matam
        for (final e in player.commanderDamage.entries)
          Tooltip(
            message: tr('Dano de comandante: {n} de 21', {'n': e.value}),
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.military_tech,
                    size: 18,
                    color: state.card(e.key) == null ? null : seatColor(state, state.card(e.key)!.instance.controller)),
                Text('${e.value}',
                    style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700, color: e.value >= 15 ? GameColors.attack : null)),
              ]),
            ),
          ),
        for (final c in command)
          Padding(padding: const EdgeInsets.only(left: 6), child: act.card(c, narrow ? 32 : 44, details: false)),
        if (player.id == act.meId)
          chip(Icons.back_hand_outlined, '${player.handCount}', anchor: 'hand:${player.id}')
        else
          KeyedSubtree(
            key: act.geo.key('hand:${player.id}'),
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _HandBacks(count: player.handCount, color: color, small: narrow, lifted: _lifted()),
            ),
          ),
        chip(Icons.layers_outlined, '${player.libraryCount}', anchor: 'lib:${player.id}'),
        chip(Icons.delete_outline, '${graveyard.length}',
            anchor: 'grave:${player.id}',
            onTap: graveyard.isEmpty ? null : () => _zoneSheet(context, tr('Cemitério'), graveyard)),
        if (exile.isNotEmpty)
          chip(Icons.block, '${exile.length}',
              anchor: 'exile:${player.id}', onTap: () => _zoneSheet(context, tr('Exílio'), exile)),
      ]),
    );
    if (!act.attacking || act.onAttack == null || player.id == act.meId) return bar;
    return DragTarget<int>(
      onAcceptWithDetails: (d) => act.onAttack!(d.data, player.id),
      builder: (context, candidates, _) => Container(
        foregroundDecoration:
            candidates.isEmpty ? null : BoxDecoration(border: Border.all(color: GameColors.attack, width: 3)),
        child: bar,
      ),
    );
  }

  /// O verso que sobe quando o bot pensa lançar uma carta da mão (qual é fica
  /// escondido: escolhe-se um dos versos pelo id, sempre o mesmo para a mesma carta).
  int? _lifted() {
    final t = act.think;
    if (t == null || t.kind != 'cast' || t.by != player.id || t.cards.isEmpty || player.handCount == 0) return null;
    final host = t.cards.first;
    final onTable = state.card(host);
    if (onTable != null && onTable.instance.zone != Zone.hand) return null;
    return host % min(player.handCount, _HandBacks.maxShown);
  }

  void _zoneSheet(BuildContext context, String title, List<ForgeCardView> cards) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              // o topo (o mais recente) primeiro; aqui tocar abre a ficha
              itemBuilder: (_, i) {
                final c = cards[cards.length - 1 - i];
                return GestureDetector(
                  onTap: () => act.onDetails(c),
                  child: TableCardView(instance: c.instance, card: c.card, width: 105, showDetails: false),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// O campo de um jogador: os terrenos numa fila, o resto noutra. O do
/// adversário fica ao contrário (terrenos ao fundo, longe do centro).
class _Battlefield extends StatelessWidget {
  const _Battlefield({required this.state, required this.player, required this.act, this.flipped = false});

  final ForgeTableState state;
  final int player;
  final bool flipped;
  final _Interaction act;

  @override
  Widget build(BuildContext context) {
    final all = state.zone(player, Zone.battlefield).toList();
    // auras e equipamentos ficam ao lado da carta a que estão presos
    final attached = <int, List<ForgeCardView>>{};
    for (final c in all) {
      final host = c.instance.attachedTo;
      if (host != null) attached.putIfAbsent(host, () => []).add(c);
    }
    bool isLand(ForgeCardView c) => c.card?.isLand ?? false;
    List<ForgeCardView> withAttachments(Iterable<ForgeCardView> cards) => [
          for (final c in cards.where((c) => c.instance.attachedTo == null)) ...[c, ...?attached[c.instance.id]],
        ];
    final lands = withAttachments(all.where(isLand));
    final others = withAttachments(all.where((c) => !isLand(c)));
    // terrenos iguais numa pilha "×N": em Commander são 8 a 10 e enchiam meia mesa.
    // Iguais = a mesma carta, no mesmo estado e com a mesma marca de escolha, sem
    // contadores nem nada preso; tocar na pilha usa o primeiro (pagar mana é igual)
    final stacked = <ForgeCardView>[];
    final counts = <int, int>{};
    final byKey = <String, ForgeCardView>{};
    for (final c in lands) {
      final i = c.instance;
      final plain = i.counters.isEmpty && i.attachedTo == null && !attached.containsKey(i.id);
      final key = '${i.oracleId}|${i.tapped}|${act.selectable(i.id)}|${act.chosen(i.id)}';
      final first = plain ? byKey[key] : null;
      if (first != null) {
        counts[first.instance.id] = (counts[first.instance.id] ?? 1) + 1;
        continue;
      }
      if (plain) byKey[key] = c;
      stacked.add(c);
    }
    final rows = [
      _CardRow(cards: others, act: act, flex: 3),
      _CardRow(cards: stacked, act: act, flex: 2, counts: counts),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: LayoutBuilder(builder: (context, box) {
        // mesa larga e baixa (tablet deitado): os terrenos ao lado das outras
        // cartas, e cada fila fica com a altura toda; em duas filas as cartas
        // ficavam com 60 px e meia mesa vazia
        final side = box.maxWidth > box.maxHeight * 3;
        if (!side) return Column(children: flipped ? rows.reversed.toList() : rows);
        final row = [
          rows[0],
          VerticalDivider(width: 12, thickness: 1, color: Colors.white.withOpacity(0.15)),
          rows[1],
        ];
        return Row(children: flipped ? row.reversed.toList() : row);
      }),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.cards, required this.act, required this.flex, this.counts = const {}});

  final List<ForgeCardView> cards;
  final _Interaction act;
  final int flex;

  /// Quantas cartas iguais cada uma representa (terrenos empilhados).
  final Map<int, int> counts;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: LayoutBuilder(builder: (context, box) {
        // as cartas viradas ocupam a altura na horizontal: a largura sai da altura da fila
        // no tablet há espaço para cartas que se leem; no telemóvel a altura manda
        final w = (box.maxHeight * cardAspect * 0.92).clamp(24.0, 150.0);
        // centradas, como numa mesa; com muitas, a fila desliza
        return Center(
            child: ListView.separated(
          shrinkWrap: true,
          scrollDirection: Axis.horizontal,
          // quem ataca sai um pouco da fila
          clipBehavior: Clip.none,
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(width: 4),
          itemBuilder: (_, i) {
            final c = cards[i];
            final n = counts[c.instance.id] ?? 1;
            final card = act.card(c, w);
            return SizedBox(
              width: (c.instance.tapped && !c.attacking ? w / cardAspect : w) + (n > 1 ? 6 : 0),
              child: Center(
                child: n == 1
                    ? card
                    : Stack(clipBehavior: Clip.none, children: [
                        // o rebordo de outra carta por trás, um pouco desviado: lê-se como uma
                        // pilha (não é outra carta: cada carta tem a sua chave para as animações)
                        Positioned(
                          left: 5,
                          top: -4,
                          right: -5,
                          bottom: 4,
                          // virada como a carta (que roda por cima do seu espaço de pé)
                          child: Transform.rotate(
                            angle: c.instance.tapped && !c.attacking ? pi / 2 : 0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF26345F),
                                borderRadius: BorderRadius.circular(w * cardCorner),
                                border: Border.all(color: Colors.white.withOpacity(0.45)),
                              ),
                            ),
                          ),
                        ),
                        card,
                        Positioned(
                          right: -6,
                          bottom: -4,
                          child: _Badge(text: '×$n', color: Colors.black.withOpacity(0.78)),
                        ),
                      ]),
              ),
            );
          },
        ));
      }),
    );
  }
}

/// A pilha (o que está à espera de resolver) como mini-cartas, a de cima
/// primeiro e com o que faz; sem pilha, o último acontecimento.
class _CenterStrip extends StatelessWidget {
  const _CenterStrip({required this.state, required this.act, required this.lookup});

  final ForgeTableState state;
  final _Interaction act;
  final ForgeCardLookup lookup;

  static String _clean(String t) => logLine(t);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = state.log.isEmpty ? '' : state.log.first;
    final onTable = {for (final c in state.cards) c.instance.id};
    final stack = state.stack;
    // no telemóvel, a pilha mais baixa: com cartas grandes e 3 linhas, as duas
    // mesas ficavam com cartas de 30 px sempre que havia algo na pilha
    final narrow = MediaQuery.sizeOf(context).width < 560;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.92),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: stack.isEmpty
          ? OracleText(_clean(last), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)
          : Row(children: [
              for (var i = 0; i < stack.length && i < 5; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: act.onStack == null || stack[i].id == null ? null : () => act.onStack!(stack[i].id!),
                    child: KeyedSubtree(
                      // a carta lançada voa da mão para aqui: tem a chave da própria carta se
                      // não estiver noutro sítio da mesa (as habilidades ficam com a da pilha)
                      key: stack[i].sourceId != null && !onTable.contains(stack[i].sourceId)
                          ? act.geo.key('c${stack[i].sourceId}')
                          : act.geo.key('s${stack[i].id}'),
                      child: _StackCard(
                        card: stack[i].name == null ? null : lookup.byName(stack[i].name!),
                        width: i == 0 ? (narrow ? 36 : 52) : (narrow ? 26 : 36),
                        chosen: stack[i].id != null && act.chosen(stack[i].id!),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: OracleText(
                  _clean(stack.first.text),
                  maxLines: narrow ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ]),
    );
  }
}

class _StackCard extends StatelessWidget {
  const _StackCard({required this.card, required this.width, required this.chosen});

  final db.Card? card;
  final double width;
  final bool chosen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * cardCorner),
        boxShadow: [
          BoxShadow(
            color: (chosen ? targetGlow : Theme.of(context).colorScheme.primary).withOpacity(0.7),
            blurRadius: 8,
          ),
        ],
      ),
      child: card == null ? const AspectRatio(aspectRatio: cardAspect, child: CardBack()) : CardImage(card!),
    );
  }
}

class _Hand extends StatelessWidget {
  const _Hand({required this.cards, required this.act, this.big = false, this.mulligan = false});

  final List<ForgeCardView> cards;
  final _Interaction act;

  /// A jogar, a mão é maior (é daqui que saem as jogadas).
  final bool big;

  /// A decidir o mulligan: a mão em grande, para se ver bem.
  final bool mulligan;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 560;
    final w = mulligan
        ? min(size.width / (narrow ? 3.6 : 7.5), size.height * 0.2 * cardAspect).clamp(70.0, 150.0)
        : big && !narrow
            ? 84.0
            : 66.0;
    final h = w / cardAspect;
    return SizedBox(
      height: h + (narrow ? 22 : 10),
      child: LayoutBuilder(builder: (context, box) {
        final n = cards.length;
        if (n == 0) return const SizedBox.shrink();
        // Cabem lado a lado? Senão as cartas sobrepõem-se num leque (como no
        // Arena), sem scroll: vê-se a mão toda, e a carta tocada fica por cima.
        final avail = box.maxWidth - 16;
        final step = n == 1 ? 0.0 : min(w + 4, (avail - w) / (n - 1));
        final fan = narrow && step < w + 4;
        final total = step * (n - 1) + w;
        final left0 = (box.maxWidth - total) / 2;
        return Stack(clipBehavior: Clip.none, children: [
          for (var i = 0; i < n; i++)
            Builder(builder: (context) {
              // no leque, as das pontas descem e rodam um pouco
              final t = n == 1 ? 0.0 : (i / (n - 1)) * 2 - 1;
              final angle = fan ? t * 0.12 : 0.0;
              final drop = fan ? t * t * 12 : 0.0;
              return Positioned(
                left: left0 + i * step,
                top: 4 + drop,
                width: w,
                child: Transform.rotate(
                  angle: angle,
                  alignment: Alignment.bottomCenter,
                  child: act.card(cards[i], w, details: false),
                ),
              );
            }),
        ]);
      }),
    );
  }
}

/// O nome de uma fase do Forge (PhaseType) na língua da app.
String phaseLabel(String? phase) => switch (phase) {
      'UNTAP' => tr('Desvirar'),
      'UPKEEP' => tr('Manutenção'),
      'DRAW' => tr('Comprar'),
      'MAIN1' => tr('Fase principal 1'),
      'COMBAT_BEGIN' => tr('Início do combate'),
      'COMBAT_DECLARE_ATTACKERS' => tr('Declarar atacantes'),
      'COMBAT_DECLARE_BLOCKERS' => tr('Declarar bloqueadores'),
      'COMBAT_FIRST_STRIKE_DAMAGE' => tr('Dano de iniciativa'),
      'COMBAT_DAMAGE' => tr('Dano de combate'),
      'COMBAT_END' => tr('Fim do combate'),
      'MAIN2' => tr('Fase principal 2'),
      'END_OF_TURN' => tr('Fim do turno'),
      'CLEANUP' => tr('Limpeza'),
      _ => '',
    };
