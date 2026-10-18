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
class LimitedBuilderScreen extends ConsumerStatefulWidget {
  const LimitedBuilderScreen({super.key, required this.pool, required this.title, this.onSaved});

  final List<PoolCard> pool;
  final String title;

  /// Depois de guardar (no draft em rede volta à sala). Sem isto, abre o deck.
  final void Function(BuildContext context, db.Deck deck)? onSaved;

  @override
  ConsumerState<LimitedBuilderScreen> createState() => _LimitedBuilderScreenState();
}

class _LimitedBuilderScreenState extends ConsumerState<LimitedBuilderScreen> {
  final Set<int> _deck = {};
  final Map<String, int> _lands = {for (final c in _basics.keys) c: 0};
  final Set<String> _colors = {};

  int get _spells => _deck.length;
  int get _landCount => _lands.values.fold(0, (a, b) => a + b);
  int get _total => _spells + _landCount;

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
    final target = (40 - _spells).clamp(0, 40);
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

    for (var i = 0; i < widget.pool.length; i++) {
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
          format: 'limited',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deck = _sorted(_deck);
    final pool = _sorted([
      for (var i = 0; i < widget.pool.length; i++)
        if (!_deck.contains(i) && _matchesColors(widget.pool[i].base)) i,
    ]);
    final curve = List.filled(7, 0);
    for (final i in _deck) {
      final c = widget.pool[i].base;
      if (!c.isLand) curve[c.mv.round().clamp(0, 6)]++;
    }

    final deckSection = [
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
            label: const Text('Completar até 40'),
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
        child: Text('Pool (${widget.pool.length - _deck.length})', style: theme.textTheme.titleMedium),
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
          Text('$_spells + $_landCount terrenos = $_total / 40',
              style: theme.textTheme.bodySmall?.copyWith(color: _total >= 40 ? Colors.green : null)),
        ]),
        actions: [
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: _deck.isEmpty ? null : _save,
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
