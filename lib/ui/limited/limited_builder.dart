import 'dart:async';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/limited_builds.dart';
import '../../data/providers.dart';
import '../decks/deck_editor_screen.dart';
import '../widgets/mana.dart';
import '../widgets/responsive.dart';
import '../widgets/resume_tile.dart';
import 'limited_common.dart';
import '../../l10n/l10n.dart';

const _basics = {'W': 'Plains', 'U': 'Island', 'B': 'Swamp', 'R': 'Mountain', 'G': 'Forest'};

/// Ordem da pool.
enum _Sort { color, cost, type }

/// Montar um deck de 40 a partir de uma pool (sealed ou draft): toca numa
/// carta para a pôr ou tirar do deck; terrenos básicos à vontade. O que fica
/// de fora vai para o sideboard do deck guardado.
///
/// Em [commander] (commander draft) o deck é de 60 com o comandante, que se
/// escolhe entre as lendas da pool (ou The Prismatic Piper / Faceless One).
///
/// O que se vai montando fica guardado (Jogar → Decks por montar), para
/// continuar depois ou se a app fechar.
class LimitedBuilderScreen extends ConsumerStatefulWidget {
  const LimitedBuilderScreen({
    super.key,
    required this.pool,
    required this.title,
    this.onSaved,
    this.commander = false,
    this.restore,
  });

  final List<PoolCard> pool;
  final String title;
  final bool commander;

  /// Continuar um deck que ficou por montar.
  final LimitedBuild? restore;

  /// Depois de guardar (no draft em rede volta à sala). Sem isto, abre o deck.
  final void Function(BuildContext context, db.Deck deck)? onSaved;

  @override
  ConsumerState<LimitedBuilderScreen> createState() => _LimitedBuilderScreenState();
}

class _LimitedBuilderScreenState extends ConsumerState<LimitedBuilderScreen> {
  final Set<int> _deck = {};
  final Map<String, int> _lands = {for (final c in _basics.keys) c: 0};
  final Set<String> _colors = {};
  _Sort _sort = _Sort.color;
  late final String _id = widget.restore?.id ?? LimitedBuildStore.newId();
  late final LimitedBuildStore _builds = ref.read(limitedBuildsProvider);
  Timer? _persist;

  /// Comandantes: da pool (índice) ou os que o formato dá sempre.
  final List<int> _cmdPool = [];
  final List<PoolCard> _cmdExtra = [];

  @override
  void initState() {
    super.initState();
    final r = widget.restore;
    // Só repõe as escolhas se a pool for a mesma (a base de cartas pode ter mudado).
    if (r != null && r.pool.length == widget.pool.length) {
      _deck.addAll(r.deck.where((i) => i < widget.pool.length));
      _lands.addAll(r.lands);
      _cmdPool.addAll(r.cmdPool.where((i) => i < widget.pool.length));
      final repo = ref.read(cardRepoProvider);
      for (final id in r.cmdExtra) {
        if (repo?.get(id) case final c?) _cmdExtra.add(_extraCard(c));
      }
    }
    // Fica logo guardado: a pool não se perde se a app fechar.
    WidgetsBinding.instance.addPostFrameCallback((_) => _write());
  }

  @override
  void dispose() {
    _persist?.cancel();
    super.dispose();
  }

  PoolCard _extraCard(db.Card c) =>
      PoolCard(db.PackCard(db.BoosterPrint(c.printId, c.oracleId, 'R', '')), c, c);

  /// setState e guarda (um pouco depois, para não escrever a cada toque).
  void _set(VoidCallback fn) {
    setState(fn);
    _persist?.cancel();
    _persist = Timer(const Duration(milliseconds: 600), _write);
  }

  void _write() {
    if (!mounted) return;
    _builds.put(LimitedBuild(
      id: _id,
      title: widget.title,
      commander: widget.commander,
      pool: [for (final c in widget.pool) c.pack],
      deck: {..._deck},
      lands: {..._lands},
      cmdPool: [..._cmdPool],
      cmdExtra: [for (final c in _cmdExtra) c.base.oracleId],
    ));
  }

  List<PoolCard> get _commanders => [for (final i in _cmdPool) widget.pool[i], ..._cmdExtra];
  int get _target => widget.commander ? 60 : 40;

  /// Terrenos recomendados: 17 em 40, 24 em 60.
  int get _recommendedLands => widget.commander ? 24 : 17;
  int get _basicCount => _lands.values.fold(0, (a, b) => a + b);
  int get _poolLands => _deck.where((i) => widget.pool[i].base.isLand).length;
  int get _nonLands => _deck.length - _poolLands;
  int get _landTotal => _poolLands + _basicCount;
  int get _total => _deck.length + _basicCount + _commanders.length;

