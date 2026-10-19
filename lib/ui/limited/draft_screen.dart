import 'dart:async';
import 'dart:math';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/booster_service.dart';
import '../../data/providers.dart';
import '../../game/draft.dart';
import '../../game/network_game.dart';
import '../cards/card_detail_screen.dart';
import '../widgets/responsive.dart';
import '../widgets/set_symbol.dart';
import 'limited_builder.dart';
import 'limited_common.dart';
import 'sealed_screen.dart';
import '../../l10n/l10n.dart';

/// Sets feitos para commander draft (boosters de 20 cartas).
const commanderDraftSets = {'CMR', 'CLB', 'CMM', 'MBC'};

/// Anfitrião: escolher as regras do draft e começar. Os lugares vazios
/// (até [seats]) ficam com bots.
Future<void> showDraftSetup(BuildContext context, WidgetRef ref, NetworkGame game) async {
  final sets = await ref.read(boosterServiceProvider).sets();
  if (!context.mounted) return;
  final cubes = ref.read(decksProvider).decks.where((d) => d.format == 'cube').toList();
  final humans = game.players.values.where((p) => p.connected).toList();
  db.BoosterSetInfo? set;
  int? cubeId;
  var mode = 'set'; // set, commander, cube
  var packs = 3;
  var picks = 1;
  var timer = 0;
  var seats = max(humans.length, humans.length <= 4 ? 4 : 8);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set_) {
      final theme = Theme.of(ctx);
      final cube = mode == 'cube';
      final commander = mode == 'commander';
      final ready = cube ? cubeId != null : set != null;
      Widget stepper(String label, String value, VoidCallback? minus, VoidCallback? plus) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(onPressed: minus, icon: const Icon(Icons.remove_circle_outline)),
              SizedBox(
                  width: 56,
                  child: Text(value, textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
              IconButton(onPressed: plus, icon: const Icon(Icons.add_circle_outline)),
            ]),
          );
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Draft'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              tr(
                  'Cada um abre um booster, tira {v} e passa o resto: à esquerda, depois à direita, depois à esquerda. {v2}',
                  {
                    'v': picks == 1 ? tr('uma carta') : tr('duas cartas'),
                    'v2': commander
                        ? tr(
                            'No fim, cada um escolhe um comandante entre as lendas que tirou (ou The Prismatic Piper) e monta um deck de 60, sem singleton, para jogar com vida 40.')
                        : tr('No fim, cada um monta um deck de 40.')
                  }),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'set', label: Text(tr('Set'))),
                ButtonSegment(value: 'commander', label: Text(tr('Commander'))),
                ButtonSegment(value: 'cube', label: Text(tr('Cubo'))),
              ],
              selected: {mode},
              onSelectionChanged: (v) => set_(() {
                if (v.first == mode) return;
                mode = v.first;
                set = null;
                // Commander Legends e companhia: escolhem-se 2 de cada vez.
                picks = mode == 'commander' ? 2 : 1;
              }),
            ),
            const SizedBox(height: 8),
            if (!cube)
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading:
                      set == null ? const Icon(Icons.style) : SetSymbol(set!.code, rarity: 'M', size: 28),
                  title: Text(set?.name ?? tr('Escolher set')),
                  subtitle: set == null
                      ? null
                      : Text(tr('{code} · {year} · {size} cartas por booster',
                          {'code': set!.code, 'year': set!.year, 'size': set!.size})),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final s = await showSetPicker(
                        ctx,
                        commander
                            ? [
                                for (final s in sets)
                                  if (commanderDraftSets.contains(s.code)) s
                              ]
                            : sets);
                    if (s != null) set_(() => set = s);
                  },
                ),
              )
            else if (cubes.isEmpty)
              Text(tr('Ainda não tens cubos (Decks → Importar lista, formato "Cubo").'))
            else
              DropdownButtonFormField<int>(
                value: cubeId,
                decoration: InputDecoration(labelText: tr('Cubo')),
                items: [for (final d in cubes) DropdownMenuItem(value: d.id, child: Text(d.name))],
                onChanged: (v) => set_(() => cubeId = v),
              ),
            if (!cube && set != null) SetImagesTile(set: set!),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 1, label: Text(tr('Tirar 1'))),
                ButtonSegment(value: 2, label: Text(tr('Tirar 2 (Pick-Two)'))),
              ],
              selected: {picks},
              onSelectionChanged: (v) => set_(() => picks = v.first),
            ),
            stepper(tr('Boosters por jogador'), '$packs', packs > 1 ? () => set_(() => packs--) : null,
                packs < 6 ? () => set_(() => packs++) : null),
            stepper(
                tr('Lugares à mesa'),
                '$seats',
                seats > max(2, humans.length) ? () => set_(() => seats--) : null,
                seats < 8 ? () => set_(() => seats++) : null),
            Text(
                seats > humans.length
                    ? '${humans.length} ${humans.length == 1 ? 'jogador' : 'jogadores'} e ${seats - humans.length} '
                        '${seats - humans.length == 1 ? 'bot' : 'bots'}'
                    : tr('{n} jogadores, sem bots', {'n': humans.length}),
                style: theme.textTheme.bodySmall),
            stepper(
                tr('Tempo por escolha'),
                timer == 0 ? tr('livre') : '${timer}s',
                timer > 0 ? () => set_(() => timer = timer <= 30 ? 0 : timer - 15) : null,
                timer < 120 ? () => set_(() => timer = timer == 0 ? 30 : timer + 15) : null),
            if (timer > 0)
              Text(tr('Quando o tempo acaba, a app escolhe por ti.'), style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: !ready
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _start(ref, game,
                          set: cube ? null : set,
                          cubeId: cube ? cubeId : null,
                          packs: packs,
                          picks: picks,
                          timer: timer,
                          seats: seats,
                          commander: commander);
                    },
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(tr('Começar draft')),
            ),
          ]),
        ),
      );
    }),
  );
}

