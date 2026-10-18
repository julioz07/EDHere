import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/card_data_service.dart';
import '../../data/collection.dart';
import '../../data/providers.dart';
import 'card_detail_screen.dart';
import 'card_search.dart';
import 'collection_import_screen.dart';

/// Cartas: pesquisa em toda a base e "As minhas cartas" (a coleção).
class CardsTab extends ConsumerWidget {
  const CardsTab({super.key, required this.onOpenData});

  final VoidCallback onOpenData;

  void _open(BuildContext context, card) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CardDetailScreen(card: card)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(cardDataProvider);
    final collection = ref.watch(collectionProvider);
    if (!data.hasData) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cartas')),
        body: NoDataMessage(onOpenData: onOpenData),
      );
    }
    final total = collection.owned.values.fold(0, (a, b) => a + b);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cartas'),
          actions: [
            IconButton(
              tooltip: 'Importar para as minhas cartas',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => const CollectionImportScreen())),
            ),
          ],
          bottom: TabBar(tabs: [
            const Tab(icon: Icon(Icons.search), text: 'Pesquisa'),
            Tab(
              icon: const Icon(Icons.inventory_2_outlined),
              text: collection.isEmpty ? 'As minhas cartas' : 'As minhas cartas ($total)',
            ),
          ]),
        ),
        body: TabBarView(children: [
          CardSearchView(onTap: (c) => _open(context, c)),
          collection.isEmpty
              ? const _EmptyCollection()
              : CardSearchView(
                  onlyOwned: true,
                  hint: 'Filtrar as minhas cartas (t:creature, id:rg…)',
                  onTap: (c) => _open(context, c),
                ),
        ]),
      ),
    );
  }
}

class _EmptyCollection extends StatelessWidget {
  const _EmptyCollection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inventory_2_outlined, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Ainda não tens cartas aqui', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Junta as cartas que tens para criares decks só com elas. É só indicativo: '
            'não é um inventário. Podes importar do ManaBox, Moxfield, Deckbox ou de uma '
            'lista de texto, ou usar "Tenho esta carta" na ficha de cada carta.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const CollectionImportScreen())),
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Importar lista'),
          ),
        ]),
      ),
    );
  }
}

/// Mostrado quando ainda não há base de cartas no telemóvel. O botão começa
/// logo a descarga (com rulings) e mostra o progresso aqui mesmo.
class NoDataMessage extends ConsumerWidget {
  const NoDataMessage({super.key, required this.onOpenData});

  /// Opções avançadas (pacotes de imagens, rulings...).
  final VoidCallback onOpenData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final data = ref.watch(cardDataProvider);
    // A verificação diária de novidades não conta: só a descarga a sério.
    final busy = data.phase == DataPhase.downloading || data.phase == DataPhase.importing;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_download_outlined, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(busy ? 'A preparar as cartas…' : 'Ainda não há cartas offline',
                style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              busy
                  ? 'Podes continuar a usar a app: a descarga continua sozinha.'
                  : 'Descarrega a base de cartas uma vez (cerca de 30 MB). Depois a pesquisa, os '
                      'decks e os jogos funcionam sem internet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (busy) ...[
              LinearProgressIndicator(
                  value: data.progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
              const SizedBox(height: 8),
              Text(data.message, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
              TextButton(onPressed: data.cancel, child: const Text('Cancelar')),
            ] else ...[
              if (data.phase == DataPhase.error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(data.message,
                      style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
                ),
              FilledButton.icon(
                onPressed: () => data.update(includeRulings: true),
                icon: const Icon(Icons.download),
                label: const Text('Descarregar cartas'),
              ),
              TextButton(onPressed: onOpenData, child: const Text('Opções de dados')),
            ],
          ]),
        ),
      ),
    );
  }
}
