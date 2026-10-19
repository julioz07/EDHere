import 'package:card_db/card_db.dart' hide Card;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../widgets/responsive.dart';
import 'playtest_screen.dart';
import '../../l10n/l10n.dart';

/// Testar um deck sozinho (goldfish): tocar num deck começa logo.
class GoldfishSetupScreen extends ConsumerWidget {
  const GoldfishSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider).decks;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Goldfish'))),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(tr('Joga sozinho com um deck para ver como abre e como corre.'), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          for (final d in decks)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(d.name),
                subtitle: Text(tr('{v} · {playableCount} cartas',
                    {'v': GameFormat.byId(d.format).label, 'playableCount': d.playableCount})),
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
    TextEditingController(text: ref.read(playerNameProvider).isEmpty ? tr('Jogador 1') : ref.read(playerNameProvider)),
    TextEditingController(text: tr('Jogador 2')),
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

  String _name(int i) => _names[i].text.trim().isEmpty ? tr('Jogador {v}', {'v': i + 1}) : _names[i].text.trim();

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).decks.where((d) => d.playableCount > 0).toList();
    final theme = Theme.of(context);
    final ready = _decks.every((d) => d != null);
    return Scaffold(
      appBar: AppBar(title: Text(tr('1 contra 1 neste dispositivo'))),
      // "Começar" fica fora da lista: sempre à vista, mesmo com o teclado.
      body: Column(children: [
        Expanded(
          child: MaxWidth(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text(
                tr('Para ensinar alguém a jogar ou testar um deck contra outro, com um só dispositivo. Para jogar a sério, cada um com o seu telemóvel, usa "Criar sala".'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < 2; i++) ...[
                Text(tr('Jogador {v}', {'v': i + 1}), style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _names[i],
                      textCapitalization: TextCapitalization.words,
                      maxLength: 20,
                      decoration: InputDecoration(labelText: tr('Nome'), counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      value: _decks[i],
                      isExpanded: true,
                      decoration: InputDecoration(labelText: tr('Deck')),
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
                title: Text(tr('Mesa partilhada (frente a frente)')),
                subtitle: Text(tr('O ecrã fica dividido: cada um vê a sua metade virada para si.')),
                value: _shared,
                onChanged: (v) => setState(() => _shared = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Mãos abertas')),
                subtitle: Text(tr('As duas mãos ficam à vista: bom para ensinar.')),
                value: _openHands,
                onChanged: _shared ? (v) => setState(() => _openHands = v) : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Primeiro jogador ao acaso')),
                value: _randomFirst,
                onChanged: (v) => setState(() => _randomFirst = v),
              ),
              if (decks.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(tr('Cria primeiro um deck.'), style: theme.textTheme.bodySmall),
                ),
            ]),
          ),
        ),
        BottomActions(children: [
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
            label: Text(tr('Começar')),
          ),
        ]),
      ]),
    );
  }
}
