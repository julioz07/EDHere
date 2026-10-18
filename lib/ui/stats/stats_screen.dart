import 'package:card_db/card_db.dart' hide Card;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../data/data_tab.dart' show formatDate;
import '../widgets/responsive.dart';

/// Histórico de partidas e estatísticas locais.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  @override
  Widget build(BuildContext context) {
    final store = ref.watch(deckStoreProvider);
    final decks = {for (final d in ref.watch(decksProvider).decks) d.id: d.name};
    final games = store.listGames();
    final theme = Theme.of(context);

    final solo = games.where((g) => g.players.where((p) => p.me).length == 1).toList();
    final wins = solo.where((g) => g.myWon).length;
    final avgMin = games.isEmpty ? 0 : games.fold(0, (n, g) => n + g.duration.inMinutes) / games.length;
    final avgTurns = games.isEmpty ? 0 : games.fold(0, (n, g) => n + g.turns) / games.length;

    // Vitórias por deck (só partidas em que joguei um lugar).
    final perDeck = <String, (int, int)>{};
    for (final g in solo) {
      final name = g.players.firstWhere((p) => p.me).deckName ?? decks[g.myDeckId] ?? '?';
      final (played, won) = perDeck[name] ?? (0, 0);
      perDeck[name] = (played + 1, won + (g.myWon ? 1 : 0));
    }
    // Comandantes mais vistos à mesa.
    final cmdCount = <String, int>{};
    for (final g in games) {
      for (final p in g.players) {
        for (final c in p.commanders) {
          cmdCount[c] = (cmdCount[c] ?? 0) + 1;
        }
      }
    }
    final topCmd = cmdCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    Widget stat(String label, String value) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(label, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
              ]),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Histórico e estatísticas')),
      body: MaxWidth(
          child: games.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                        'Ainda não há jogos guardados. No fim de uma partida, usa o menu da mesa → '
                        '"Terminar jogo".',
                        textAlign: TextAlign.center),
                  ),
                )
              : ListView(padding: const EdgeInsets.all(16), children: [
                  // Mesma altura para todos, mesmo quando o texto parte em duas linhas.
                  IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    stat('jogos', '${games.length}'),
                    const SizedBox(width: 8),
                    stat('vitórias', solo.isEmpty ? '—' : '${(wins * 100 / solo.length).round()}%'),
                    const SizedBox(width: 8),
                    stat('min por jogo', avgMin.toStringAsFixed(0)),
                    const SizedBox(width: 8),
                    stat('turnos', avgTurns.toStringAsFixed(1)),
                  ])),
                  if (perDeck.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Por deck', style: theme.textTheme.titleMedium),
                    for (final MapEntry(key: name, value: (played, won)) in perDeck.entries)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(name),
                        trailing: Text('$won / $played vitórias'),
                      ),
                  ],
                  if (topCmd.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Comandantes mais jogados', style: theme.textTheme.titleMedium),
                    for (final e in topCmd.take(5))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.key),
                        trailing: Text('${e.value}'),
                      ),
                  ],
                  const SizedBox(height: 8),
                  Text('Partidas', style: theme.textTheme.titleMedium),
                  for (final g in games)
                    Dismissible(
                      key: ValueKey(g.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        color: theme.colorScheme.error,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => setState(() => store.deleteGame(g.id!)),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          g.myWon ? Icons.emoji_events : Icons.sports_esports_outlined,
                          color: g.myWon ? Colors.amber : null,
                        ),
                        title: Text(g.players.map((p) => p.name).join(' · ')),
                        subtitle: Text([
                          formatDate(g.playedAt.toIso8601String()),
                          GameFormat.byId(g.format).label,
                          '${g.turns} turnos',
                          '${g.duration.inMinutes} min',
                          if (g.winner != null) 'venceu ${g.winner}',
                          if (g.network) 'em rede',
                        ].join(' · ')),
                      ),
                    ),
                ])),
    );
  }
}
