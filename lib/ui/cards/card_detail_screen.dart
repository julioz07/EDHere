import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/providers.dart';
import '../widgets/card_view.dart';
import '../widgets/mana.dart';
import 'versions.dart';

const _formatLabels = {
  'commander': 'Commander',
  'brawl': 'Brawl',
  'standardbrawl': 'Std. Brawl',
  'oathbreaker': 'Oathbreaker',
  'paupercommander': 'Pauper EDH',
  'standard': 'Standard',
  'pioneer': 'Pioneer',
  'modern': 'Modern',
  'legacy': 'Legacy',
  'vintage': 'Vintage',
  'pauper': 'Pauper',
  'premodern': 'Premodern',
};

/// Ficha da carta: imagem (ou carta de texto), texto Oracle, legalidades e
/// rulings. Mostra o artista e o copyright, como o Scryfall exige.
class CardDetailScreen extends ConsumerStatefulWidget {
  const CardDetailScreen({
    super.key,
    required this.card,
    this.actions = const [],
    this.deckPrintId,
    this.onDeckPrint,
  });

  /// A carta (com qualquer impressão; a ficha resolve a versão a mostrar).
  final db.Card card;

  /// Botões extra (ex.: "Juntar ao deck").
  final List<Widget> actions;

  /// Aberta a partir de um deck: a versão dessa entrada e como a mudar.
  final String? deckPrintId;
  final Future<void> Function(db.PrintInfo? print)? onDeckPrint;

  @override
  ConsumerState<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends ConsumerState<CardDetailScreen> {
  int _face = 0;
  late String? _deckPrint = widget.deckPrintId;
  int? _versionCount;

  /// A carta base (impressão por defeito), vinda da base local.
  db.Card get _base => ref.read(cardRepoProvider)?.get(widget.card.oracleId) ?? widget.card;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Garante a imagem grande da versão mostrada, se houver rede.
      ref.read(imagesProvider).ensure([_shown()]);
      final v = await ref.read(printsProvider).versions(widget.card.oracleId);
      if (mounted && !v.offline) setState(() => _versionCount = v.prints.length);
    });
  }

  db.Card _shown() => ref.read(printsProvider).resolve(_base, printId: _deckPrint);

  Future<void> _chooseVersion() async {
    final prints = ref.read(printsProvider);
    final base = _base;
    final current = _deckPrint ?? prints.preferredFor(base.oracleId);
    final choice = await showVersionPicker(context, base, current: current ?? base.printId);
    if (choice == null || !mounted) return;
    final p = choice.print;
    final inDeck = widget.onDeckPrint != null;
    final where = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (inDeck)
            ListTile(
              leading: const Icon(Icons.style_outlined),
              title: Text(p == null ? 'Usar a versão por defeito neste deck' : 'Usar ${p.label} neste deck'),
              onTap: () => Navigator.pop(ctx, 'deck'),
            ),
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: Text(p == null ? 'Deixar de ter versão preferida' : 'Usar ${p.label} em todo o lado'),
            subtitle: const Text('Versão preferida desta carta (decks sem versão própria)'),
            onTap: () => Navigator.pop(ctx, 'global'),
          ),
        ]),
      ),
    );
    if (where == null || !mounted) return;
    if (where == 'deck') {
      await widget.onDeckPrint!(p);
      setState(() => _deckPrint = p?.printId);
      if (p != null) await prints.use(base, p);
    } else {
      await prints.setPreferred(base, p);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(printsProvider);
    final card = _shown();
    final repo = ref.watch(cardRepoProvider);
    final theme = Theme.of(context);
    final legal = repo?.legalities(card.oracleId) ?? const {};
    final rulings = repo?.rulings(card.oracleId) ?? const [];
    final faces = card.faces.isEmpty ? [null] : card.faces;
    final artist = card.faces.isNotEmpty ? (card.faces[_face].artist ?? card.artist) : card.artist;

    return Scaffold(
      appBar: AppBar(title: Text(card.name, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: CardImage(card, face: card.hasFaceImages ? _face : 0, preferNormal: true, radius: 14),
            ),
          ),
          if (card.hasFaceImages)
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _face = (_face + 1) % card.faces.length),
                icon: const Icon(Icons.flip),
                label: const Text('Virar'),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            [
              if (artist != null) 'Ilustração: $artist',
              '™ & © Wizards of the Coast',
            ].join(' · '),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Center(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _chooseVersion,
              icon: const Icon(Icons.collections_outlined),
              label: Text(_versionCount == null
                  ? 'Versões'
                  : 'Versões ($_versionCount) · ${card.setCode.toUpperCase()} #${card.collectorNumber}'),
            ),
          ),
          if (widget.actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...widget.actions,
          ],
          const SizedBox(height: 16),
          for (final f in faces) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(f?.name ?? card.name,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      ManaCost(f?.manaCost ?? card.manaCost, size: 18),
                    ]),
                    const SizedBox(height: 4),
                    Text(f?.typeLine ?? card.typeLine, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 10),
                    OracleText(f?.oracleText ?? card.oracleText,
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.35)),
                    if ((f?.power ?? card.power) != null) ...[
                      const SizedBox(height: 8),
                      Text('${f?.power ?? card.power}/${f?.toughness ?? card.toughness}',
                          style: theme.textTheme.titleSmall),
                    ],
                    if ((f?.loyalty ?? card.loyalty) != null) ...[
                      const SizedBox(height: 8),
                      Text('Lealdade ${f?.loyalty ?? card.loyalty}', style: theme.textTheme.titleSmall),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Chip(
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Identidade  '),
                ColorIdentity(card.identityMask, size: 16),
              ]),
            ),
            if (card.gameChanger) const Chip(label: Text('Game Changer')),
            Chip(label: Text('${card.setCode.toUpperCase()} · ${card.rarity}')),
          ]),
          const SizedBox(height: 16),
          Text('Legalidade', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final MapEntry(key: k, value: label) in _formatLabels.entries)
                _LegalChip(label, legal[k]),
            ],
          ),
          if (rulings.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Rulings', style: theme.textTheme.titleMedium),
            for (final r in rulings)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.publishedAt,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  OracleText(r.comment, style: theme.textTheme.bodyMedium),
                ]),
              ),
          ],
        ],
      ),
    );
  }
}

class _LegalChip extends StatelessWidget {
  const _LegalChip(this.label, this.status);
  final String label;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (status) {
      'legal' => ('Legal', EdhColors.ok),
      'banned' => ('Banida', EdhColors.bad),
      'restricted' => ('Restrita', EdhColors.warn),
      _ => ('Não', Theme.of(context).colorScheme.outline),
    };
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
