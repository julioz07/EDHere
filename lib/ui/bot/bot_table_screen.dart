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

/// A mesa de uma partida no motor do Forge. Por agora só se vê (bot contra
/// bot): as regras e as jogadas são todas do Forge, a mesa desenha o estado.
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
  StreamSubscription<Map<String, dynamic>>? _sub;
  ForgeTableState? _state;
  String? _error;

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
    if (e['type'] == 'error') {
      setState(() => _error = e['error'] as String?);
      return;
    }
    final s = ForgeTableState.fromMap(e, _lookup);
    // tokens e cartas que só aparecem a meio (copiadas, roubadas...)
    final fresh = [
      for (final c in s.cards)
        if (c.card != null && _requested.add(c.card!.oracleId)) c.card!,
    ];
    if (fresh.isNotEmpty) ref.read(imagesProvider).ensure(fresh);
    setState(() => _state = s);
  }

  /// Cartas cujas imagens já foram pedidas.
  final _requested = <String>{};

  void _openCard(ForgeCardView c) {
    final card = c.card;
    if (card == null || c.instance.faceDown) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CardDetailScreen(card: card)));
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    return Scaffold(
      appBar: AppBar(
        title: Text(s == null ? tr('Bot contra bot') : tr('Turno {v}', {'v': s.turn})),
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
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(tr('A baralhar…')),
                ]))
              : _table(s),
    );
  }

  Widget _table(ForgeTableState s) {
    if (s.players.length < 2) return const SizedBox.shrink();
    final me = s.players[0];
    final them = s.players[1];
    return SafeArea(
      child: Column(children: [
        _PlayerBar(state: s, player: them, lookup: _lookup, onCard: _openCard),
        Expanded(child: _Battlefield(state: s, player: them.id, flipped: true, onCard: _openCard)),
        _CenterStrip(state: s),
        Expanded(child: _Battlefield(state: s, player: me.id, onCard: _openCard)),
        _PlayerBar(state: s, player: me, lookup: _lookup, onCard: _openCard),
        _Hand(cards: s.zone(me.id, Zone.hand).toList(), onCard: _openCard),
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

/// Nome, vida e contadores de um jogador, mais o comandante e as zonas públicas.
class _PlayerBar extends StatelessWidget {
  const _PlayerBar({required this.state, required this.player, required this.lookup, required this.onCard});

  final ForgeTableState state;
  final ForgePlayer player;
  final ForgeCardLookup lookup;
  final void Function(ForgeCardView) onCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = state.active == player.id;
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
      color: active ? theme.colorScheme.primaryContainer.withOpacity(0.5) : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        Expanded(
          child: Text(
            player.lost ? '${player.name} · ${tr('perdeu')}' : player.name,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
        ),
        Text('${player.life}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        if (player.poison > 0) chip(Icons.coronavirus_outlined, '${player.poison}'),
        for (final c in command)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: GestureDetector(
              onTap: () => onCard(c),
              child: SizedBox(width: 28, child: TableCardView(instance: c.instance, card: c.card, width: 28, showDetails: false)),
            ),
          ),
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
              // o topo (o mais recente) primeiro
              itemBuilder: (_, i) {
                final c = cards[cards.length - 1 - i];
                return GestureDetector(
                  onTap: () => onCard(c),
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
  const _Battlefield({required this.state, required this.player, required this.onCard, this.flipped = false});

  final ForgeTableState state;
  final int player;
  final bool flipped;
  final void Function(ForgeCardView) onCard;

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
      _CardRow(cards: others, onCard: onCard, flex: 3),
      _CardRow(cards: lands, onCard: onCard, flex: 2),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(children: flipped ? rows.reversed.toList() : rows),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.cards, required this.onCard, required this.flex});

  final List<ForgeCardView> cards;
  final void Function(ForgeCardView) onCard;
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
            final tappedW = c.instance.tapped ? w / cardAspect : w;
            return GestureDetector(
              onTap: () => onCard(c),
              child: SizedBox(
                width: tappedW,
                child: Center(
                  child: Opacity(
                    opacity: c.sick ? 0.75 : 1,
                    child: TableCardView(instance: c.instance, card: c.card, width: w, highlighted: c.attacking),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

/// Fase, turno e a pilha (o que está à espera de resolver).
class _CenterStrip extends StatelessWidget {
  const _CenterStrip({required this.state});

  final ForgeTableState state;

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
          Text('↳ ${item.text}', maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
        if (state.stack.isEmpty && last.isNotEmpty)
          Text(last, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
      ]),
    );
  }
}

class _Hand extends StatelessWidget {
  const _Hand({required this.cards, required this.onCard});

  final List<ForgeCardView> cards;
  final void Function(ForgeCardView) onCard;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => onCard(cards[i]),
          child: TableCardView(instance: cards[i].instance, card: cards[i].card, width: 62, showDetails: false),
        ),
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
