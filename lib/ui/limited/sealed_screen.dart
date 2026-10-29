import 'dart:math';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/booster_service.dart';
import '../../data/limited_builds.dart';
import '../../data/providers.dart';
import '../widgets/responsive.dart';
import '../widgets/set_symbol.dart';
import 'limited_builder.dart';
import 'limited_common.dart';
import '../../l10n/l10n.dart';
import '../../app/theme.dart';

/// Escolher um set (com pesquisa), do mais recente para o mais antigo.
Future<db.BoosterSetInfo?> showSetPicker(BuildContext context, List<db.BoosterSetInfo> sets) {
  return showModalBottomSheet<db.BoosterSetInfo>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      var query = '';
      return StatefulBuilder(builder: (ctx, set) {
        final q = db.normalizeName(query);
        final shown = q.isEmpty
            ? sets
            : sets.where((s) => db.normalizeName('${s.name} ${s.code} ${s.year}').contains(q)).toList();
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.85,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                autofocus: false,
                decoration:
                    InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Set (nome, código ou ano)')),
                onChanged: (v) => set(() => query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) {
                  final s = shown[i];
                  return ListTile(
                    dense: true,
                    leading: SizedBox(
                      width: 52,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        SetSymbol(s.code, rarity: 'R', size: 24),
                        const SizedBox(height: 2),
                        Text(s.code, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    title: Text(s.name),
                    subtitle: Text(tr('{year} · {v} · {size} cartas', {
                      'year': s.year,
                      'v': s.kind == 'play' ? tr('Play Booster') : tr('Draft Booster'),
                      'size': s.size
                    })),
                    onTap: () => Navigator.pop(ctx, s),
                  );
                },
              ),
            ),
          ]),
        );
      });
    },
  );
}

/// Sealed: cada um abre os seus boosters e monta um deck com o que saiu.
/// De um set (boosters iguais aos reais) ou de um cubo (lista própria).
class SealedSetupScreen extends ConsumerStatefulWidget {
  const SealedSetupScreen({super.key});

  @override
  ConsumerState<SealedSetupScreen> createState() => _SealedSetupScreenState();
}

class _SealedSetupScreenState extends ConsumerState<SealedSetupScreen> {
  bool _cube = false;
  db.BoosterSetInfo? _set;
  int? _cubeId;
  int _packs = 6;
  int _cubePackSize = 15;
  bool _busy = false;
  List<db.BoosterSetInfo> _sets = const [];

  @override
  void initState() {
    super.initState();
    ref.read(boosterServiceProvider).sets().then((s) {
      if (mounted) setState(() => _sets = s);
    });
  }

  Future<void> _open() async {
    setState(() => _busy = true);
    final random = Random();
    List<List<db.PackCard>> packs;
    String title;
    if (_cube) {
      final deck = ref.read(deckStoreProvider).getDeck(_cubeId!)!;
      final list = [
        for (final e in deck.entries)
          for (var i = 0; i < e.qty; i++) e.oracleId,
      ];
      final repo = ref.read(cardRepoProvider)!;
      final cards = repo.getMany(list);
      packs = [
        for (final pack in db.cubePacks(list, _packs, _cubePackSize, random))
          [
            for (final o in pack)
              if (cards[o] case final c?)
                db.PackCard(db.BoosterPrint(c.printId, o, (c.rarity.isEmpty ? 'c' : c.rarity[0]).toUpperCase(), '')),
          ],
      ];
      title = tr('Cubo {v}', {'v': deck.name});
    } else {
      final boosters = await ref.read(boosterServiceProvider).set(_set!);
      packs = [for (var i = 0; i < _packs; i++) boosters.open(random)];
      title = _set!.name;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PackOpeningScreen(packs: packs, title: title, setCode: _cube ? null : _set!.code),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubes = ref.watch(decksProvider).decks.where((d) => d.format == 'cube').toList();
    final ready = _cube ? _cubeId != null : _set != null;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Sealed'))),
      // "Abrir boosters" fica fora da lista: sempre à vista.
      body: Column(children: [
        Expanded(
          child: MaxWidth(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text(
                tr('Cada um abre os seus boosters e monta um deck de 40 cartas com o que saiu (mais terrenos básicos à vontade). Para jogar com outros, cada um faz o seu sealed e depois criam uma sala.'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, icon: const Icon(Icons.inventory_2_outlined), label: Text(tr('Set'))),
                  ButtonSegment(value: true, icon: const Icon(Icons.grid_view), label: Text(tr('Cubo'))),
                ],
                selected: {_cube},
                onSelectionChanged: (v) => setState(() => _cube = v.first),
              ),
              const SizedBox(height: 12),
              if (!_cube)
                Card(
                  child: ListTile(
                    leading: _set == null ? const Icon(Icons.style) : SetSymbol(_set!.code, rarity: 'M', size: 30),
                    title: Text(_set?.name ?? tr('Escolher set')),
                    subtitle: Text(_set == null
                        ? (_sets.isEmpty
                            ? tr('A carregar…')
                            : tr('{n} sets disponíveis, de 1993 até hoje', {'n': _sets.length}))
                        : tr('{code} · {year} · {size} cartas por booster',
                            {'code': _set!.code, 'year': _set!.year, 'size': _set!.size})),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _sets.isEmpty
                        ? null
                        : () async {
                            final s = await showSetPicker(context, _sets);
                            if (s != null) setState(() => _set = s);
                          },
                  ),
                ),
              if (!_cube && _set != null)
                SetImagesTile(set: _set!)
              else if (cubes.isEmpty)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(tr('Ainda não tens cubos')),
                    subtitle: Text(tr(
                        'Em Decks → Importar lista, cola a lista do cubo (por exemplo, exportada do CubeCobra) e escolhe o formato "Cubo".')),
                  ),
                )
              else ...[
                DropdownButtonFormField<int>(
                  value: _cubeId,
                  decoration: InputDecoration(labelText: tr('Cubo')),
                  items: [
                    for (final d in cubes)
                      DropdownMenuItem(
                          value: d.id,
                          child: Text(tr('{v} ({v2} cartas)', {'v': d.name, 'v2': d.count(db.Board.main)}))),
                  ],
                  onChanged: (v) => setState(() => _cubeId = v),
                ),
                const SizedBox(height: 8),
                _Stepper(
                  label: tr('Cartas por pack'),
                  value: _cubePackSize,
                  min: 5,
                  max: 20,
                  onChanged: (v) => setState(() => _cubePackSize = v),
                ),
              ],
              _Stepper(
                label: tr('Boosters'),
                value: _packs,
                min: 1,
                max: 12,
                onChanged: (v) => setState(() => _packs = v),
              ),
              const SizedBox(height: 16),
              Text(
                tr('Os boosters seguem a composição real de cada set (dados do MTGJSON). As imagens descarregam-se quando há rede, ou passam de outro telemóvel na sala.'),
                style: theme.textTheme.bodySmall,
              ),
            ]),
          ),
        ),
        BottomActions(children: [
          FilledButton.icon(
            onPressed: !ready || _busy ? null : _open,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.card_giftcard),
            label: Text(tr('Abrir {packs} boosters', {'packs': _packs})),
          ),
        ]),
      ]),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper(
      {required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline)),
          SizedBox(
              width: 32,
              child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
          IconButton(
              onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add_circle_outline)),
        ]),
      );
}

