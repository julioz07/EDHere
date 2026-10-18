import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../decks/deck_editor_screen.dart';
import '../widgets/mana.dart';
import '../widgets/responsive.dart';
import 'limited_common.dart';

const _basics = {'W': 'Plains', 'U': 'Island', 'B': 'Swamp', 'R': 'Mountain', 'G': 'Forest'};

/// Montar um deck de 40 a partir de uma pool (sealed ou draft): toca numa
/// carta para a pôr ou tirar do deck; terrenos básicos à vontade. O que fica
/// de fora vai para o sideboard do deck guardado.
///
/// Em [commander] (commander draft) o deck é de 60 com o comandante, que se
/// escolhe entre as lendas da pool (ou The Prismatic Piper / Faceless One).
class LimitedBuilderScreen extends ConsumerStatefulWidget {
  const LimitedBuilderScreen(
      {super.key, required this.pool, required this.title, this.onSaved, this.commander = false});

  final List<PoolCard> pool;
  final String title;
  final bool commander;

  /// Depois de guardar (no draft em rede volta à sala). Sem isto, abre o deck.
  final void Function(BuildContext context, db.Deck deck)? onSaved;

  @override
  ConsumerState<LimitedBuilderScreen> createState() => _LimitedBuilderScreenState();
}

class _LimitedBuilderScreenState extends ConsumerState<LimitedBuilderScreen> {
  final Set<int> _deck = {};
  final Map<String, int> _lands = {for (final c in _basics.keys) c: 0};
  final Set<String> _colors = {};

  /// Comandantes: da pool (índice) ou os que o formato dá sempre.
  final List<int> _cmdPool = [];
  final List<PoolCard> _cmdExtra = [];

  List<PoolCard> get _commanders => [for (final i in _cmdPool) widget.pool[i], ..._cmdExtra];
  int get _target => widget.commander ? 60 : 40;
  int get _spells => _deck.length;
  int get _landCount => _lands.values.fold(0, (a, b) => a + b);
  int get _total => _spells + _landCount + _commanders.length;

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

