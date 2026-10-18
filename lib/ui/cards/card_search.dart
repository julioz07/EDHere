import 'dart:async';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/collection.dart';
import '../../data/providers.dart';
import '../widgets/card_view.dart';
import '../widgets/responsive.dart';

/// Campo de pesquisa com resultados, usado no separador Cartas e ao
/// acrescentar cartas a um deck.
class CardSearchView extends ConsumerStatefulWidget {
  const CardSearchView({
    super.key,
    required this.onTap,
    this.trailingFor,
    this.initialQuery = '',
    this.fixedFilter = '',
    this.autofocus = false,
    this.hint = 'Nome ou filtros (t:dragon id:rg)',
    this.onlyOwned = false,
  });

  /// Só as minhas cartas (a coleção); sem texto mostra-as todas.
  final bool onlyOwned;

  final void Function(db.Card card) onTap;
  final Widget? Function(db.Card card)? trailingFor;
  final String initialQuery;

  /// Filtro acrescentado sempre à pesquisa (ex.: identidade do comandante).
  final String fixedFilter;
  final bool autofocus;
  final String hint;

  @override
  ConsumerState<CardSearchView> createState() => _CardSearchViewState();
}

class _CardSearchViewState extends ConsumerState<CardSearchView> {
  late final _ctrl = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  List<db.Card> _results = const [];
  int _total = 0;
  List<String> _errors = const [];
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty || widget.onlyOwned) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  Iterable<String>? get _restrict => widget.onlyOwned ? ref.read(collectionProvider).owned.keys : null;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  String get _query {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return widget.onlyOwned ? widget.fixedFilter : '';
    return widget.fixedFilter.isEmpty ? q : '$q ${widget.fixedFilter}';
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _run);
    setState(() {});
  }

  void _run() {
    final repo = ref.read(cardRepoProvider);
    if (repo == null || !mounted) return;
    final r = repo.search(_query, limit: 60, restrictTo: _restrict);
    setState(() {
      _results = r.cards;
      _total = r.total;
      _errors = r.errors;
    });
  }

  void _loadMore() {
    final repo = ref.read(cardRepoProvider);
    if (repo == null || _loadingMore || _results.length >= _total) return;
    _loadingMore = true;
    final r = repo.search(_query, limit: 60, offset: _results.length, restrictTo: _restrict);
    setState(() => _results = [..._results, ...r.cards]);
    _loadingMore = false;
  }

  /// Quantas tenho (se tiver) e o botão extra de quem usa a pesquisa.
  Widget? _trailing(db.Card c, int owned) {
    final extra = widget.trailingFor?.call(c);
    if (owned == 0) return extra;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.inventory_2_outlined, size: 14, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 3),
        Text('$owned',
            style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
      ]),
    );
    if (extra == null) return badge;
    return Row(mainAxisSize: MainAxisSize.min, children: [badge, const SizedBox(width: 4), extra]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ref.listen(cardDataProvider.select((s) => s.generation), (_, __) => _run());
    ref.watch(printsProvider);
    final collection = ref.watch(collectionProvider);
    if (widget.onlyOwned) {
      ref.listen(collectionProvider, (_, __) => _run());
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _ctrl,
            autofocus: widget.autofocus,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              hintText: widget.hint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_ctrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() {
                        _results = const [];
                        _total = 0;
                        _errors = const [];
                      });
                    },
                  ),
                IconButton(
                  tooltip: 'Ajuda da pesquisa',
                  icon: const Icon(Icons.help_outline),
                  onPressed: () => showSearchHelp(context),
                ),
              ]),
            ),
          ),
        ),
        if (_errors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Filtro não reconhecido: ${_errors.join(', ')}',
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
          ),
        if (_query.isNotEmpty || widget.onlyOwned)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_total == 1 ? '1 carta' : '$_total cartas',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.pixels > n.metrics.maxScrollExtent - 400) _loadMore();
              return false;
            },
            child: LayoutBuilder(builder: (context, box) {
              Widget tile(int i) {
                final c = _results[i];
                return CardTile(
                  ref.read(printsProvider).resolve(c),
                  thumbWidth: box.maxWidth >= wideBreakpoint ? 64 : 56,
                  onTap: () => widget.onTap(c),
                  trailing: _trailing(c, collection.ownedOf(c.oracleId)),
                );
              }

              // Tablet: resultados em várias colunas.
              if (box.maxWidth >= wideBreakpoint) {
                return GridView.builder(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 520,
                    mainAxisExtent: 104,
                  ),
                  itemCount: _results.length,
                  itemBuilder: (_, i) => tile(i),
                );
              }
              return ListView.builder(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: _results.length,
                itemBuilder: (_, i) => tile(i),
              );
            }),
          ),
        ),
      ],
    );
  }
}

void showSearchHelp(BuildContext context) {
  const rows = [
    ('sol ring', 'Nome contém'),
    ('!"Sol Ring"', 'Nome exato'),
    ('t:dragon', 'Tipo'),
    ('o:"draw a card"', 'Texto da carta'),
    ('k:flying', 'Palavra-chave'),
    ('c:rg  c=r  c:m  c:c', 'Cores (ou "azorius", "esper"…)'),
    ('id:esper', 'Cabe na identidade de cor'),
    ('mv<=3  pow>=4  tou:2', 'Valor de mana, poder, resistência'),
    ('f:commander', 'Legal no formato'),
    ('banned:modern', 'Banida no formato'),
    ('r:mythic  s:cmm', 'Raridade, coleção'),
    ('is:commander', 'Pode ser comandante'),
    ('is:token  is:dfc', 'Tokens, duas faces'),
    ('-t:land', 'Negar um filtro'),
    ('bolt or shock', 'Uma ou outra'),
    ('order:mv  order:edhrec', 'Ordenar'),
  ];
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text('Pesquisa', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Sintaxe parecida com a do Scryfall. Junta vários filtros com espaços.'),
          const SizedBox(height: 12),
          for (final (code, desc) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(
                  width: 170,
                  child: Text(code,
                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                ),
                Expanded(child: Text(desc)),
              ]),
            ),
        ],
      ),
    ),
  );
}
