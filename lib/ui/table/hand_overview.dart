import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart' hide Table, Intent;
import 'package:mesa_core/mesa_core.dart';

import '../../game/game_controller.dart';
import '../../l10n/l10n.dart';
import '../widgets/card_view.dart';
import 'table_card.dart';
import 'table_sheets.dart';

/// A mão toda num ecrã: as cartas grandes, agrupadas por tipo ou por custo,
/// com filtros. Tocar numa carta abre as ações dela (as mesmas da mesa).
class HandOverviewScreen extends StatefulWidget {
  const HandOverviewScreen({super.key, required this.ctrl, required this.seat});
  final GameController ctrl;
  final int seat;

  @override
  State<HandOverviewScreen> createState() => _HandOverviewScreenState();
}

enum _Kind { land, creature, spell, other }

class _HandOverviewScreenState extends State<HandOverviewScreen> {
  _Kind? _filter;
  bool _byCost = false;

  GameController get ctrl => widget.ctrl;

  @override
  void initState() {
    super.initState();
    ctrl.addListener(_changed);
  }

  @override
  void dispose() {
    ctrl.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // a mão ficou vazia (jogou-se a última): volta à mesa
    if (ctrl.zones(widget.seat).hand.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  static _Kind _kind(db.Card? c) {
    final t = c?.frontType ?? '';
    if (c?.isLand ?? false) return _Kind.land;
    if (t.contains('Creature')) return _Kind.creature;
    if (t.contains('Instant') || t.contains('Sorcery')) return _Kind.spell;
    return _Kind.other;
  }

  static String _kindLabel(_Kind k) => switch (k) {
        _Kind.land => tr('Terrenos'),
        _Kind.creature => tr('Criaturas'),
        _Kind.spell => tr('Instantâneos e feitiços'),
        _Kind.other => tr('Outras'),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hand = ctrl.zones(widget.seat).hand;
    final cards = {for (final pc in hand) pc.pid: ctrl.card(pc.oracleId, printId: pc.printId)};
    final counts = {for (final k in _Kind.values) k: hand.where((pc) => _kind(cards[pc.pid]) == k).length};
    final shown = [
      for (final pc in hand)
        if (_filter == null || _kind(cards[pc.pid]) == _filter) pc
    ]..sort((a, b) {
        final ca = cards[a.pid], cb = cards[b.pid];
        final mv = (ca?.mv ?? 0).compareTo(cb?.mv ?? 0);
        return mv != 0 ? mv : (ca?.displayName ?? '').compareTo(cb?.displayName ?? '');
      });
    // grupos: por tipo (terrenos primeiro, como numa mesa) ou por custo
    final groups = <String, List<PrivateCard>>{};
    if (_byCost) {
      for (final pc in shown) {
        final c = cards[pc.pid];
        final key = (c?.isLand ?? false)
            ? tr('Terrenos')
            : (c?.mv ?? 0) >= 7
                ? tr('Custo 7+')
                : tr('Custo {n}', {'n': (c?.mv ?? 0).toInt()});
        groups.putIfAbsent(key, () => []).add(pc);
      }
    } else {
      for (final k in _Kind.values) {
        final list = shown.where((pc) => _kind(cards[pc.pid]) == k).toList();
        if (list.isNotEmpty) groups[_kindLabel(k)] = list;
      }
    }
    // três por linha num telemóvel, mais num tablet (32 de margens, 8 entre cartas)
    final width = MediaQuery.sizeOf(context).width - 32;
    final cols = width > 600 ? 6 : 3;
    final cardW = ((width - (cols - 1) * 8) / cols).floorToDouble();

    Widget chip(String label, int n, _Kind? k) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text('$label $n'),
            selected: _filter == k,
            onSelected: n == 0 && k != null ? null : (_) => setState(() => _filter = k),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(hand.length == 1 ? tr('A tua mão: 1 carta') : tr('A tua mão: {n} cartas', {'n': hand.length})),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(value: false, label: Text(tr('Tipo'))),
                ButtonSegment(value: true, label: Text(tr('Custo'))),
              ],
              selected: {_byCost},
              onSelectionChanged: (v) => setState(() => _byCost = v.first),
            ),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            chip(tr('Todas'), hand.length, null),
            for (final k in _Kind.values)
              if (counts[k]! > 0) chip(_kindLabel(k), counts[k]!, k),
          ]),
        ),
        for (final MapEntry(key: title, value: list) in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text('$title · ${list.length}',
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final pc in list)
              Semantics(
                button: true,
                label: cards[pc.pid]?.displayName ?? tr('carta'),
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () {
                    ctrl.actAs(widget.seat);
                    showHandCardActions(context, ctrl, pc);
                  },
                  child: SizedBox(
                    width: cardW,
                    child: cards[pc.pid] == null ? const CardBack() : CardImage(cards[pc.pid]!, preferNormal: true),
                  ),
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}
