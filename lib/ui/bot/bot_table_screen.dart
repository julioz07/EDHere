import 'dart:async';
import 'dart:math';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart' hide Table;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesa_core/mesa_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../bot/forge_engine.dart';
import '../../bot/forge_table.dart';
import '../../data/providers.dart';
import '../../data/settings.dart';
import '../../l10n/l10n.dart';
import '../cards/card_detail_screen.dart';
import '../table/table_card.dart';
import '../widgets/card_view.dart';
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
  ({String text, bool mine})? _banner;
  Timer? _bannerTimer;
  int _lastTurn = 0;

  /// A vida de cada jogador no início de cada turno (para o gráfico do fim).
  final _lifeHistory = <int, List<int>>{};
  bool _overShown = false;

  late BotSpeed _speed = BotSpeed.byId(ref.read(prefsProvider).getString(BotSpeed.prefKey));

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
    ForgeEngine.start(seats: widget.seats, repo: _repo, commander: widget.commander, paceMs: _speed.paceMs)
        .catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  void dispose() {
    _spotTimer?.cancel();
    _bannerTimer?.cancel();
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
        _spotTimer?.cancel();
        _spotTimer = Timer(spot.duration, () {
          if (mounted) setState(() => _spot = null);
        });
        setState(() => _spot = spot);
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
    }
    final old = _state;
    final specs = old == null || s.players.isEmpty ? const <FlightSpec>[] : _changes(old, s);
    setState(() {
      if (s.players.isNotEmpty) _state = s;
      if (e['type'] == 'prompt') {
        _prompt = ForgePrompt.fromMap(e);
        _waiting = false;
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
    var played = false, died = false;
    for (final id in ids) {
      final a = _where(old, id), b = _where(now, id);
      // sem sítio conhecido (a meio de um lançamento, na biblioteca...): não voa
      if (a == b || b == null) continue;
      final c = now.card(id) ?? old.card(id);
      if (a != null && a.startsWith('hand:$meId') && (b == 'stack' || b.startsWith('battlefield'))) {
        played = true;
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
    // dano: abanar a mesa (mais quando sou eu a sofrer) e vibrar
    for (final p in now.players) {
      final before = old.player(p.id);
      if (before == null || p.life >= before.life) continue;
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
    if (now.over && !old.over) _haptic(HapticFeedback.heavyImpact);
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
          content: Text(tr('O bot ganha esta partida.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Continuar a jogar'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Desistir'))),
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
    final title = s == null ? (_live ? tr('Contra o bot') : tr('Bot contra bot')) : tr('Turno {v}', {'v': s.turn});
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
                            painter:
                                CombatArrowsPainter(geo: _geo, origin: _areaKey, arrows: s.over ? const [] : _arrows(s), pulse: _pulse),
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
                                          const Color(0xFFE53935).withOpacity(0.45 * (1 - _shake.value)),
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
    }
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
    final them = s.players[1];
    final act = _Interaction(
      prompt: _live && !_waiting ? _prompt : null,
      onCard: _tapCard,
      onDetails: _peekCard,
      onPlayer: _live ? (id) => _act('player', id) : null,
      onStack: _live ? (id) => _act('stack', id) : null,
      geo: _geo,
      hidden: _hidden,
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
          _PlayerBar(
              state: s, player: them, act: act, thinking: _live && !s.over && (_waiting || _prompt?.input == 'wait')),
          Expanded(child: _Battlefield(state: s, player: them.id, flipped: true, act: act)),
          PhaseBar(phase: s.phase, mine: _live && s.active == me.id, compact: narrow),
          if (!narrow || s.stack.isNotEmpty || !_live) _CenterStrip(state: s, act: act, lookup: _lookup),
          if (_live && !s.over) _PromptBar(prompt: _prompt, waiting: _waiting, onButton: _act, state: s, meId: me.id),
          Expanded(child: _Battlefield(state: s, player: me.id, act: act)),
          _PlayerBar(state: s, player: me, act: act),
          _Hand(
            cards: s.zone(me.id, Zone.hand).toList(),
            act: act,
            big: _live,
            mulligan: _live && !_waiting && _prompt?.input == 'mulligan',
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
        children: [for (final l in s.log) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(l))],
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
  });

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
    return GestureDetector(
      key: geo.key('c${c.instance.id}'),
      onTap: () => onCard(c),
      onLongPress: () => onDetails(c),
      child: Opacity(
        opacity: hidden.contains(c.instance.id) ? 0 : (c.sick ? 0.75 : 1),
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            // em combate: vermelho a atacar, azul a bloquear (como no Arena)
            decoration: autoTap(c.instance.id)
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(width * 0.06),
                    boxShadow: const [BoxShadow(color: Color(0xFFFFC107), blurRadius: 12, spreadRadius: 3)],
                  )
                : c.attacking || c.blocking
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(width * 0.06),
                        boxShadow: [
                          BoxShadow(
                            color: (c.attacking ? const Color(0xFFE53935) : const Color(0xFF1E88E5)).withOpacity(0.9),
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
                color: c.attacking ? const Color(0xFFE53935) : const Color(0xFF1E88E5),
              ),
            ),
          if (c.damage > 0)
            Positioned(
              bottom: -4,
              right: -4,
              child: _Badge(text: '-${c.damage}', color: const Color(0xFFB71C1C)),
            ),
        ]),
      ),
    );
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

/// O que o jogo espera de mim e os dois botões. Na prioridade, as mensagens
/// são nossas ("A tua fase principal: joga uma carta ou passa") em vez das do
/// Forge ("Prioridade: Ana | Turno: 2 | Fase: ..."), e o OK diz o que faz.
class _PromptBar extends StatelessWidget {
  const _PromptBar(
      {required this.prompt, required this.waiting, required this.onButton, required this.state, required this.meId});

  final ForgePrompt? prompt;
  final bool waiting;
  final void Function(String kind) onButton;
  final ForgeTableState state;
  final int meId;

  ({String message, String ok, String cancel}) _texts(ForgePrompt p) {
    // sem linhas em branco nem os ids internos do Forge ("Lightning Bolt (2)")
    final forge = p.message.replaceAll(RegExp(r'\n\s*\n'), '\n').replaceAll(RegExp(r' \(\d+\)'), '').trim();
    String cancel() => switch (p.cancelKind) {
          'undo' => tr('Desfazer'),
          'endTurn' => tr('Terminar o turno'),
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
    final narrow = MediaQuery.sizeOf(context).width < 560;
    final texts = busy ? null : _texts(p);
    final message = busy
        ? Row(children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Flexible(child: Text(tr('O bot está a pensar…'), style: theme.textTheme.bodyMedium)),
          ])
        : Text(texts!.message, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium);
    final buttons = [
      if (!busy && texts!.cancel.isNotEmpty) ...[
        const SizedBox(width: 6),
        OutlinedButton(
          // o tema dá largura infinita aos botões; numa linha precisam de largura própria
          style: OutlinedButton.styleFrom(minimumSize: const Size(72, 40)),
          onPressed: p.cancel.enabled ? () => onButton('cancel') : null,
          child: Text(texts.cancel),
        ),
      ],
      if (!busy && texts!.ok.isNotEmpty) ...[
        const SizedBox(width: 6),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
          onPressed: p.ok.enabled ? () => onButton('ok') : null,
          child: Text(texts.ok),
        ),
      ],
    ];
    return Container(
      width: double.infinity,
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              message,
              if (buttons.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons),
              ],
            ])
          : Row(children: [Expanded(child: message), ...buttons]),
    );
  }
}

