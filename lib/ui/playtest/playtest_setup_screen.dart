import 'package:card_db/card_db.dart' hide Card;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../widgets/responsive.dart';
import 'playtest_screen.dart';

/// Testar um deck sozinho (goldfish): tocar num deck começa logo.
class GoldfishSetupScreen extends ConsumerWidget {
  const GoldfishSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider).decks;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Goldfish')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Joga sozinho com um deck para ver como abre e como corre.',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          for (final d in decks)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(d.name),
                subtitle: Text('${GameFormat.byId(d.format).label} · ${d.playableCount} cartas'),
                trailing: const Icon(Icons.play_arrow_rounded),
                enabled: d.playableCount > 0,
                onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                  builder: (_) => PlaytestScreen(deckIds: [d.id!]),
                )),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Dois jogadores no mesmo dispositivo: para ensinar alguém ou testar um
/// deck contra outro.
class DuelSetupScreen extends ConsumerStatefulWidget {
  const DuelSetupScreen({super.key});

  @override
  ConsumerState<DuelSetupScreen> createState() => _DuelSetupScreenState();
}

class _DuelSetupScreenState extends ConsumerState<DuelSetupScreen> {
  late final _names = [
    TextEditingController(
        text: ref.read(playerNameProvider).isEmpty ? 'Jogador 1' : ref.read(playerNameProvider)),
    TextEditingController(text: 'Jogador 2'),
  ];
  final List<int?> _decks = [null, null];
  bool _randomFirst = true;
  late bool _shared = true;
  bool _openHands = false;

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  String _name(int i) => _names[i].text.trim().isEmpty ? 'Jogador ${i + 1}' : _names[i].text.trim();

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).decks.where((d) => d.playableCount > 0).toList();
    final theme = Theme.of(context);
    final ready = _decks.every((d) => d != null);
    return Scaffold(
      appBar: AppBar(title: const Text('1 contra 1 neste dispositivo')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(
            'Para ensinar alguém a jogar ou testar um deck contra outro, com um só dispositivo. '
            'Para jogar a sério, cada um com o seu telemóvel, usa "Criar sala".',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 2; i++) ...[
            Text('Jogador ${i + 1}', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _names[i],
                  textCapitalization: TextCapitalization.words,
                  maxLength: 20,
                  decoration: const InputDecoration(labelText: 'Nome', counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  value: _decks[i],
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Deck'),
                  items: [
                    for (final d in decks)
                      DropdownMenuItem(value: d.id, child: Text(d.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _decks[i] = v),
                ),
              ),
            ]),
            const SizedBox(height: 16),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mesa partilhada (frente a frente)'),
            subtitle: const Text('O ecrã fica dividido: cada um vê a sua metade virada para si.'),
            value: _shared,
            onChanged: (v) => setState(() => _shared = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mãos abertas'),
            subtitle: const Text('As duas mãos ficam à vista: bom para ensinar.'),
            value: _openHands,
            onChanged: _shared ? (v) => setState(() => _openHands = v) : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Primeiro jogador ao acaso'),
            value: _randomFirst,
            onChanged: (v) => setState(() => _randomFirst = v),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: !ready
                ? null
                : () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                      builder: (_) => PlaytestScreen(
                        deckIds: [_decks[0]!, _decks[1]!],
                        names: [_name(0), _name(1)],
                        randomFirst: _randomFirst,
                        tablet: _shared,
                        openHands: _openHands,
                      ),
                    )),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Começar'),
          ),
          if (decks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Cria primeiro um deck.', style: theme.textTheme.bodySmall),
            ),
        ]),
      ),
    );
  }
}
