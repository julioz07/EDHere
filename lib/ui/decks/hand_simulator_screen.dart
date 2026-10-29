import 'dart:math';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';

import '../widgets/card_view.dart';
import '../widgets/responsive.dart';
import '../../l10n/l10n.dart';

/// Gera mãos iniciais seguidas para ver se o deck abre bem.
class HandSimulatorScreen extends StatefulWidget {
  const HandSimulatorScreen({super.key, required this.deck, required this.cards});

  final db.Deck deck;
  final Map<String, db.Card> cards;

  @override
  State<HandSimulatorScreen> createState() => _HandSimulatorScreenState();
}

class _HandSimulatorScreenState extends State<HandSimulatorScreen> {
  final _random = Random();
  late final List<String> _library = [
    for (final e in widget.deck.entries.where((e) => e.board == db.Board.main))
      for (var i = 0; i < e.qty; i++) e.oracleId,
  ];
  List<String> _hand = const [];
  final List<int> _landCounts = [];

  @override
  void initState() {
    super.initState();
    _newHand();
  }

  int _lands(List<String> hand) => hand.where((o) => widget.cards[o]?.isLand ?? false).length;

  void _newHand() {
    final lib = [..._library]..shuffle(_random);
    setState(() {
      _hand = lib.take(7).toList();
      _landCounts.add(_lands(_hand));
    });
  }

  /// Simula muitas mãos de uma vez para dar números estáveis.
  void _batch(int n) {
    for (var i = 0; i < n; i++) {
      final lib = [..._library]..shuffle(_random);
      _landCounts.add(_lands(lib.take(7).toList()));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _landCounts.length;
    final avg = total == 0 ? 0 : _landCounts.reduce((a, b) => a + b) / total;
    final good = _landCounts.where((l) => l >= 2 && l <= 4).length;
    final byCount = <int, int>{};
    for (final l in _landCounts) {
      byCount[l] = (byCount[l] ?? 0) + 1;
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('Mãos de {v}', {'v': widget.deck.name}))),
      body: MaxWidth(
          child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(_lands(_hand) == 1 ? tr('1 terreno nesta mão') : tr('{v} terrenos nesta mão', {'v': _lands(_hand)}), style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          childAspectRatio: cardAspect,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (final o in _hand)
              if (widget.cards[o] case final c?) CardImage(c),
          ],
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: FilledButton(
                  onPressed: _library.length < 7 ? null : _newHand, child: Text(tr('Nova mão')))),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: _library.length < 7 ? null : () => _batch(1000),
              child: Text(tr('+1000 mãos')),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        Text(total == 1 ? tr('1 mão simulada') : tr('{total} mãos simuladas', {'total': total}), style: theme.textTheme.titleSmall),
        Text(tr('Média de terrenos: {v}', {'v': avg.toStringAsFixed(2)})),
        Text(tr('Mãos com 2 a 4 terrenos: {v}%',
            {'v': total == 0 ? 0 : (good * 100 / total).toStringAsFixed(0)})),
        const SizedBox(height: 8),
        for (final k in (byCount.keys.toList()..sort()))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(width: 90, child: Text(k == 1 ? tr('1 terreno') : tr('{k} terrenos', {'k': k}))),
              Expanded(
                child: LinearProgressIndicator(
                  value: byCount[k]! / total,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text('${(byCount[k]! * 100 / total).toStringAsFixed(0)}%', textAlign: TextAlign.right),
              ),
            ]),
          ),
      ])),
    );
  }
}
