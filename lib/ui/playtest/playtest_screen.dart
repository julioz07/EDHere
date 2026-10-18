import 'package:card_db/card_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../game/game_controller.dart';
import '../table/table_screen.dart';
import '../table/tablet_table_screen.dart';

/// Playtest local com os decks escolhidos, no mesmo núcleo do jogo em rede.
class PlaytestScreen extends ConsumerStatefulWidget {
  const PlaytestScreen({super.key, required this.deckIds, this.randomFirst = false, this.tablet = false});

  final List<int> deckIds;
  final bool randomFirst;

  /// Modo tablet: todos à volta do mesmo ecrã.
  final bool tablet;

  @override
  ConsumerState<PlaytestScreen> createState() => _PlaytestScreenState();
}

class _PlaytestScreenState extends ConsumerState<PlaytestScreen> {
  late final GameController _ctrl = _build();

  GameController _build() {
    final store = ref.read(deckStoreProvider);
    final repo = ref.read(cardRepoProvider)!;
    final decks = [for (final id in widget.deckIds) store.getDeck(id)!];
    final format = GameFormat.byId(decks.first.format);
    final player = ref.read(playerNameProvider);
    final prints = ref.read(printsProvider);
    return GameController.playtest(
      repo: repo,
      resolvePrint: (c, p) => prints.resolve(c, printId: p),
      effectivePrint: prints.effectivePrint,
      format: format,
      randomFirst: widget.randomFirst,
      seats: [
        for (var i = 0; i < decks.length; i++)
          SeatSetup(
            seat: i,
            name: decks.length == 1
                ? (player.isEmpty ? 'Eu' : player)
                : '${decks[i].name.length > 12 ? decks[i].name.substring(0, 12) : decks[i].name} ${i + 1}',
            deck: decks[i],
          ),
      ],
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.tablet ? TabletTableScreen(ctrl: _ctrl) : TableScreen(ctrl: _ctrl);
}
