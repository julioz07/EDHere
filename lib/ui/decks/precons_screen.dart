import 'package:card_db/card_db.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/material.dart' as m show Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/precons.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../widgets/card_art.dart';
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
        .ensureRefs(cards.expand((c) => ImageRef.allOf(prints.resolve(c))), sizes: const ['small']).ignore();
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
      void toggle() => setState(() => on ? _picked.remove(p.id) : _picked.add(p.id));
      return m.Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: on ? theme.colorScheme.primary : Colors.transparent, width: 2),
        ),
        child: InkWell(
          onTap: _busy ? null : toggle,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 120,
              child: ArtBanner.card(
                face == null ? null : prints.resolve(face),
                scrim: ArtScrim.bottom,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      _Chip(GameFormat.byId(p.format).label),
                      if (face != null) ...[const SizedBox(width: 8), ColorIdentity(face.identityMask)],
                      const Spacer(),
                      Checkbox(
                        value: on,
                        side: const BorderSide(color: Colors.white, width: 2),
                        onChanged: _busy ? null : (_) => toggle(),
                      ),
                    ]),
                    const Spacer(),
                    // à direita, em baixo, fica o crédito da ilustração
                    Padding(
                      padding: const EdgeInsets.only(right: 96),
                      child: Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (face != null)
                  Text(face.displayFrontName, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(p.about, style: theme.textTheme.bodyMedium),
                if (have) ...[
                  const SizedBox(height: 4),
                  Text(tr('Já tens este deck'),
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ]),
            ),
          ]),
        ),
      );
    }

    // No tablet, em grelha (2 ou 3 por linha, com a mesma altura por linha).
    final cols = MediaQuery.sizeOf(context).width >= 1200
        ? 3
        : isWide(context)
            ? 2
            : 1;
    List<Widget> grid(Iterable<Precon> list) {
      final tiles = [for (final p in list) tile(p)];
      if (cols == 1) return tiles;
      return [
        for (var i = 0; i < tiles.length; i += cols)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var j = i; j < i + cols; j++) ...[
                if (j > i) const SizedBox(width: 12),
                Expanded(child: j < tiles.length ? tiles[j] : const SizedBox.shrink()),
              ],
            ]),
          ),
      ];
    }

    final n = _picked.length;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Decks base'))),
      body: Column(children: [
        Expanded(
          child: MaxWidth(
            max: cols == 1 ? 760 : 380.0 * cols,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
              Text(
                tr('Decks prontos a jogar, para começares já. Ficam nos teus decks e podes mudá-los à vontade.'),
                style: theme.textTheme.bodyMedium,
              ),
              section(tr('Commander (100 cartas) · Foundations Commander')),
              ...grid(precons.where((p) => p.format == 'commander')),
              section(tr('60 cartas · Modern')),
              ...grid(precons.where((p) => p.format != 'commander')),
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

/// Etiqueta pequena por cima da ilustração (o formato).
class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(text.toUpperCase(),
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      );
}