  List<int> _sorted(Iterable<int> idx) {
    final list = idx.toList();
    list.sort((a, b) {
      final ca = widget.pool[a].base, cb = widget.pool[b].base;
      final la = ca.isLand ? 1 : 0, lb = cb.isLand ? 1 : 0;
      if (la != lb) return la.compareTo(lb);
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

  /// 17 terrenos repartidos pelos símbolos de mana das cartas do deck.
  void _suggestLands() {
    final pips = <String, int>{for (final c in _basics.keys) c: 0};
    for (final i in _deck) {
      for (final m in RegExp(r'\{([WUBRG])\}').allMatches(widget.pool[i].base.manaCost)) {
        pips[m.group(1)!] = pips[m.group(1)!]! + 1;
      }
    }
    final total = pips.values.fold(0, (a, b) => a + b);
    final target = (_target - _spells - _commanders.length).clamp(0, _target);
    setState(() {
      for (final c in _basics.keys) {
        _lands[c] = total == 0 ? 0 : (target * pips[c]! / total).floor();
      }
      // O que sobra do arredondamento vai para a cor com mais símbolos.
      final best = pips.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      if (total > 0) _lands[best] = _lands[best]! + target - _landCount;
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
          notes: 'O sideboard tem o resto da pool.',
        ));
    if (!mounted) return;
    final done = widget.onSaved;
    if (done != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${deck.name}" guardado.')));
      done(context, deck);
      return;
    }
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => DeckEditorScreen(deckId: deck.id!),
    ));
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
      candidates.add((
        index: null,
        card: PoolCard(db.PackCard(db.BoosterPrint(c.printId, c.oracleId, 'R', '')), c, c),
      ));
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
              child: Text('Comandante', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Uma lenda que tiraste no draft. Podes ter duas se forem parceiras (Partner, Background) '
                'ou se forem as duas de uma só cor. The Prismatic Piper e Faceless One estão sempre '
                'disponíveis e ficam da cor que escolheres antes do jogo.',
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
                            ? 'Estas duas não podem ser comandantes juntas.'
                            : 'Esta carta precisa de outra comandante (Background).',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  FilledButton(
                    onPressed: valid(picked) ? () => Navigator.pop(ctx, true) : null,
                    child: Text(picked.length == 2 ? 'Usar estas duas' : 'Usar este comandante'),
                  ),
                ]),
              ),
            ),
          ]),
        );
      }),
    );
    if (ok != true || !mounted) return;
    setState(() {
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
    final deck = _sorted(_deck);
    final pool = _sorted([
      for (var i = 0; i < widget.pool.length; i++)
        if (!_deck.contains(i) &&
            !_cmdPool.contains(i) &&
            _matchesColors(widget.pool[i].base) &&
            _inIdentity(widget.pool[i].base))
          i,
    ]);
    final outside =
        widget.pool.indexed.where((e) => !_cmdPool.contains(e.$1) && !_inIdentity(e.$2.base)).length;
    final commanders = _commanders;
    final curve = List.filled(7, 0);
    for (final i in _deck) {
      final c = widget.pool[i].base;
      if (!c.isLand) curve[c.mv.round().clamp(0, 6)]++;
    }

    final deckSection = [
      if (widget.commander)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Expanded(
              child: Text(
                  commanders.isEmpty
                      ? 'Comandante'
                      : 'Comandante: ${commanders.map((c) => c.base.name).join(' + ')}',
                  style: theme.textTheme.titleMedium),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: _chooseCommander,
              icon: const Icon(Icons.workspace_premium_outlined, size: 18),
              label: Text(commanders.isEmpty ? 'Escolher' : 'Trocar'),
            ),
          ]),
        ),
      if (widget.commander && commanders.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
              'Escolhe primeiro o comandante: a pool passa a mostrar só as cartas da sua identidade de cor.'),
        ),
      if (commanders.isNotEmpty)
        PoolGrid(target: 96, children: [for (final c in commanders) PoolCardView(card: c)]),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Text('Deck ($_spells)', style: theme.textTheme.titleMedium),
          const Spacer(),
          for (var i = 1; i < 7; i++)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('${i == 6 ? '6+' : i}:${curve[i]}', style: theme.textTheme.labelSmall),
            ),
        ]),
      ),
      if (deck.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Toca nas cartas da pool para as pôr no deck.'),
        )
      else
        PoolGrid(target: 96, children: [
          for (final i in deck)
            PoolCardView(card: widget.pool[i], onTap: () => setState(() => _deck.remove(i))),
        ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(children: [
          Text('Terrenos básicos ($_landCount)', style: theme.textTheme.titleMedium),
          const Spacer(),
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: _deck.isEmpty ? null : _suggestLands,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: Text('Completar até $_target'),
          ),
        ]),
      ),
      Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
        for (final c in _basics.keys)
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _lands[c]! > 0 ? () => setState(() => _lands[c] = _lands[c]! - 1) : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            ManaSymbol(c, size: 22),
            SizedBox(width: 26, child: Text('${_lands[c]}', textAlign: TextAlign.center)),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _lands[c] = _lands[c]! + 1),
              icon: const Icon(Icons.add, size: 18),
            ),
          ]),
      ]),
    ];

    final poolSection = [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('Pool (${pool.length})${outside > 0 ? ' · $outside fora da identidade' : ''}',
            style: theme.textTheme.titleMedium),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(spacing: 6, children: [
          for (final c in ['W', 'U', 'B', 'R', 'G', 'C'])
            FilterChip(
              label: ManaSymbol(c, size: 18),
              selected: _colors.contains(c),
              showCheckmark: false,
              onSelected: (v) => setState(() => v ? _colors.add(c) : _colors.remove(c)),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      PoolGrid(target: 96, children: [
        for (final i in pool) PoolCardView(card: widget.pool[i], onTap: () => setState(() => _deck.add(i))),
      ]),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, overflow: TextOverflow.ellipsis),
          Text(
              '${commanders.isEmpty ? '' : '${commanders.length} + '}'
              '$_spells + $_landCount terrenos = $_total / $_target',
              style: theme.textTheme.bodySmall?.copyWith(color: _total >= _target ? Colors.green : null)),
        ]),
        actions: [
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: _deck.isEmpty || (widget.commander && _commanders.isEmpty) ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar'),
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
