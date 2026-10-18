import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import 'cards/cards_tab.dart';
import 'data/data_tab.dart';
import 'settings/settings_tab.dart';
import 'decks/decks_tab.dart';
import 'play/play_tab.dart';
import 'widgets/responsive.dart';

/// Estrutura principal: Cartas, Decks, Jogar e Definições.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late int _tab = ref.read(cardDataProvider).hasData ? 1 : 0;

  @override
  void initState() {
    super.initState();
    // Verifica novidades no máximo uma vez por dia, se houver rede.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = ref.read(deckStoreProvider);
      final last = int.tryParse(store.setting('last_bulk_check') ?? '') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last > const Duration(days: 1).inMilliseconds) {
        store.setSetting('last_bulk_check', '$now');
        ref.read(cardDataProvider).checkRemote();
      }
    });
  }

  void _go(int i) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _tab = i);
  }

  void _openData() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DataTab()));

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(cardDataProvider);
    final settingsIcon = Badge(
      isLabelVisible: data.updateAvailable || !data.hasData,
      child: const Icon(Icons.settings_outlined),
    );
    final body = IndexedStack(
      index: _tab,
      children: [
        CardsTab(onOpenData: _openData),
        DecksTab(onOpenData: _openData),
        const PlayTab(),
        const SettingsTab(),
      ],
    );
    // Em tablet a navegação passa para uma barra lateral, para não roubar altura.
    if (isWide(context)) {
      return Scaffold(
        body: Row(children: [
          SafeArea(
            right: false,
            child: NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.6,
              destinations: [
                const NavigationRailDestination(icon: Icon(Icons.search), label: Text('Cartas')),
                const NavigationRailDestination(icon: Icon(Icons.style_outlined), label: Text('Decks')),
                const NavigationRailDestination(
                    icon: Icon(Icons.table_restaurant_outlined), label: Text('Jogar')),
                NavigationRailDestination(icon: settingsIcon, label: const Text('Definições')),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.search), label: 'Cartas'),
          const NavigationDestination(icon: Icon(Icons.style_outlined), label: 'Decks'),
          const NavigationDestination(icon: Icon(Icons.table_restaurant_outlined), label: 'Jogar'),
          NavigationDestination(icon: settingsIcon, label: 'Definições'),
        ],
      ),
    );
  }
}
