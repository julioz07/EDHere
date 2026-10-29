import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import 'cards/cards_tab.dart';
import 'data/data_tab.dart';
import 'settings/settings_tab.dart';
import 'decks/decks_tab.dart';
import 'play/play_tab.dart';
import 'resume_game.dart';
import 'widgets/responsive.dart';
import '../l10n/l10n.dart';

/// Estrutura principal: Cartas, Decks, Jogar e Definições.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.startDownload = false});

  /// Vindo da introdução: começa logo a descarregar a base de cartas.
  final bool startDownload;

  /// Separador a abrir na próxima vez (depois de mudar de língua, a app é
  /// refeita e volta às Definições).
  static int? reopenTab;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late int _tab = _takeReopen() ?? _home;

  static int? _takeReopen() {
    final t = AppShell.reopenTab;
    AppShell.reopenTab = null;
    return t;
  }

  DateTime? _backPressed;

  /// Separador de partida: Decks quando já há cartas, senão Cartas.
  int get _home => ref.read(cardDataProvider).hasData ? 1 : 0;

  @override
  void initState() {
    super.initState();
    // Verifica novidades no máximo uma vez por dia, se houver rede.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.startDownload && !ref.read(cardDataProvider).hasData) {
        ref.read(cardDataProvider).update(includeRulings: true);
        return;
      }
      final store = ref.read(deckStoreProvider);
      final last = int.tryParse(store.setting('last_bulk_check') ?? '') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last > const Duration(days: 1).inMilliseconds) {
        store.setSetting('last_bulk_check', '$now');
        ref.read(cardDataProvider).checkRemote();
      }
      // A app fechou a meio de um jogo em rede: oferece voltar.
      offerResume(context, ref);
    });
  }

  void _go(int i) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _tab = i);
  }

  /// Retroceder: primeiro volta ao separador inicial; aí, só sai com dois toques.
  void _onBack() {
    if (_tab != _home) {
      _go(_home);
      return;
    }
    final now = DateTime.now();
    if (_backPressed != null && now.difference(_backPressed!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _backPressed = now;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr('Toca outra vez em retroceder para sair.')),
      duration: const Duration(seconds: 2),
    ));
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
    final Widget page;
    if (isWide(context)) {
      page = Scaffold(
        body: Row(children: [
          SafeArea(
            right: false,
            child: NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.6,
              destinations: [
                NavigationRailDestination(icon: const Icon(Icons.search), label: Text(tr('Cartas'))),
                NavigationRailDestination(icon: const Icon(Icons.style_outlined), label: Text(tr('Decks'))),
                NavigationRailDestination(icon: const Icon(Icons.table_restaurant_outlined), label: Text(tr('Jogar'))),
                NavigationRailDestination(icon: settingsIcon, label: Text(tr('Definições'))),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    } else {
      page = Scaffold(
        body: body,
        // com letra grande, "Impostazioni" partia em duas linhas: os ícones já
        // dizem o que é cada separador, por isso a escala fica limitada
        bottomNavigationBar: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.15,
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _go,
            destinations: [
              NavigationDestination(icon: const Icon(Icons.search), label: tr('Cartas')),
              NavigationDestination(icon: const Icon(Icons.style_outlined), label: tr('Decks')),
              NavigationDestination(icon: const Icon(Icons.table_restaurant_outlined), label: tr('Jogar')),
              NavigationDestination(icon: settingsIcon, label: tr('Definições')),
            ],
          ),
        ),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: page,
    );
  }
}