  /// Identidade de cor dos comandantes; null = sem restrição (sem comandante,
  /// ou The Prismatic Piper / Faceless One, que ficam de uma cor à escolha).
  int? get _identity {
    final cmds = _commanders;
    if (!widget.commander || cmds.isEmpty) return null;
    if (cmds.any((c) => db.isDraftWildCommander(c.base.name))) return null;
    return cmds.fold<int>(0, (m, c) => m | c.base.identityMask);
  }

  bool _inIdentity(db.Card c) {
    final id = _identity;
    return id == null || c.identityMask & ~id == 0;
  }

  /// Grupo de cor: W, U, B, R, G, multicor, incolor, terrenos.
  int _colorRank(db.Card c) {
    if (c.isLand) return 7;
    final letters = db.ManaColors.lettersOf(c.colorMask);
    if (letters.isEmpty) return 6;
    if (letters.length > 1) return 5;
    return 'WUBRG'.indexOf(letters.first);
  }

  int _typeRank(db.Card c) {
    final t = c.frontType;
    if (c.isLand) return 4;
    if (t.contains('Creature')) return 0;
    if (t.contains('Instant') || t.contains('Sorcery')) return 1;
    if (t.contains('Artifact') || t.contains('Enchantment')) return 2;
    return 3;
  }

  List<int> _sorted(Iterable<int> idx, {_Sort? by}) {
    final mode = by ?? _sort;
    final list = idx.toList();
    list.sort((a, b) {
      final ca = widget.pool[a].base, cb = widget.pool[b].base;
      final group = switch (mode) {
        _Sort.color => _colorRank(ca).compareTo(_colorRank(cb)),
        _Sort.type => _typeRank(ca).compareTo(_typeRank(cb)),
        _Sort.cost => (ca.isLand ? 1 : 0).compareTo(cb.isLand ? 1 : 0),
      };
      if (group != 0) return group;
      final mv = ca.mv.compareTo(cb.mv);
      return mv != 0 ? mv : ca.name.compareTo(cb.name);
    });
    return list;
  }

  bool _matchesColors(db.Card c) {
    if (_colors.isEmpty) return true;
    final letters = db.ManaColors.lettersOf(c.colorMask).toSet();
    if (letters.isEmpty) return _colors.contains('C');
    return letters.every(_colors.contains);
  }

  /// Completa o deck com terrenos básicos, repartidos pelos símbolos de mana
  /// das cartas do deck.
  void _suggestLands() {
    final pips = <String, int>{for (final c in _basics.keys) c: 0};
    for (final i in _deck) {
      for (final m in RegExp(r'\{([WUBRG])\}').allMatches(widget.pool[i].base.manaCost)) {
        pips[m.group(1)!] = pips[m.group(1)!]! + 1;
      }
    }
    // Sem símbolos de cor no deck (só artefactos, por exemplo): reparte pelas
    // cores das cartas e, se nem isso houver, pelas cores da pool toda.
    void byColors(Iterable<int> idx) {
      for (final i in idx) {
        for (final l in db.ManaColors.lettersOf(widget.pool[i].base.colorMask)) {
          pips[l] = pips[l]! + 1;
        }
      }
    }

    if (pips.values.every((n) => n == 0)) byColors(_deck);
    if (pips.values.every((n) => n == 0)) byColors(Iterable<int>.generate(widget.pool.length));
    final total = pips.values.fold(0, (a, b) => a + b);
    final target = (_target - _deck.length - _commanders.length).clamp(0, _target);
    _set(() {
      for (final c in _basics.keys) {
        _lands[c] = total == 0 ? 0 : (target * pips[c]! / total).floor();
      }
      // O que sobra do arredondamento vai para a cor com mais símbolos.
      final best = pips.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      if (total > 0) _lands[best] = _lands[best]! + target - _basicCount;
    });
  }