Future<void> _start(WidgetRef ref, NetworkGame game,
    {db.BoosterSetInfo? set,
    int? cubeId,
    required int packs,
    required int picks,
    required int timer,
    required int seats,
    bool commander = false}) async {
  final humans = game.players.values.where((p) => p.connected).toList();
  // Bots espalhados entre os jogadores, para não ficarem todos seguidos.
  final order = <({int? seat, String name})>[];
  final bots = seats - humans.length;
  var b = 0;
  for (var i = 0; i < humans.length; i++) {
    order.add((seat: humans[i].seat, name: humans[i].name));
    final share = ((i + 1) * bots / humans.length).round() - (i * bots / humans.length).round();
    for (var k = 0; k < share; k++) {
      order.add((seat: null, name: 'Bot ${++b}'));
    }
  }
  final List<List<List<DraftCard>>> generated;
  String title;
  if (set != null) {
    final boosters = await ref.read(boosterServiceProvider).set(set);
    generated = draftPacks(rounds: packs, seats: order.length, set: boosters);
    title = set.name;
  } else {
    final deck = ref.read(deckStoreProvider).getDeck(cubeId!)!;
    final repo = ref.read(cardRepoProvider)!;
    final cards = repo.getMany(deck.entries.map((e) => e.oracleId));
    generated = draftPacks(rounds: packs, seats: order.length, cube: [
      for (final e in deck.entries)
        for (var i = 0; i < e.qty; i++)
          if (cards[e.oracleId] case final c?)
            db.BoosterPrint(c.printId, c.oracleId, (c.rarity.isEmpty ? 'c' : c.rarity[0]).toUpperCase(), ''),
    ]);
    title = tr('Cubo {v}', {'v': deck.name});
  }
  game.startDraft(
    DraftConfig(
        title: title,
        setCode: set?.code,
        packs: packs,
        picks: picks,
        timer: timer,
        commander: commander,
        seats: order),
    generated,
  );
}

/// O ecrã do draft: o pack à frente, as escolhas e quem está à espera.
class DraftScreen extends ConsumerStatefulWidget {
  const DraftScreen({super.key, required this.client, this.onDeck});
  final DraftClient client;

  /// Deck montado no fim do draft (a sala escolhe-o logo).
  final void Function(db.Deck deck)? onDeck;

  @override
  ConsumerState<DraftScreen> createState() => _DraftScreenState();
}

