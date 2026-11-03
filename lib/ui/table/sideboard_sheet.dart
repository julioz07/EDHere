import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Entre os jogos de um encontro: trocar cartas entre o deck e o sideboard.
/// Vale só para este encontro; o deck guardado não muda.
Future<db.Deck> showSideboardSheet(BuildContext context, db.Deck deck, db.CardRepository repo) async {
  var current = deck;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final theme = Theme.of(ctx);
      final cards = repo.getMany(current.entries.map((e) => e.oracleId).toList());
      String name(db.DeckEntry e) => cards[e.oracleId]?.displayName ?? '?';
      List<db.DeckEntry> sorted(db.Board b) => current.inBoard(b).toList()..sort((x, y) => name(x).compareTo(name(y)));

      /// Passa uma cópia de [e] para o outro lado.
      void moveOne(db.DeckEntry e, db.Board to) => set(() =>
          current = current.setQty(e.oracleId, e.board, e.qty - 1).add(e.oracleId, board: to, printId: e.printId));

      Widget tile(db.DeckEntry e, db.Board to) => ListTile(
            dense: true,
            title: Text(e.qty > 1 ? '${e.qty}× ${name(e)}' : name(e)),
            trailing: IconButton(
              tooltip: to == db.Board.side ? tr('Para o sideboard') : tr('Para o deck'),
              icon: Icon(to == db.Board.side ? Icons.arrow_downward : Icons.arrow_upward),
              onPressed: () => moveOne(e, to),
            ),
          );

      return SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.85,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(tr('Sideboard'), style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(tr('Troca cartas entre o deck e o sideboard. Vale só para este encontro.'),
                style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: ListView(children: [
              ListTile(
                title: Text(tr('Deck ({n})', {'n': current.count(db.Board.main)}), style: theme.textTheme.titleSmall),
              ),
              for (final e in sorted(db.Board.main)) tile(e, db.Board.side),
              ListTile(
                title:
                    Text(tr('Sideboard ({n})', {'n': current.count(db.Board.side)}), style: theme.textTheme.titleSmall),
              ),
              for (final e in sorted(db.Board.side)) tile(e, db.Board.main),
            ]),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Pronto: jogo seguinte')),
              ),
            ),
          ),
        ]),
      );
    }),
  );
  return current;
}
