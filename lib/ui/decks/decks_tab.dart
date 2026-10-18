import 'package:card_db/card_db.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/material.dart' as m show Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/backup_actions.dart';
import '../../data/providers.dart';
import '../cards/cards_tab.dart';
import '../widgets/card_view.dart';
import '../widgets/mana.dart';
import '../widgets/responsive.dart';
import 'deck_editor_screen.dart';
import 'deck_import_screen.dart';

class DecksTab extends ConsumerWidget {
  const DecksTab({super.key, required this.onOpenData});

  final VoidCallback onOpenData;

  Future<void> _newDeck(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const DeckSettingsDialog(),
    );
    if (result == null || !context.mounted) return;
    final deck = ref.read(decksProvider).save(Deck(name: result.$1, format: result.$2));
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DeckEditorScreen(deckId: deck.id!),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(cardDataProvider);
    final decks = ref.watch(decksProvider).decks;
    final repo = ref.watch(cardRepoProvider);
    ref.watch(printsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Decks')),
      floatingActionButton: data.hasData
          ? FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: const Text('Novo deck'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _newDeck(context, ref);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.content_paste),
                      title: const Text('Importar lista'),
                      subtitle: const Text('Moxfield, Archidekt, MTGO, Arena'),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const DeckImportScreen(),
                        ));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.file_open_outlined),
                      title: const Text('Importar ficheiro do EDHere'),
                      subtitle: const Text('Um deck ou backup que exportaste ou te enviaram'),
                      onTap: () {
                        Navigator.pop(ctx);
                        importBackupFile(context, ref);
                      },
                    ),
                  ]),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Deck'),
            )
          : null,
      body: !data.hasData
          ? NoDataMessage(onOpenData: onOpenData)
          : decks.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.style_outlined, size: 56, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text('Ainda não tens decks', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 6),
                      const Text(
                          'Cola a lista de um deck do Moxfield, Archidekt ou Arena, ou começa um do zero.',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const DeckImportScreen(),
                        )),
                        icon: const Icon(Icons.content_paste),
                        label: const Text('Importar lista'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _newDeck(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Novo deck'),
                      ),
                    ]),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  // Telemóvel: uma coluna. Tablet: várias.
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: isWide(context) ? 560 : 10000,
                    mainAxisExtent: 124,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: decks.length,
                  itemBuilder: (context, i) {
                    final d = decks[i];
                    final format = GameFormat.byId(d.format);
                    final cmdIds = d.inBoard(Board.command).map((e) => e.oracleId).toList();
                    final cmds = repo?.getMany(cmdIds).values.toList() ?? const [];
                    final identity = cmds.fold(0, (m, c) => m | c.identityMask);
                    return m.Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => DeckEditorScreen(deckId: d.id!),
                        )),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            SizedBox(
                              width: 48,
                              child: cmds.isEmpty
                                  ? AspectRatio(
                                      aspectRatio: cardAspect,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Icon(Icons.style, color: theme.colorScheme.primary),
                                      ),
                                    )
                                  : CardImage(
                                      ref.read(printsProvider).resolve(cmds.first,
                                          printId: d.inBoard(Board.command).first.printId),
                                      radius: 4),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(d.name,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(
                                  '${format.label} · ${format.hasCommandZone ? d.playableCount : d.count(Board.main)} cartas'
                                  '${cmds.isEmpty ? '' : ' · ${cmds.map((c) => c.frontName).join(' + ')}'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                                if (cmds.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  ColorIdentity(identity),
                                ],
                              ]),
                            ),
                            const Icon(Icons.chevron_right),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

/// Nome e formato de um deck (criar ou editar).
class DeckSettingsDialog extends StatefulWidget {
  const DeckSettingsDialog({super.key, this.name = '', this.format = 'commander', this.title = 'Novo deck'});

  final String name;
  final String format;
  final String title;

  @override
  State<DeckSettingsDialog> createState() => _DeckSettingsDialogState();
}

class _DeckSettingsDialogState extends State<DeckSettingsDialog> {
  late final _name = TextEditingController(text: widget.name);
  late String _format = widget.format;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _name,
          autofocus: widget.name.isEmpty,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nome'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _format,
          decoration: const InputDecoration(labelText: 'Formato'),
          items: [
            for (final f in GameFormat.all) DropdownMenuItem(value: f.id, child: Text(f.label)),
          ],
          onChanged: (v) => setState(() => _format = v ?? _format),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(
          onPressed: () => Navigator.pop(
              context, (_name.text.trim().isEmpty ? 'Deck sem nome' : _name.text.trim(), _format)),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
