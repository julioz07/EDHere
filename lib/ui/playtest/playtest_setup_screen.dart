import 'package:card_db/card_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'playtest_screen.dart';
import '../widgets/responsive.dart';

/// Escolher os decks do playtest: 1 deck = goldfish; 2 a 4 = hot-seat
/// (vários lugares controlados por mim no mesmo dispositivo).
class PlaytestSetupScreen extends ConsumerStatefulWidget {
  const PlaytestSetupScreen({super.key});

  @override
  ConsumerState<PlaytestSetupScreen> createState() => _PlaytestSetupScreenState();
}

class _PlaytestSetupScreenState extends ConsumerState<PlaytestSetupScreen> {
  final List<int> _chosen = [];
  bool _randomFirst = false;
  bool _tablet = false;

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).decks;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Playtest')),
      body: MaxWidth(
          child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Escolhe 1 deck para jogar sozinho (goldfish) ou até 4 para controlares '
            'vários lugares neste dispositivo (hot-seat). Podes escolher o mesmo deck mais '
            'de uma vez.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_chosen.isNotEmpty) ...[
            Text('Lugares', style: theme.textTheme.titleSmall),
            for (var i = 0; i < _chosen.length; i++)
              ListTile(
                dense: true,
                leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                title: Text(decks.firstWhere((d) => d.id == _chosen[i]).name),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _chosen.removeAt(i)),
                ),
              ),
            const Divider(),
          ],
          Text('Os meus decks', style: theme.textTheme.titleSmall),
          for (final d in decks)
            ListTile(
              title: Text(d.name),
              subtitle: Text('${GameFormat.byId(d.format).label} · ${d.playableCount} cartas'),
              trailing: const Icon(Icons.add),
              enabled: _chosen.length < 4 && d.playableCount > 0,
              onTap: () => setState(() => _chosen.add(d.id!)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Primeiro jogador ao acaso'),
            value: _randomFirst,
            onChanged: (v) => setState(() => _randomFirst = v),
          ),
          if (_chosen.length >= 2)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Modo tablet (mesa partilhada)'),
              subtitle: const Text(
                  'Cada jogador fica com a sua área virada para si. Ideal para um tablet no meio da mesa.'),
              value: _tablet,
              onChanged: (v) => setState(() => _tablet = v),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _chosen.isEmpty
                ? null
                : () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                      builder: (_) => PlaytestScreen(
                        deckIds: [..._chosen],
                        randomFirst: _randomFirst,
                        tablet: _tablet && _chosen.length >= 2,
                      ),
                    )),
            child: Text(_chosen.length <= 1 ? 'Começar goldfish' : 'Começar hot-seat (${_chosen.length})'),
          ),
        ],
      )),
    );
  }
}