/// Nome, vida e contadores de um jogador, mais o comandante e as zonas públicas.
/// Tocar no nome ou na vida escolhe o jogador (como alvo, por exemplo).
class _PlayerBar extends StatelessWidget {
  const _PlayerBar({required this.state, required this.player, required this.act, this.thinking = false});

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
    return Container(
      key: act.geo.key('player:${player.id}'),
      decoration: BoxDecoration(
        // fundo próprio: por cima do fundo da mesa, o nome e a vida têm de se ler
        color: active ? theme.colorScheme.primaryContainer : theme.colorScheme.surface.withOpacity(0.9),
        border:
            pickable || chosen ? Border.all(color: chosen ? targetGlow : theme.colorScheme.primary, width: 2) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        Expanded(
          child: InkWell(
            onTap: act.onPlayer == null ? null : () => act.onPlayer!(player.id),
            child: Row(children: [
              Expanded(
                child: Row(children: [
                  Flexible(
                    child: Text(
                      player.lost ? '${player.name} · ${tr('perdeu')}' : player.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (thinking) const Padding(padding: EdgeInsets.only(left: 6), child: ThinkingDots()),
                ]),
              ),
              AnimatedLife(life: player.life, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        if (player.poison > 0) chip(Icons.coronavirus_outlined, '${player.poison}'),
        for (final c in command)
          Padding(padding: const EdgeInsets.only(left: 6), child: act.card(c, 28, details: false)),
        chip(Icons.back_hand_outlined, '${player.handCount}', anchor: 'hand:${player.id}'),
        chip(Icons.layers_outlined, '${player.libraryCount}', anchor: 'lib:${player.id}'),
        chip(Icons.delete_outline, '${graveyard.length}',
            anchor: 'grave:${player.id}',
            onTap: graveyard.isEmpty ? null : () => _zoneSheet(context, tr('Cemitério'), graveyard)),
        if (exile.isNotEmpty)
          chip(Icons.block, '${exile.length}',
              anchor: 'exile:${player.id}', onTap: () => _zoneSheet(context, tr('Exílio'), exile)),
      ]),
    );
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
    final rows = [
      _CardRow(cards: others, act: act, flex: 3),
      _CardRow(cards: lands, act: act, flex: 2),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(children: flipped ? rows.reversed.toList() : rows),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.cards, required this.act, required this.flex});

  final List<ForgeCardView> cards;
  final _Interaction act;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: LayoutBuilder(builder: (context, box) {
        // as cartas viradas ocupam a altura na horizontal: a largura sai da altura da fila
        final w = (box.maxHeight * cardAspect * 0.92).clamp(24.0, 110.0);
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(width: 4),
          itemBuilder: (_, i) {
            final c = cards[i];
            return SizedBox(
              width: c.instance.tapped ? w / cardAspect : w,
              child: Center(child: act.card(c, w)),
            );
          },
        );
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

  static String _clean(String t) => t.replaceAll(RegExp(r' \(\d+\)'), '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = state.log.isEmpty ? '' : state.log.first;
    final onTable = {for (final c in state.cards) c.instance.id};
    final stack = state.stack;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.92),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: stack.isEmpty
          ? Text(_clean(last), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)
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
                        width: i == 0 ? 52 : 36,
                        chosen: stack[i].id != null && act.chosen(stack[i].id!),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  _clean(stack.first.text),
                  maxLines: 3,
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
        borderRadius: BorderRadius.circular(width * 0.06),
        boxShadow: [
          BoxShadow(
            color: (chosen ? targetGlow : Theme.of(context).colorScheme.primary).withOpacity(0.7),
            blurRadius: 8,
          ),
        ],
      ),
      child: card == null
          ? const AspectRatio(aspectRatio: cardAspect, child: CardBack())
          : CardImage(card!, radius: width * 0.06),
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