  Future<void> _save() async {
    final repo = ref.read(cardRepoProvider)!;
    final entries = <db.DeckEntry>[];
    // Uma entrada por carta e zona: a base de decks junta versões diferentes
    // da mesma carta (fica a versão da primeira).
    void add(String oracleId, String? printId, db.Board board, [int n = 1]) {
      final i = entries.indexWhere((e) => e.oracleId == oracleId && e.board == board);
      if (i >= 0) {
        final e = entries[i];
        entries[i] = db.DeckEntry(oracleId: oracleId, qty: e.qty + n, board: board, printId: e.printId);
      } else {
        entries.add(db.DeckEntry(oracleId: oracleId, qty: n, board: board, printId: printId));
      }
    }

    for (final c in _commanders) {
      add(c.base.oracleId, c.printId, db.Board.command);
    }
    for (var i = 0; i < widget.pool.length; i++) {
      if (_cmdPool.contains(i)) continue;
      final c = widget.pool[i];
      add(c.base.oracleId, c.printId, _deck.contains(i) ? db.Board.main : db.Board.side);
    }
    for (final MapEntry(key: c, value: n) in _lands.entries) {
      if (n == 0) continue;
      final land = repo.findByName(_basics[c]!);
      if (land != null) add(land.oracleId, null, db.Board.main, n);
    }
    final now = DateTime.now();
    final deck = ref.read(decksProvider).save(db.Deck(
          name: '${widget.title} · ${shortDate(now)}',
          format: widget.commander ? 'commanderdraft' : 'limited',
          entries: entries,
          notes: tr('O sideboard tem o resto da pool.'),
        ));
    _persist?.cancel();
    _builds.remove(_id);
    if (!mounted) return;
    final done = widget.onSaved;
    if (done != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('"{v}" guardado.', {'v': deck.name}))));
      done(context, deck);
      return;
    }
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => DeckEditorScreen(deckId: deck.id!),
    ));
  }

  /// Sair sem guardar o deck: fica por montar (ou deita-se fora).
  Future<void> _leave() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sair sem guardar o deck?')),
        content:
            Text(tr('A pool e o que já escolheste ficam em Jogar → Decks por montar, para acabares depois.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'stay'), child: Text(tr('Ficar'))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'drop'), child: Text(tr('Deitar fora'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'keep'), child: Text(tr('Sair'))),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'stay') return;
    _persist?.cancel();
    if (choice == 'drop') {
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Deitar fora a pool?')),
          content: Text(tr('As {n} cartas desta pool perdem-se.', {'n': widget.pool.length})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Deitar fora'))),
          ],
        ),
      );
      if (sure != true || !mounted) return;
      _builds.remove(_id);
    } else {
      _write();
      _builds.refresh();
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// Escolher um ou dois comandantes. Dois se forem parceiros (Partner,
  /// Background…) ou se forem os dois monocolores.
  Future<void> _chooseCommander() async {
    final repo = ref.read(cardRepoProvider)!;
    final candidates = <({int? index, PoolCard card})>[
      for (var i = 0; i < widget.pool.length; i++)
        if (widget.pool[i].base.canBeCommander || widget.pool[i].base.frontType.contains('Background'))
          (index: i, card: widget.pool[i]),
    ];
    final seen = {for (final c in candidates) c.card.base.oracleId};
    for (final name in db.draftWildCommanders) {
      final c = repo.findByName(name);
      if (c == null || seen.contains(c.oracleId)) continue;
      candidates.add((index: null, card: _extraCard(c)));
    }
    final picked = <int>{
      for (var k = 0; k < candidates.length; k++)
        if ((candidates[k].index != null && _cmdPool.contains(candidates[k].index)) ||
            (candidates[k].index == null &&
                _cmdExtra.any((e) => e.base.oracleId == candidates[k].card.base.oracleId)))
          k,
    };
    bool valid(Set<int> s) => commanderPairOk([for (final k in s) candidates[k].card.base]);

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set_) {
        final theme = Theme.of(ctx);
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.85,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(tr('Comandante'), style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                tr('Uma lenda que tiraste no draft. Podes ter duas se forem parceiras (Partner, Background) ou se forem as duas de uma só cor. The Prismatic Piper e Faceless One estão sempre disponíveis e ficam da cor que escolheres antes do jogo.'),
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(children: [
                PoolGrid(target: 110, children: [
                  for (var k = 0; k < candidates.length; k++)
                    Stack(children: [
                      PoolCardView(
                        card: candidates[k].card,
                        onTap: () => set_(() {
                          if (!picked.remove(k)) {
                            if (picked.length >= 2) picked.clear();
                            picked.add(k);
                          }
                        }),
                      ),
                      if (picked.contains(k))
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(color: theme.colorScheme.primary, width: 4),
                              ),
                              alignment: Alignment.topRight,
                              padding: const EdgeInsets.all(4),
                              child: const Icon(Icons.check_circle, color: Colors.white),
                            ),
                          ),
                        ),
                    ]),
                ]),
              ]),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (picked.isNotEmpty && !valid(picked))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        picked.length == 2
                            ? tr('Estas duas não podem ser comandantes juntas.')
                            : tr('Esta carta precisa de outra comandante (Background).'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  FilledButton(
                    onPressed: valid(picked) ? () => Navigator.pop(ctx, true) : null,
                    child: Text(picked.length == 2 ? tr('Usar estas duas') : tr('Usar este comandante')),
                  ),
                ]),
              ),
            ),
          ]),
        );
      }),
    );
    if (ok != true || !mounted) return;
    _set(() {
      _cmdPool.clear();
      _cmdExtra.clear();
      for (final k in picked) {
        final c = candidates[k];
        if (c.index != null) {
          _cmdPool.add(c.index!);
          _deck.remove(c.index);
        } else {
          _cmdExtra.add(c.card);
        }
      }
      // O que ficou fora da identidade sai do deck.
      _deck.removeWhere((i) => !_inIdentity(widget.pool[i].base));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deck = _sorted(_deck, by: _Sort.cost);
    // Os básicos que saem nos boosters não aparecem: estão nos contadores.
    final pool = _sorted([
      for (var i = 0; i < widget.pool.length; i++)
        if (!_deck.contains(i) &&
            !_cmdPool.contains(i) &&
            !widget.pool[i].base.isBasicLand &&
            _matchesColors(widget.pool[i].base) &&
            _inIdentity(widget.pool[i].base))
          i,
    ]);
    final outside =
        widget.pool.indexed.where((e) => !_cmdPool.contains(e.$1) && !_inIdentity(e.$2.base)).length;
    final commanders = _commanders;
    final curve = List.filled(7, 0);
    var creatures = 0;
    for (final i in _deck) {
      final c = widget.pool[i].base;
      if (!c.isLand) curve[c.mv.round().clamp(0, 6)]++;
      if (c.frontType.contains('Creature')) creatures++;
    }
    final lands = _landTotal;
    final landNote = lands == 0
        ? null
        : lands > _recommendedLands + 2
            ? tr('Tens {lands} terrenos; o normal é cerca de {recommendedLands}. Põe mais cartas da pool.',
                {'lands': lands, 'recommendedLands': _recommendedLands})
            : lands < _recommendedLands - 3 && _total >= _target
                ? tr('Só {lands} terrenos; o normal é cerca de {recommendedLands}.',
                    {'lands': lands, 'recommendedLands': _recommendedLands})
                : null;

    final deckSection = [
      if (widget.commander)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Expanded(
              child: Text(
                  commanders.isEmpty
                      ? tr('Comandante')
                      : tr('Comandante: {v}', {'v': commanders.map((c) => c.base.displayName).join(' + ')}),
                  style: theme.textTheme.titleMedium),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: _chooseCommander,
              icon: const Icon(Icons.workspace_premium_outlined, size: 18),
              label: Text(commanders.isEmpty ? tr('Escolher') : tr('Trocar')),
            ),
          ]),
        ),
      if (widget.commander && commanders.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(tr(
              'Escolhe primeiro o comandante: a pool passa a mostrar só as cartas da sua identidade de cor.')),
        ),
      if (commanders.isNotEmpty)
        PoolGrid(target: 96, children: [for (final c in commanders) PoolCardView(card: c)]),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          Text(tr('Deck ({n})', {'n': _deck.length}), style: theme.textTheme.titleMedium),
          const Spacer(),
          for (var i = 1; i < 7; i++)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('${i == 6 ? '6+' : i}:${curve[i]}', style: theme.textTheme.labelSmall),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
        child: Text(
            tr('{creatures} criaturas · {v} outras · {poolLands} terrenos da pool',
                {'creatures': creatures, 'v': _nonLands - creatures, 'poolLands': _poolLands}),
            style: theme.textTheme.bodySmall),
      ),
      if (deck.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(tr('Toca nas cartas da pool para as pôr no deck. Toque longo para ver a carta.')),
        )
      else
        PoolGrid(target: 96, children: [
          for (final i in deck) PoolCardView(card: widget.pool[i], onTap: () => _set(() => _deck.remove(i))),
        ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(children: [
          Expanded(
              child: Text(tr('Terrenos básicos ({basicCount})', {'basicCount': _basicCount}),
                  style: theme.textTheme.titleMedium)),
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: _deck.isEmpty ? null : _suggestLands,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: Text(tr('Completar até {target}', {'target': _target})),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(
          landNote ??
              tr('Terrenos no deck: {lands} (recomendado: cerca de {recommendedLands}).',
                  {'lands': lands, 'recommendedLands': _recommendedLands}),
          style:
              theme.textTheme.bodySmall?.copyWith(color: landNote != null ? theme.colorScheme.error : null),
        ),
      ),
      Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
        for (final c in _basics.keys)
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _lands[c]! > 0 ? () => _set(() => _lands[c] = _lands[c]! - 1) : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            ManaSymbol(c, size: 22),
            SizedBox(width: 26, child: Text('${_lands[c]}', textAlign: TextAlign.center)),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => _set(() => _lands[c] = _lands[c]! + 1),
              icon: const Icon(Icons.add, size: 18),
            ),
          ]),
      ]),
    ];

    final poolSection = [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
            tr('Pool ({n}){v}', {
              'n': pool.length,
              'v': outside > 0 ? tr(' · {outside} fora da identidade', {'outside': outside}) : ''
            }),
            style: theme.textTheme.titleMedium),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final c in ['W', 'U', 'B', 'R', 'G', 'C'])
            FilterChip(
              label: ManaSymbol(c, size: 18),
              selected: _colors.contains(c),
              showCheckmark: false,
              onSelected: (v) => setState(() => v ? _colors.add(c) : _colors.remove(c)),
            ),
          const SizedBox(width: 4),
          SegmentedButton<_Sort>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: _Sort.color, label: Text(tr('Cor'))),
              ButtonSegment(value: _Sort.cost, label: Text(tr('Custo'))),
              ButtonSegment(value: _Sort.type, label: Text(tr('Tipo'))),
            ],
            selected: {_sort},
            onSelectionChanged: (v) => setState(() => _sort = v.first),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      PoolGrid(target: 96, children: [
        for (final i in pool) PoolCardView(card: widget.pool[i], onTap: () => _set(() => _deck.add(i))),
      ]),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, overflow: TextOverflow.ellipsis),
            Text(
                tr('{v}{nonLands} cartas + {lands} terrenos = {total} / {target}', {
                  'v': commanders.isEmpty ? '' : '${commanders.length} + ',
                  'nonLands': _nonLands,
                  'lands': lands,
                  'total': _total,
                  'target': _target
                }),
                style: theme.textTheme.bodySmall?.copyWith(color: _total >= _target ? Colors.green : null)),
          ]),
          actions: [
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: _deck.isEmpty || (widget.commander && _commanders.isEmpty) ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(tr('Guardar')),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: isWide(context)
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 32), children: poolSection)),
                const VerticalDivider(width: 1),
                Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 32), children: deckSection)),
              ])
            : ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [...deckSection, const Divider(), ...poolSection]),
      ),
    );
  }
}

