import 'dart:async';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart' hide Table;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesa_core/mesa_core.dart';

import '../../bot/forge_engine.dart';
import '../../bot/forge_table.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../cards/card_detail_screen.dart';
import '../table/table_card.dart';
import '../widgets/card_view.dart';
import 'bot_dialogs.dart';

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

class _BotTableScreenState extends ConsumerState<BotTableScreen> {
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

  @override
  void initState() {
    super.initState();
    // As imagens dos dois decks, para não aparecerem cartas de texto a meio.
    final ids = {for (final s in widget.seats) ...s.deck.entries.map((e) => e.oracleId)};
    _requested.addAll(ids);
    ref.read(imagesProvider).ensure(_repo.getMany(ids).values);
    _sub = ForgeEngine.events.listen(_onEvent);
    ForgeEngine.start(seats: widget.seats, repo: _repo, commander: widget.commander).catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    ForgeEngine.stop();
    super.dispose();
  }

  void _onEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    switch (e['type']) {
      case 'error':
        setState(() => _error = e['error'] as String?);
        return;
      case 'ask':
        _ask(ForgeAsk.fromMap(e));
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
    setState(() {
      if (s.players.isNotEmpty) _state = s;
      if (e['type'] == 'prompt') {
        _prompt = ForgePrompt.fromMap(e);
        _waiting = false;
      }
      if (s.over) _prompt = null;
    });
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
    final title = s == null
        ? (_live ? tr('Contra o bot') : tr('Bot contra bot'))
        : tr('Turno {v}', {'v': s.turn});
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
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
                : _table(s),
      ),
    );
  }

  Widget _table(ForgeTableState s) {
    if (s.players.length < 2) return const SizedBox.shrink();
    final me = s.players[0];
    final them = s.players[1];
    final act = _Interaction(
      prompt: _live && !_waiting ? _prompt : null,
      onCard: _tapCard,
      onDetails: _openCard,
      onPlayer: _live ? (id) => _act('player', id) : null,
      onStack: _live ? (id) => _act('stack', id) : null,
    );
    return SafeArea(
      child: Column(children: [
        _PlayerBar(state: s, player: them, act: act),
        Expanded(child: _Battlefield(state: s, player: them.id, flipped: true, act: act)),
        _CenterStrip(state: s, act: act),
        if (_live && !s.over) _PromptBar(prompt: _prompt, waiting: _waiting, onButton: _act),
        Expanded(child: _Battlefield(state: s, player: me.id, act: act)),
        _PlayerBar(state: s, player: me, act: act),
        _Hand(cards: s.zone(me.id, Zone.hand).toList(), act: act, big: _live),
        if (s.over) _OverBanner(state: s),
      ]),
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
  });

  /// null quando não há nada à espera da pessoa (ou a ver bot contra bot).
  final ForgePrompt? prompt;
  final void Function(ForgeCardView) onCard;
  final void Function(ForgeCardView) onDetails;
  final void Function(int id)? onPlayer;
  final void Function(int id)? onStack;

  bool selectable(int cardId) => prompt?.selectableCards.contains(cardId) ?? false;
  bool chosen(int id) => prompt?.chosen.contains(id) ?? false;
  bool playerSelectable(int id) => prompt?.selectablePlayers.contains(id) ?? false;

  /// Uma carta da mesa com os toques: tocar joga (ou abre a ficha, a ver), tocar sem largar abre a ficha.
  Widget card(ForgeCardView c, double width, {bool details = true}) {
    return GestureDetector(
      onTap: () => onCard(c),
      onLongPress: () => onDetails(c),
      child: Opacity(
        opacity: c.sick ? 0.75 : 1,
        child: TableCardView(
          instance: c.instance,
          card: c.card,
          width: width,
          showDetails: details,
          highlighted: c.attacking || selectable(c.instance.id),
          targeted: chosen(c.instance.id),
        ),
      ),
    );
  }
}

/// A mensagem do Forge e os dois botões (passar, confirmar, cancelar...).
class _PromptBar extends StatelessWidget {
  const _PromptBar({required this.prompt, required this.waiting, required this.onButton});