class _DraftScreenState extends ConsumerState<DraftScreen> {
  DraftClient get c => widget.client;
  final Set<int> _selected = {};
  List<DraftCard>? _shownPack;
  List<PoolCard> _packCards = const [];
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && c.deadline != null) setState(() {});
    });
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _tick?.cancel();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (!identical(c.pack, _shownPack)) {
        _shownPack = c.pack;
        _selected.clear();
        _packCards = c.pack == null ? const [] : resolvePool(ref, [for (final d in c.pack!) d.pack]);
      }
    });
  }

  void _confirm() {
    final pack = c.pack;
    if (pack == null) return;
    c.choose([
      for (final d in pack)
        if (_selected.contains(d.id)) d
    ]);
  }

  void _toggle(DraftCard d) {
    setState(() {
      if (_selected.contains(d.id)) {
        _selected.remove(d.id);
      } else if (c.picks == 1) {
        _selected
          ..clear()
          ..add(d.id);
      } else if (_selected.length < c.picks) {
        _selected.add(d.id);
      }
    });
  }

  void _showPool() {
    final cards = resolvePool(ref, [for (final d in c.pool) d.pack]);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.8,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(tr('As tuas escolhas ({n})', {'n': cards.length}),
                style: Theme.of(ctx).textTheme.titleMedium),
          ),
          PoolGrid(target: 96, children: [for (final p in cards) PoolCardView(card: p)]),
        ]),
      ),
    );
  }

  Future<void> _build() async {
    final pool = resolvePool(ref, [for (final d in c.pool) d.pack]);
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => LimitedBuilderScreen(
        pool: pool,
        title: tr('Draft · {title}', {'title': c.config.title}),
        commander: c.config.commander,
        // Depois de guardar, volta à sala com o deck já escolhido.
        onSaved: (ctx, deck) {
          Navigator.of(ctx).pop();
          widget.onDeck?.call(deck);
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cfg = c.config;
    final left = c.deadline?.difference(DateTime.now()).inSeconds;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Draft · {title}', {'title': cfg.title}), overflow: TextOverflow.ellipsis),
          Text(
            c.finished
                ? tr('Terminado · {n} cartas', {'n': c.pool.length})
                : tr('Booster {v} de {packs} · escolha {pickNo} · passa para a {v2}', {
                    'v': c.round + 1,
                    'packs': cfg.packs,
                    'pickNo': c.pickNo,
                    'v2': c.direction > 0 ? tr('esquerda') : tr('direita')
                  }),
            style: theme.textTheme.bodySmall,
          ),
        ]),
        actions: [
          if (left != null && !c.finished)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: const Icon(Icons.timer_outlined, size: 18),
                label: Text('${max(0, left)}s'),
                backgroundColor: left <= 10 ? theme.colorScheme.errorContainer : null,
              ),
            ),
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: c.pool.isEmpty ? null : _showPool,
            icon: const Icon(Icons.style_outlined),
            label: Text('${c.pool.length}'),
          ),
        ],
      ),
      body: Column(children: [
        // Quem está à frente de quantos packs (a mesa, pela ordem de passagem).
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8), children: [
            for (var i = 0; i < cfg.seats.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(cfg.seats[i].seat == null ? Icons.smart_toy_outlined : Icons.person, size: 16),
                  label: Tooltip(
                    message: i < c.seats.length
                        ? '${c.seats[i].waiting} ${c.seats[i].waiting == 1 ? 'pack à espera' : 'packs à espera'}'
                        : '',
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(cfg.seats[i].name),
                      if (i < c.seats.length && c.seats[i].waiting > 0) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.inventory_2_outlined, size: 14),
                        Text(' ${c.seats[i].waiting}'),
                      ],
                    ]),
                  ),
                  backgroundColor: i < c.seats.length && c.seats[i].waiting > 1
                      ? theme.colorScheme.tertiaryContainer
                      : null,
                ),
              ),
            Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.inventory_2_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                Text(tr(' = packs à espera'),
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: c.finished
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.emoji_events_outlined, size: 48),
                    const SizedBox(height: 8),
                    Text(tr('Draft terminado: {n} cartas', {'n': c.pool.length}),
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                      onPressed: _build,
                      icon: const Icon(Icons.construction),
                      label: Text(tr('Montar o deck')),
                    ),
                  ]),
                )
              : c.pack == null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(tr('À espera do próximo pack…'), style: theme.textTheme.titleMedium),
                      ]),
                    )
                  : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(children: [
                          if (cfg.setCode != null) ...[
                            SetSymbol(cfg.setCode!, rarity: 'R', size: 20),
                            const SizedBox(width: 8),
                          ],
                          Text(
                              c.picks == 1
                                  ? tr('Escolhe 1 carta ({n} no pack)', {'n': _packCards.length})
                                  : tr('Escolhe {picks} cartas ({n} no pack)',
                                      {'picks': c.picks, 'n': _packCards.length}),
                              style: theme.textTheme.titleSmall),
                        ]),
                      ),
                      PoolGrid(target: isWide(context) ? 170 : 110, children: [
                        for (var i = 0; i < _packCards.length && i < c.pack!.length; i++)
                          GestureDetector(
                            onLongPress: () => Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => CardDetailScreen(card: _packCards[i].shown),
                            )),
                            child: Stack(children: [
                              PoolCardView(card: _packCards[i], onTap: () => _toggle(c.pack![i])),
                              if (_selected.contains(c.pack![i].id))
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(9),
                                        border: Border.all(color: theme.colorScheme.primary, width: 4),
                                        color: theme.colorScheme.primary.withOpacity(0.15),
                                      ),
                                      child: const Align(
                                        alignment: Alignment.topRight,
                                        child: Padding(
                                          padding: EdgeInsets.all(4),
                                          child: Icon(Icons.check_circle, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                      ]),
                    ]),
        ),
      ]),
      bottomNavigationBar: c.pack == null || c.finished
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _selected.length == c.picks ? _confirm : null,
                  icon: const Icon(Icons.check),
                  label: Text(c.picks == 1
                      ? tr('Escolher esta')
                      : tr('Escolher ({n}/{picks})', {'n': _selected.length, 'picks': c.picks})),
                ),
              ),
            ),
    );
  }
}
