import 'package:card_db/card_db.dart' hide Card;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bot/forge_engine.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../widgets/responsive.dart';
import 'bot_table_screen.dart';

/// Preparar uma partida contra o bot: o meu deck, o deck do bot e a dificuldade.
class BotSetupScreen extends ConsumerStatefulWidget {
  const BotSetupScreen({super.key});

  @override
  ConsumerState<BotSetupScreen> createState() => _BotSetupScreenState();
}

class _BotSetupScreenState extends ConsumerState<BotSetupScreen> {
  int? _myDeck;
  int? _botDeck;
  BotLevel _level = BotLevel.normal;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final ids = [
      for (final d in ref.read(decksProvider).decks)
        if (d.playableCount > 0) d.id!,
    ];
    if (ids.isNotEmpty) {
      _myDeck = ids.first;
      _botDeck = ids.length > 1 ? ids[1] : ids.first;
    }
  }

  /// [watch]: o meu deck também fica com um bot (para ver o motor a jogar).
  Future<void> _start({bool watch = false}) async {
    final store = ref.read(deckStoreProvider);
    final repo = ref.read(cardRepoProvider);
    final mine = store.getDeck(_myDeck!);
    final theirs = store.getDeck(_botDeck!);
    if (repo == null || mine == null || theirs == null) return;
    final commander = mine.format == 'commander' && theirs.format == 'commander';
    if (commander && (mine.count(Board.command) == 0 || theirs.count(Board.command) == 0)) {
      _snack(tr('Em Commander, os dois decks precisam de um comandante.'));
      return;
    }
    final player = ref.read(playerNameProvider);
    final seats = [
      watch
          ? ForgeSeat(name: tr('Bot 1'), deck: mine, bot: BotLevel.normal)
          : ForgeSeat(name: player.isEmpty ? tr('Jogador') : player, deck: mine),
      ForgeSeat(name: tr('Bot ({v})', {'v': _level.label}), deck: theirs, bot: _level),
    ];
    setState(() => _busy = true);
    try {
      await ForgeEngine.init();
      final missing = await ForgeEngine.checkDecks(seats, repo);
      if (!mounted) return;
      final all = {...missing[0], ...missing[1]}.toList()..sort();
      if (all.isNotEmpty && !await _confirmMissing(all)) return;
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => BotTableScreen(seats: seats, commander: commander),
      ));
    } on Exception catch (e) {
      _snack(tr('Não foi possível arrancar o bot: {v}', {'v': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmMissing(List<String> names) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Cartas que o bot ainda não conhece')),
        content: SingleChildScrollView(
          child: Text(
            '${tr('O motor do bot ainda não sabe jogar estas cartas, por isso ficam de fora da partida:')}\n\n'
            '${names.join('\n')}',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Jogar sem elas'))),
        ],
      ),
    );
    return ok ?? false;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).decks.where((d) => d.playableCount > 0).toList();
    final theme = Theme.of(context);
    DropdownButtonFormField<int> deckField(String label, int? value, ValueChanged<int?> onChanged) =>
        DropdownButtonFormField<int>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final d in decks)
              DropdownMenuItem(
                value: d.id,
                child: Text('${d.name} · ${GameFormat.byId(d.format).label}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        );
    return Scaffold(
      appBar: AppBar(title: Text(tr('Jogar contra o bot'))),
      body: Column(children: [
        Expanded(
          child: MaxWidth(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text(
                tr('Uma partida 1 contra 1 com as regras completas: o bot é o motor do Forge, que aplica as regras e joga sozinho. Funciona sem internet.'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              deckField(tr('O teu deck'), _myDeck, (v) => setState(() => _myDeck = v)),
              const SizedBox(height: 12),
              deckField(tr('O deck do bot'), _botDeck, (v) => setState(() => _botDeck = v)),
              const SizedBox(height: 20),
              Text(tr('Dificuldade'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<BotLevel>(
                // sem o visto: em ecrãs pequenos parte "Normal" em duas linhas
                showSelectedIcon: false,
                segments: [for (final l in BotLevel.values) ButtonSegment(value: l, label: Text(l.label))],
                selected: {_level},
                onSelectionChanged: (s) => setState(() => _level = s.first),
              ),
              const SizedBox(height: 8),
              Text(switch (_level) {
                BotLevel.easy => tr('Comete erros de propósito: às vezes não joga o que podia, ataca com menos criaturas ou esquece-se de bloquear.'),
                BotLevel.normal => tr('O bot do Forge tal como é: joga bem, sem batota.'),
                BotLevel.hard => tr('Pensa mais em cada jogada e tem baralhamentos que lhe dão melhor mana.'),
              }, style: theme.textTheme.bodySmall),
              if (decks.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(tr('Cria primeiro um deck.'), style: theme.textTheme.bodySmall),
                ),
            ]),
          ),
        ),
        BottomActions(children: [
          OutlinedButton.icon(
            onPressed: _busy || _myDeck == null || _botDeck == null ? null : () => _start(watch: true),
            icon: const Icon(Icons.visibility_outlined),
            label: Text(tr('Ver o bot a jogar')),
          ),
          FilledButton.icon(
            onPressed: _busy || _myDeck == null || _botDeck == null ? null : _start,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_busy ? tr('A preparar o bot…') : tr('Jogar')),
          ),
        ]),
      ]),
    );
  }
}