  final ForgePrompt? prompt;
  final bool waiting;
  final void Function(String kind) onButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = prompt;
    final busy = waiting || p == null;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(children: [
        Expanded(
          child: busy
              ? Row(children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text(tr('O bot está a pensar…'), style: theme.textTheme.bodyMedium),
                ])
              : Text(p.message, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
        ),
        if (!busy && p.cancel.label.isNotEmpty) ...[
          const SizedBox(width: 6),
          OutlinedButton(
            // o tema dá largura infinita aos botões; numa linha precisam de largura própria
            style: OutlinedButton.styleFrom(minimumSize: const Size(80, 40)),
            onPressed: p.cancel.enabled ? () => onButton('cancel') : null,
            child: Text(p.cancel.label),
          ),
        ],
        if (!busy && p.ok.label.isNotEmpty) ...[
          const SizedBox(width: 6),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
            onPressed: p.ok.enabled ? () => onButton('ok') : null,
            child: Text(p.ok.label),
          ),
        ],
      ]),
    );
  }
}

/// Nome, vida e contadores de um jogador, mais o comandante e as zonas públicas.
/// Tocar no nome ou na vida escolhe o jogador (como alvo, por exemplo).
class _PlayerBar extends StatelessWidget {
  const _PlayerBar({required this.state, required this.player, required this.act});

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
    Widget chip(IconData icon, String text, {VoidCallback? onTap}) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: ActionChip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(icon, size: 16),
            label: Text(text),
            onPressed: onTap,
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: active ? theme.colorScheme.primaryContainer.withOpacity(0.5) : null,
        border: pickable || chosen
            ? Border.all(color: chosen ? targetGlow : theme.colorScheme.primary, width: 2)
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        Expanded(
          child: InkWell(
            onTap: act.onPlayer == null ? null : () => act.onPlayer!(player.id),
            child: Row(children: [
              Expanded(
                child: Text(
                  player.lost ? '${player.name} · ${tr('perdeu')}' : player.name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text('${player.life}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        if (player.poison > 0) chip(Icons.coronavirus_outlined, '${player.poison}'),
        for (final c in command) Padding(padding: const EdgeInsets.only(left: 6), child: act.card(c, 28, details: false)),
        chip(Icons.back_hand_outlined, '${player.handCount}'),
        chip(Icons.layers_outlined, '${player.libraryCount}'),
        chip(Icons.delete_outline, '${graveyard.length}',
            onTap: graveyard.isEmpty ? null : () => _zoneSheet(context, tr('Cemitério'), graveyard)),
        if (exile.isNotEmpty) chip(Icons.block, '${exile.length}', onTap: () => _zoneSheet(context, tr('Exílio'), exile)),
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

/// Fase, turno e a pilha (o que está à espera de resolver).
class _CenterStrip extends StatelessWidget {
  const _CenterStrip({required this.state, required this.act});

  final ForgeTableState state;
  final _Interaction act;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = state.player(state.active ?? -1);
    final last = state.log.isEmpty ? '' : state.log.first;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(
          '${active?.name ?? ''} · ${phaseLabel(state.phase)}',
          style: theme.textTheme.labelLarge,
          overflow: TextOverflow.ellipsis,
        ),
        for (final item in state.stack.reversed)
          InkWell(
            onTap: act.onStack == null || item.id == null ? null : () => act.onStack!(item.id!),
            child: Text(
              '↳ ${item.text}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: item.id != null && act.chosen(item.id!) ? targetGlow : null,
              ),
            ),
          ),
        if (state.stack.isEmpty && last.isNotEmpty)
          Text(last, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
      ]),
    );
  }
}

class _Hand extends StatelessWidget {
  const _Hand({required this.cards, required this.act, this.big = false});

  final List<ForgeCardView> cards;
  final _Interaction act;

  /// A jogar, a mão é maior (é daqui que saem as jogadas).
  final bool big;

  @override
  Widget build(BuildContext context) {
    final w = big ? 84.0 : 62.0;
    return SizedBox(
      height: w / cardAspect + 8,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) => act.card(cards[i], w, details: false),
      ),
    );
  }
}

class _OverBanner extends StatelessWidget {
  const _OverBanner({required this.state});

  final ForgeTableState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winner = state.player(state.winner ?? -1);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.primary,
      padding: const EdgeInsets.all(12),
      child: Text(
        winner == null ? tr('Empate') : tr('{v} ganhou', {'v': winner.name}),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onPrimary),
      ),
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
