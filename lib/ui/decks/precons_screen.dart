import 'package:card_db/card_db.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/material.dart' as m show Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/precons.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../widgets/card_view.dart';
import '../widgets/mana.dart';
import '../widgets/responsive.dart';

/// Decks base que vêm com a app: para quem acabou de instalar poder jogar
/// logo, em Commander ou num formato de 60 cartas.
class PreconsScreen extends ConsumerStatefulWidget {
  const PreconsScreen({super.key});

  @override
  ConsumerState<PreconsScreen> createState() => _PreconsScreenState();
}

class _PreconsScreenState extends ConsumerState<PreconsScreen> {
  late final Set<String> _have = {for (final d in ref.read(decksProvider).decks) d.name};
  late final Set<String> _picked = {
    for (final p in precons)
      if (!_have.contains(p.name)) p.id
  };
  bool _busy = false;

  Future<void> _import() async {
    final repo = ref.read(cardRepoProvider)!;
    setState(() => _busy = true);
    var done = 0;
    final missing = <String>[];
    final cards = <Card>[];
    for (final p in precons.where((p) => _picked.contains(p.id))) {
      final format = GameFormat.byId(p.format);
      final r = resolveDeckText(parseDeckText(await p.load(), hasCommandZone: format.hasCommandZone), repo.findByName);
      if (r.entries.isEmpty) continue;
      // Uma carta que ainda não está nos dados do telemóvel (coleção muito
      // recente): fica nas notas, como na importação de listas.
      final notes = r.unresolved.isEmpty
          ? ''
          : tr('Não encontradas na importação:\n{v}', {'v': r.unresolved.map((l) => '${l.qty} ${l.name}').join('\n')});
      if (r.unresolved.isNotEmpty) missing.add(p.name);
      ref.read(decksProvider).save(Deck(name: p.name, format: p.format, entries: r.entries, notes: notes));
      cards.addAll(repo.getMany(r.entries.map((e) => e.oracleId)).values);
      done++;
    }
    // As imagens pequenas vêm já, em segundo plano: sem elas a mesa só mostra
    // molduras (e na sala ninguém as tem para partilhar).
    final prints = ref.read(printsProvider);
    ref
        .read(imagesProvider)
        .ensureRefs(cards.expand((c) => ImageRef.allOf(prints.resolve(c))), sizes: const ['small'])
        .ignore();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text(missing.isNotEmpty
          ? tr('{n} decks importados. Faltam cartas em {v}: atualiza os dados das cartas em Definições.',
              {'n': done, 'v': missing.join(', ')})
          : done == 1
              ? tr('1 deck importado.')
              : tr('{n} decks importados.', {'n': done})),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(cardRepoProvider);
    final prints = ref.read(printsProvider);
    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );
    Widget tile(Precon p) {
      final face = repo?.findByName(p.face);
      final have = _have.contains(p.name);
      final on = _picked.contains(p.id);
      return m.Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 8),
        child: CheckboxListTile(
          value: on,
          onChanged: _busy ? null : (v) => setState(() => v! ? _picked.add(p.id) : _picked.remove(p.id)),
          contentPadding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          secondary: SizedBox(
            width: 56,
            child: face == null
                ? Icon(Icons.style_outlined, color: theme.colorScheme.primary)
                : CardImage(prints.resolve(face)),
          ),
          title: Text(p.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 2),
            Row(children: [
              if (face != null) ...[ColorIdentity(face.identityMask), const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  have ? tr('{v} · já tens este deck', {'v': GameFormat.byId(p.format).label}) : GameFormat.byId(p.format).label,
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(p.about),
          ]),
        ),
      );
    }

    final n = _picked.length;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Decks base'))),
      body: Column(children: [
        Expanded(
          child: MaxWidth(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
              Text(
                tr('Decks prontos a jogar, para começares já. Ficam nos teus decks e podes mudá-los à vontade.'),
                style: theme.textTheme.bodyMedium,
              ),
              section(tr('Commander (100 cartas) · Foundations Commander')),
              for (final p in precons.where((p) => p.format == 'commander')) tile(p),
              section(tr('60 cartas · Modern')),
              for (final p in precons.where((p) => p.format != 'commander')) tile(p),
            ]),
          ),
        ),
        BottomActions(children: [
          FilledButton.icon(
            onPressed: n == 0 || _busy || repo == null ? null : _import,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_done),
            label: Text(n == 1 ? tr('Importar 1 deck') : tr('Importar {n} decks', {'n': n})),
          ),
        ]),
      ]),
    );
  }
}
