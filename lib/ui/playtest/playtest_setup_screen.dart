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

/// Partida de teste no mesmo dispositivo, de 2 a 6 jogadores: controlo-os
/// todos e, ao passar o turno, a mesa mostra o jogador seguinte. Com 2, pode
/// ser uma mesa partilhada (frente a frente) para ensinar alguém.
class TestMatchSetupScreen extends ConsumerStatefulWidget {
  const TestMatchSetupScreen({super.key});

  @override
  ConsumerState<TestMatchSetupScreen> createState() => _TestMatchSetupScreenState();
}

class _TestMatchSetupScreenState extends ConsumerState<TestMatchSetupScreen> {
  static const _maxPlayers = 6;
  late final _names = [
    TextEditingController(text: ref.read(playerNameProvider).isEmpty ? tr('Jogador 1') : ref.read(playerNameProvider)),
    for (var i = 2; i <= _maxPlayers; i++) TextEditingController(text: tr('Jogador {v}', {'v': i})),
  ];
  final List<int?> _decks = List.filled(_maxPlayers, null);
  int _count = 2;

  @override
  void initState() {
    super.initState();
    // Cada jogador começa já com um deck (alternando os que há): com 6
    // jogadores, escolher todos à mão era cansativo.
    final ids = [
      for (final d in ref.read(decksProvider).decks)
        if (d.playableCount > 0) d.id!,
    ];
    for (var i = 0; i < _maxPlayers && ids.isNotEmpty; i++) {
      _decks[i] = ids[i % ids.length];
    }
  }
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
    final ready = _decks.take(_count).every((d) => d != null);
    final shared = _shared && _count == 2;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Partida de teste'))),
      // "Começar" fica fora da lista: sempre à vista, mesmo com o teclado.
      body: Column(children: [
        Expanded(
          child: MaxWidth(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text(
                tr('Uma partida completa num só dispositivo: controlas todos os jogadores e, ao passar o turno, a mesa mostra o seguinte. Para testar decks ou ensinar alguém. Para jogar a sério, cada um com o seu telemóvel, usa "Criar sala".'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text(tr('Jogadores'), style: theme.textTheme.titleSmall)),
                IconButton.filledTonal(
                  tooltip: tr('Menos'),
                  onPressed: _count > 2 ? () => setState(() => _count--) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 40,
                  child: Text('$_count', textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                ),
                IconButton.filledTonal(
                  tooltip: tr('Mais'),
                  onPressed: _count < _maxPlayers ? () => setState(() => _count++) : null,
                  icon: const Icon(Icons.add),
                ),
              ]),
              const SizedBox(height: 12),
              for (var i = 0; i < _count; i++) ...[
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
              // A mesa partilhada (frente a frente) só existe com 2 jogadores.
              if (_count == 2) ...[
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
              ],
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
                        deckIds: [for (var i = 0; i < _count; i++) _decks[i]!],
                        names: [for (var i = 0; i < _count; i++) _name(i)],
                        randomFirst: _randomFirst,
                        tablet: shared,
                        openHands: shared && _openHands,
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