/// Abrir os boosters um a um (ou todos de uma vez) e depois montar o deck.
class PackOpeningScreen extends ConsumerStatefulWidget {
  const PackOpeningScreen({super.key, required this.packs, required this.title, this.setCode});
  final List<List<db.PackCard>> packs;
  final String title;

  /// Para o símbolo no cabeçalho de cada booster (null num cubo).
  final String? setCode;

  @override
  ConsumerState<PackOpeningScreen> createState() => _PackOpeningScreenState();
}

class _PackOpeningScreenState extends ConsumerState<PackOpeningScreen> {
  // Comuns primeiro e a rara no fim, como num booster a sério.
  late final List<List<PoolCard>> _packs = [
    for (final p in widget.packs) resolvePool(ref, [...p]..sort((a, b) => revealRank(a).compareTo(revealRank(b)))),
  ];
  late final int _missing = widget.packs.fold(0, (n, p) => n + p.length) - _packs.fold(0, (n, p) => n + p.length);
  int _opened = 1;

  List<PoolCard> get _pool => [for (final p in _packs) ...p];

  void _build() => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => LimitedBuilderScreen(pool: _pool, title: tr('Sealed · {title}', {'title': widget.title})),
      ));

  /// Sair antes de montar: a pool pode ficar guardada para depois.
  Future<void> _leave() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sair dos boosters?')),
        content: Text(tr('Podes guardar a pool e montar o deck depois (Jogar → Decks por montar).')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'stay'), child: Text(tr('Ficar'))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'drop'), child: Text(tr('Deitar fora'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'keep'), child: Text(tr('Guardar a pool'))),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'stay') return;
    if (choice == 'keep') {
      ref.read(limitedBuildsProvider).put(LimitedBuild(
            id: LimitedBuildStore.newId(),
            title: tr('Sealed · {title}', {'title': widget.title}),
            pool: [for (final c in _pool) c.pack],
          ));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = _opened >= _packs.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          if (_missing > 0)
            Card(
              margin: const EdgeInsets.all(12),
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.update),
                title:
                    Text(tr('{missing} cartas destes boosters não estão na tua base de cartas', {'missing': _missing})),
                subtitle: Text(tr('O set é mais recente do que a base. Atualiza-a em Definições → Dados.')),
              ),
            ),
          for (var i = _opened - 1; i >= 0; i--) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                if (widget.setCode != null) ...[
                  SetSymbol(widget.setCode!, rarity: 'R', size: 22),
                  const SizedBox(width: 8),
                ],
                Text(tr('Booster {v}', {'v': i + 1}), style: theme.textTheme.titleMedium),
              ]),
            ),
            PoolGrid(children: [for (final c in _packs[i]) PoolCardView(card: c)]),
          ],
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Text(
                    all
                        ? tr('{n} cartas na pool', {'n': _pool.length})
                        : tr('Booster {opened} de {n}', {'opened': _opened, 'n': _packs.length}),
                    style: theme.textTheme.titleSmall),
              ),
              if (!all) ...[
                TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(0, EdhSize.button)),
                    onPressed: () => setState(() => _opened = _packs.length),
                    child: Text(tr('Abrir todos'))),
                const SizedBox(width: 8),
                FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, EdhSize.button)),
                    onPressed: () => setState(() => _opened++),
                    child: Text(tr('Abrir o próximo'))),
              ] else
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, EdhSize.button)),
                  onPressed: _build,
                  icon: const Icon(Icons.construction),
                  label: Text(tr('Montar o deck')),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
