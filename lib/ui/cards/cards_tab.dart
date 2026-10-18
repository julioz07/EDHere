import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'card_detail_screen.dart';
import 'card_search.dart';

class CardsTab extends ConsumerWidget {
  const CardsTab({super.key, required this.onOpenData});

  final VoidCallback onOpenData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(cardDataProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cartas')),
      body: data.hasData
          ? CardSearchView(
              onTap: (c) => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => CardDetailScreen(card: c),
              )),
            )
          : NoDataMessage(onOpenData: onOpenData),
    );
  }
}

/// Mostrado quando ainda não há base de cartas no telemóvel.
class NoDataMessage extends StatelessWidget {
  const NoDataMessage({super.key, required this.onOpenData});

  final VoidCallback onOpenData;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_download_outlined, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Ainda não há cartas offline', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Descarrega a base de cartas uma vez (cerca de 25 MB). Depois a pesquisa e '
            'os decks funcionam sem internet.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onOpenData, child: const Text('Descarregar cartas')),
        ]),
      ),
    );
  }
}
