import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../widgets/card_view.dart';
import '../widgets/set_symbol.dart';
import '../widgets/responsive.dart';

/// Resultado do seletor: uma versão, ou [isDefault] para voltar à por defeito.
class VersionChoice {
  const VersionChoice(this.print) : isDefault = false;
  const VersionChoice.byDefault()
      : print = null,
        isDefault = true;
  final db.PrintInfo? print;
  final bool isDefault;
}

/// Miniatura de uma versão: a imagem local se já existir, senão da rede.
class VersionThumb extends ConsumerWidget {
  const VersionThumb({super.key, required this.base, required this.print, this.selected = false});

  final db.Card base;
  final db.PrintInfo print;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final images = ref.watch(imagesProvider);
    final card = base.withPrint(print);
    final key = db.ImageRef.keyFor(card);
    final local = images.best(key);
    final url = print.imgSmall ?? (print.faces.isNotEmpty ? print.faces.first.imgSmall : null);
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Expanded(
        child: AspectRatio(
          aspectRatio: cardAspect,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: local != null
                  ? Image.file(local, fit: BoxFit.cover)
                  : url != null
                      ? Image.network(url,
                          fit: BoxFit.cover,
                          headers: const {'User-Agent': 'EDHere/0.1'},
                          errorBuilder: (_, __, ___) => TextCard(card))
                      : TextCard(card),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (print.setCode.isNotEmpty) ...[
          SetSymbol(print.setCode, rarity: print.rarity, size: 13),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(print.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? scheme.primary : null)),
        ),
      ]),
    ]);
  }
}

/// Grelha com todas as versões de uma carta, para escolher uma.
Future<VersionChoice?> showVersionPicker(BuildContext context, db.Card base,
    {String? current, String title = 'Escolher versão'}) {
  return showModalBottomSheet<VersionChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.85,
      child: Consumer(builder: (ctx, ref, _) {
        final prints = ref.read(printsProvider);
        return FutureBuilder(
          future: prints.versions(base.oracleId),
          builder: (ctx, snap) {
            final theme = Theme.of(ctx);
            final list = snap.data?.prints ?? const <db.PrintInfo>[];
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(children: [
                  Expanded(child: Text('$title · ${base.name}', style: theme.textTheme.titleMedium)),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, const VersionChoice.byDefault()),
                    child: const Text('Por defeito'),
                  ),
                ]),
              ),
              if (snap.connectionState != ConnectionState.done)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (list.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        snap.data?.offline == true
                            ? 'Sem ligação. Liga-te à internet para ver as versões desta carta.'
                            : 'Não há outras versões.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else ...[
                if (snap.data?.offline == true)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Sem ligação: só as versões já vistas antes.'),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('${list.length} versões',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cardColumns(MediaQuery.of(ctx).size.width, target: 170),
                      childAspectRatio: cardAspect * 0.86,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: list.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => Navigator.pop(ctx, VersionChoice(list[i])),
                      child: VersionThumb(
                        base: base,
                        print: list[i],
                        selected: list[i].printId == (current ?? base.printId),
                      ),
                    ),
                  ),
                ),
              ],
            ]);
          },
        );
      }),
    ),
  );
}
