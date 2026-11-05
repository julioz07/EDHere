import 'package:card_db/card_db.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/material.dart' as m show Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/backup_actions.dart';
import '../../data/providers.dart';
import '../cards/cards_tab.dart';
import '../widgets/card_art.dart';
import '../widgets/mana.dart';
import '../widgets/responsive.dart';
import 'deck_editor_screen.dart';
import 'deck_import_screen.dart';
import 'precons_screen.dart';
import '../../l10n/l10n.dart';
import '../widgets/empty_state.dart';

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
      appBar: AppBar(title: Text(tr('Decks'))),
      floatingActionButton: data.hasData
          ? FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: Text(tr('Novo deck')),
                      onTap: () {
                        Navigator.pop(ctx);
                        _newDeck(context, ref);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(tr('Decks base')),
                      subtitle: Text(tr('Decks prontos a jogar, em Commander e Modern')),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PreconsScreen()));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.content_paste),
                      title: Text(tr('Importar lista')),
                      subtitle: Text(tr('Moxfield, Archidekt, MTGO, Arena')),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const DeckImportScreen(),
                        ));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.file_open_outlined),
                      title: Text(tr('Importar ficheiro do EDHere')),
                      subtitle: Text(tr('Um deck ou backup que exportaste ou te enviaram')),
                      onTap: () {
                        Navigator.pop(ctx);
                        importBackupFile(context, ref);
                      },
                    ),
                  ]),
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text(tr('Deck')),
            )
          : null,
      body: !data.hasData
          ? NoDataMessage(onOpenData: onOpenData)
          : decks.isEmpty
              ? EmptyState(
                  icon: Icons.style_outlined,
                  title: tr('Ainda não tens decks'),
                  body: tr(
                      'Começa com um dos decks base, prontos a jogar, cola a lista de um deck do Moxfield, Archidekt ou Arena, ou começa um do zero.'),
                  actions: [
                    FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PreconsScreen())),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text(tr('Decks base')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const DeckImportScreen(),
                      )),
                      icon: const Icon(Icons.content_paste),
                      label: Text(tr('Importar lista')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _newDeck(context, ref),
                      icon: const Icon(Icons.add),
                      label: Text(tr('Novo deck')),
                    ),
                  ],
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  // Telemóvel: uma coluna. Tablet: várias.
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    // no tablet, três colunas: duas deixavam dois terços do ecrã vazios
                    maxCrossAxisExtent: isWide(context) ? 420 : 10000,
                    mainAxisExtent: 132,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: decks.length,
                  itemBuilder: (context, i) {
                    final d = decks[i];
                    final format = GameFormat.byId(d.format);
                    final (:cover, :commanders, :identity) = deckCover(d, repo, ref.read(printsProvider));
                    const white = Colors.white;
                    return m.Card(
                      clipBehavior: Clip.antiAlias,
                      margin: EdgeInsets.zero,
                      child: ArtBanner.card(
                        cover,
                        identity: identity,
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => DeckEditorScreen(deckId: d.id!),
                            )),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
                              child: Row(children: [
                                Expanded(
                                  child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(d.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleLarge
                                                ?.copyWith(fontWeight: FontWeight.w800, color: white, height: 1.15)),
                                        const SizedBox(height: 2),
                                        Text(
                                          tr('{v} · {v2} cartas{v3}', {
                                            'v': format.label,
                                            'v2': format.hasCommandZone ? d.playableCount : d.count(Board.main),
                                            'v3': commanders.isEmpty
                                                ? ''
                                                : ' · ${commanders.map((c) => c.displayFrontName).join(' + ')}'
                                          }),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                                        ),
                                        if (identity != 0) ...[
                                          const SizedBox(height: 6),
                                          ColorIdentity(identity),
                                        ],
                                      ]),
                                ),
                                const Icon(Icons.chevron_right, color: Colors.white70),
                              ]),
                            ),
                          ),
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
  const DeckSettingsDialog({super.key, this.name = '', this.format = 'commander', this.title});

  final String name;
  final String format;
  final String? title;

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
      title: Text(widget.title ?? tr('Novo deck')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _name,
          autofocus: widget.name.isEmpty,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Nome')),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _format,
          decoration: InputDecoration(labelText: tr('Formato')),
          items: [
            for (final f in GameFormat.all) DropdownMenuItem(value: f.id, child: Text(f.label)),
          ],
          onChanged: (v) => setState(() => _format = v ?? _format),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancelar'))),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, (_name.text.trim().isEmpty ? tr('Deck sem nome') : _name.text.trim(), _format)),
          child: Text(tr('Guardar')),
        ),
      ],
    );
  }
}
