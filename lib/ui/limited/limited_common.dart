import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/booster_service.dart';
import '../../data/image_service.dart';
import '../../data/providers.dart';
import '../cards/card_detail_screen.dart';
import '../widgets/card_view.dart';
import '../widgets/responsive.dart';
import '../../l10n/l10n.dart';

/// Uma carta de um booster já com a carta da base e a arte certa.
class PoolCard {
  PoolCard(this.pack, this.base, this.shown);
  final db.PackCard pack;
  final db.Card base;

  /// A carta com a impressão do booster (a arte que saiu).
  final db.Card shown;

  db.BoosterPrint get print => pack.print;
  bool get foil => pack.foil;

  /// A impressão a guardar no deck (null se for a por defeito da base).
  String? get printId => print.scryfallId == base.printId ? null : print.scryfallId;
}

/// Junta a carta da base a cada carta dos boosters e guarda as impressões
/// (para a arte continuar a aparecer no deck, mesmo offline).
List<PoolCard> resolvePool(WidgetRef ref, Iterable<db.PackCard> cards) {
  final repo = ref.read(cardRepoProvider)!;
  final prints = ref.read(printsProvider);
  final out = <PoolCard>[];
  final infos = <db.PrintInfo>[];
  for (final p in cards) {
    final base = repo.get(p.print.oracleId);
    if (base == null) continue;
    if (p.print.scryfallId.isEmpty || p.print.scryfallId == base.printId) {
      out.add(PoolCard(p, base, base));
      continue;
    }
    final info = p.print.printInfo(base);
    infos.add(info);
    out.add(PoolCard(p, base, base.withPrint(info)));
  }
  // Guardar as impressões avisa outros ecrãs: fica para depois deste build.
  final images = ref.read(imagesProvider);
  Future.microtask(() {
    if (infos.isNotEmpty) prints.remember(infos);
    // Imagens pequenas destas cartas (em silêncio, se houver rede).
    images.ensureRefs(out.expand((c) => db.ImageRef.allOf(c.shown)), sizes: const ['small']);
  });
  return out;
}

Color rarityColor(String r) => switch (r) {
      'M' => const Color(0xFFE8622A),
      'R' => const Color(0xFFD4AF37),
      'U' => const Color(0xFF9FB4C7),
      _ => Colors.transparent,
    };

/// Carta de um booster numa grelha: arte, contorno da raridade e foil.
/// Toque longo abre a carta em grande.
class PoolCardView extends StatelessWidget {
  const PoolCardView({super.key, required this.card, this.onTap, this.dimmed = false, this.qty = 1});

  final PoolCard card;
  final VoidCallback? onTap;
  final bool dimmed;
  final int qty;

  @override
  Widget build(BuildContext context) {
    final border = rarityColor(card.print.rarity);
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CardDetailScreen(card: card.shown),
      )),
      child: Opacity(
        opacity: dimmed ? 0.35 : 1,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: border, width: border == Colors.transparent ? 0 : 2),
          ),
          child: Stack(children: [
            CardImage(card.shown, radius: 7),
            if (card.foil)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.pinkAccent.withOpacity(0.18),
                          Colors.cyanAccent.withOpacity(0.08),
                          Colors.yellowAccent.withOpacity(0.18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (card.foil)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.auto_awesome, size: 16, color: Colors.white),
              ),
            if (qty > 1)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(8)),
                  child: Text('×$qty',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Grelha de cartas de booster que se adapta à largura.
class PoolGrid extends StatelessWidget {
  const PoolGrid({super.key, required this.children, this.target = 120});
  final List<Widget> children;
  final double target;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          crossAxisCount: cardColumns(box.maxWidth, target: target, min: 3, max: 10),
          childAspectRatio: cardAspect * 0.97,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: children,
        ),
      );
}

String shortDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// Ordem para mostrar um booster aberto: comuns primeiro, a rara no fim
/// (como quando se abre um booster a sério).
int revealRank(db.PackCard c) => switch (c.print.rarity) {
      'M' => 4,
      'R' => 3,
      'S' => 3,
      'U' => 1,
      _ => c.foil ? 2 : 0,
    };

/// Descarregar antes as imagens de um set (para abrir boosters sem rede).
class SetImagesTile extends ConsumerStatefulWidget {
  const SetImagesTile({super.key, required this.set});
  final db.BoosterSetInfo set;

  @override
  ConsumerState<SetImagesTile> createState() => _SetImagesTileState();
}

class _SetImagesTileState extends ConsumerState<SetImagesTile> {
  List<db.ImageRef>? _refs;
  String? _loadedFor;

  Future<void> _load() async {
    final code = widget.set.code;
    _loadedFor = code;
    final boosters = await ref.read(boosterServiceProvider).set(widget.set);
    final repo = ref.read(cardRepoProvider);
    if (repo == null || !mounted || _loadedFor != code) return;
    final seen = <String>{};
    final refs = <db.ImageRef>[];
    for (final p in boosters.prints) {
      final base = repo.get(p.oracleId);
      if (base == null) continue;
      final shown =
          p.scryfallId.isEmpty || p.scryfallId == base.printId ? base : base.withPrint(p.printInfo(base));
      for (final r in db.ImageRef.allOf(shown)) {
        if (seen.add(r.key)) refs.add(r);
      }
    }
    setState(() => _refs = refs);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadedFor != widget.set.code) {
      _refs = null;
      _load();
    }
    final images = ref.watch(imagesProvider);
    final refs = _refs;
    final job = images.job;
    final running = job != null && job.pack.id == 'set_${widget.set.code}';
    final missing = refs?.where((r) => !images.has('small', r.key)).length;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: const Icon(Icons.download_for_offline_outlined),
        title: Text(refs == null
            ? tr('Imagens do set…')
            : missing == 0
                ? tr('Imagens do set já estão offline')
                : tr('Imagens offline: {v} de {n}', {'v': refs.length - missing!, 'n': refs.length})),
        subtitle: running
            ? LinearProgressIndicator(value: job.total == 0 ? null : job.done / job.total)
            : Text(
                missing == null || missing == 0
                    ? tr('Os boosters abrem com arte mesmo sem rede.')
                    : tr('Descarrega agora (cerca de {v} MB) para abrir os boosters sem rede.',
                        {'v': (missing * avgImageBytes['small']! / 1048576).ceil()}),
                style: theme.textTheme.bodySmall),
        trailing: refs == null || missing == 0 || running
            ? null
            : IconButton(
                tooltip: tr('Descarregar'),
                icon: const Icon(Icons.download),
                onPressed: job != null
                    ? null
                    : () => images.download(
                        ImagePack('set_${widget.set.code}', widget.set.name, tr('Imagens do set'), null),
                        'small',
                        refs),
              ),
      ),
    );
  }
}