/// Se estas cartas podem ser os comandantes de um commander draft: uma lenda,
/// ou duas parceiras (Partner, Background…) ou duas lendas monocolores.
bool commanderPairOk(List<db.Card> cards) {
  if (cards.length == 1) return cards.first.canBeCommander;
  if (cards.length != 2) return false;
  final [a, b] = cards;
  if (db.canPartner(a, b)) return true;
  bool mono(db.Card c) => c.canBeCommander && db.ManaColors.lettersOf(c.colorMask).length == 1;
  return mono(a) && mono(b);
}

/// Continuar a montar um deck que ficou por montar.
Future<void> resumeLimitedBuild(BuildContext context, WidgetRef ref, LimitedBuild b) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LimitedBuilderScreen(
        pool: resolvePool(ref, b.pool),
        title: b.title,
        commander: b.commander,
        restore: b,
      ),
    ));

/// Cartão "Decks por montar" (separador Jogar): pools de sealed e draft que
/// ficaram a meio.
class LimitedBuildsCard extends ConsumerWidget {
  const LimitedBuildsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final builds = ref.watch(limitedBuildsProvider).builds;
    if (builds.isEmpty || ref.watch(cardRepoProvider) == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(tr('Decks por montar'), style: theme.textTheme.titleSmall),
        ),
        for (final b in builds)
          ResumeTile(
            icon: Icons.construction,
            title: b.title,
            subtitle: tr('{n} cartas na pool · {n2} no deck · {v}',
                {'n': b.pool.length, 'n2': b.deck.length, 'v': shortDate(b.savedAt)}),
            deleteTooltip: tr('Deitar fora'),
            onDelete: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(tr('Deitar fora a pool?')),
                  content: Text(
                      tr('{title}: as {n} cartas perdem-se.', {'title': b.title, 'n': b.pool.length})),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Deitar fora'))),
                  ],
                ),
              );
              if (ok == true) ref.read(limitedBuildsProvider).remove(b.id);
            },
            actionLabel: tr('Montar'),
            onAction: () => resumeLimitedBuild(context, ref, b),
          ),
      ]),
    );
  }
}
