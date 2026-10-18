import 'package:card_db/card_db.dart' hide Card;
import 'package:card_db/card_db.dart' as db show Card;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../settings/backup_actions.dart';
import '../../app/share.dart';
import '../../app/theme.dart';
import '../../data/bracket.dart';
import '../../data/collection.dart';
import '../../data/providers.dart';
import '../cards/card_detail_screen.dart';
import '../cards/card_search.dart';
import '../cards/versions.dart';
import '../playtest/playtest_screen.dart';
import '../widgets/card_view.dart';
import '../widgets/mana.dart';
import '../widgets/responsive.dart';
import 'decks_tab.dart';
import 'hand_simulator_screen.dart';

class DeckEditorScreen extends ConsumerStatefulWidget {
  const DeckEditorScreen({super.key, required this.deckId});

  final int deckId;

  @override
  ConsumerState<DeckEditorScreen> createState() => _DeckEditorScreenState();
}

class _DeckEditorScreenState extends ConsumerState<DeckEditorScreen> {
  late Deck _deck = ref.read(deckStoreProvider).getDeck(widget.deckId)!;
  late bool _grid = ref.read(deckStoreProvider).setting('deck_view') == 'grid';

  GameFormat get _format => GameFormat.byId(_deck.format);

  void _update(Deck d) {
    setState(() => _deck = ref.read(decksProvider).save(d));
  }

  Map<String, db.Card> _cards() => ref.read(cardRepoProvider)!.getMany(_deck.entries.map((e) => e.oracleId));

  List<DeckIssue> _issues(Map<String, db.Card> cards) {
    final f = _format;
    final repo = ref.read(cardRepoProvider)!;
    return validateDeck(_deck, f, cards, repo.legalityIn(f.legalityKey ?? '', cards.keys));
  }

  @override
  void initState() {
    super.initState();
    // Imagens automáticas das cartas dos meus decks ("As minhas cartas").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(imagesProvider).ensure(_cards().values);
    });
  }

  @override
  void dispose() {
    final images = ref.read(imagesProvider);
    final cards = _cards().values.toList();
    super.dispose();
    images.ensure(cards);
  }

  Future<void> _addCards({bool commander = false}) async {
    final cards = _cards();
    final identity = _deck
        .inBoard(Board.command)
        .map((e) => cards[e.oracleId])
        .whereType<db.Card>()
        .fold(0, (m, c) => m | c.identityMask);
    final f = _format;
    final idLetters = ManaColors.lettersOf(identity).join();
    final filters = <String>[
      if (f.legalityKey != null) 'f:${f.legalityKey}',
      if (commander) 'is:commander',
      if (!commander && f.hasCommandZone && identity != 0) 'id<=${idLetters.toLowerCase()}',
      if (!commander && f.hasCommandZone && identity == 0 && _deck.count(Board.command) > 0) 'id:c',
    ];
    // O que o filtro faz, dito por palavras (aparece como chip).
    final label = [
      if (!commander && f.hasCommandZone && _deck.count(Board.command) > 0)
        'Identidade ${identity == 0 ? 'incolor' : idLetters}',
      if (f.legalityKey != null) 'legal em ${f.label}',
    ].join(' · ');
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _AddCardsScreen(
        title: commander ? 'Escolher comandante' : 'Juntar cartas',
        fixedFilter: filters.join(' '),
        filterLabel: label,
        initialQuery: '',
        defaultOrder: commander ? 'edhrec' : 'name',
        qtyOf: (id) => _deck.entries.where((e) => e.oracleId == id).fold(0, (n, e) => n + e.qty),
        copyLimit: commander || !f.isSingleton ? null : (c) => c.copyLimit(f.maxCopies),
        onAdd: (c) async {
          if (!commander) {
            _update(_deck.add(c.oracleId, board: Board.main));
            return false;
          }
          return _chooseCommander(c);
        },
      ),
    ));
    setState(() {});
  }

  /// Escolher um comandante: o primeiro entra logo; um segundo só se forem
  /// parceiros, senão pergunta se é para trocar. Devolve true para fechar a
  /// pesquisa.
  Future<bool> _chooseCommander(db.Card c) async {
    final current = _deck.inBoard(Board.command).toList();
    final cards = _cards();
    if (current.any((e) => e.oracleId == c.oracleId)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${c.name} já é o comandante.')));
      return false;
    }
    if (current.isEmpty) {
      _update(_deck.add(c.oracleId, board: Board.command));
      return true;
    }
    final first = cards[current.first.oracleId];
    if (current.length == 1 && first != null && canPartner(first, c)) {
      _update(_deck.add(c.oracleId, board: Board.command));
      return true;
    }
    final names = [for (final e in current) cards[e.oracleId]?.name ?? '?'].join(' e ');
    final swap = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trocar de comandante?'),
        content: Text('${c.name} não pode ser parceiro de $names. Queres que passe a ser o comandante?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trocar')),
        ],
      ),
    );
    if (swap != true) return false;
    var d = _deck;
    for (final e in current) {
      d = d.setQty(e.oracleId, Board.command, 0);
    }
    _update(d.add(c.oracleId, board: Board.command));
    return true;
  }

  /// "Tenho este deck físico": junta as cartas às minhas cartas (sem somar
  /// às que já lá estão).
  Future<void> _ownDeck() async {
    final cards = <String, int>{};
    for (final e in _deck.entries.where((e) => e.board != Board.maybe)) {
      cards[e.oracleId] = (cards[e.oracleId] ?? 0) + e.qty;
    }
    ref.read(collectionProvider).addAll(cards, atLeast: true);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${cards.length} cartas juntas às minhas cartas.')));
    }
  }

  void _entryActions(DeckEntry e, db.Card card) {
    final f = _format;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        void close() => Navigator.pop(ctx);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: SizedBox(
                    width: 36,
                    child: CardImage(ref.read(printsProvider).resolve(card, printId: e.printId), radius: 3)),
                title: Text(card.name),
                subtitle: Text('${e.qty} × ${e.board.label}${e.category == null ? '' : ' · ${e.category}'}'),
              ),
              const Divider(),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.remove),
                  onPressed: () {
                    close();
                    _update(_deck.setQty(e.oracleId, e.board, e.qty - 1));
                  },
                ),
                const SizedBox(width: 24),
                Text('${e.qty}', style: Theme.of(ctx).textTheme.headlineSmall),
                const SizedBox(width: 24),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    close();
                    _update(_deck.add(e.oracleId, board: e.board));
                  },
                ),
              ]),
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Ver carta'),
                onTap: () {
                  close();
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => CardDetailScreen(
                      card: card,
                      deckPrintId: e.printId,
                      onDeckPrint: (p) async => _update(_deck.setPrint(e.oracleId, e.board, p?.printId)),
                    ),
                  ));
                },
              ),
              ListTile(
                leading: const Icon(Icons.collections_outlined),
                title: const Text('Escolher versão'),
                subtitle: Text(e.printId == null
                    ? 'A preferida ou a por defeito'
                    : (ref.read(printsProvider).info(e.printId!)?.label ?? 'Versão escolhida')),
                onTap: () async {
                  close();
                  final prints = ref.read(printsProvider);
                  final choice = await showVersionPicker(context, card,
                      current: prints.effectivePrint(card.oracleId, e.printId) ?? card.printId);
                  if (choice == null) return;
                  _update(_deck.setPrint(e.oracleId, e.board, choice.print?.printId));
                  if (choice.print != null) await prints.use(card, choice.print!);
                },
              ),
              for (final b in Board.values)
                if (b != e.board && (b != Board.command || f.hasCommandZone))
                  ListTile(
                    leading: Icon(b == Board.command ? Icons.star_outline : Icons.drive_file_move_outline),
                    title: Text(b == Board.command
                        ? (f.commandZone == CommandZone.oathbreaker
                            ? 'Pôr na zona de comando'
                            : 'Definir como comandante')
                        : 'Mover para ${b.label}'),
                    onTap: () {
                      close();
                      _update(_deck.move(e.oracleId, e.board, b));
                    },
                  ),
              ListTile(
                leading: const Icon(Icons.label_outline),
                title: const Text('Categoria'),
                subtitle: Text(e.category ?? 'Sem categoria (agrupa por tipo)'),
                onTap: () async {
                  close();
                  final cat = await _askCategory(e.category);
                  if (cat != null) {
                    _update(_deck.setCategory(e.oracleId, e.board, cat.isEmpty ? null : cat));
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
                title: const Text('Remover'),
                onTap: () {
                  close();
                  _update(_deck.setQty(e.oracleId, e.board, 0));
                },
              ),
            ]),
          ),
        );
      },
    );
  }

  Future<String?> _askCategory(String? current) {
    final existing = {
      for (final e in _deck.entries)
        if (e.category != null) e.category!,
      'Ramp',
      'Draw',
      'Remoção',
      'Wipes',
      'Terrenos',
      'Proteção',
      'Win cons',
    }.toList();
    final ctrl = TextEditingController(text: current ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Categoria'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ctrl, autofocus: true),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in existing) ActionChip(label: Text(c), onPressed: () => Navigator.pop(ctx, c)),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Sem categoria')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
  }

  void _export() {
    final cards = _cards();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copiar lista (Moxfield / Archidekt)'),
            subtitle: const Text('Com secções Commander, Deck, Sideboard e as versões escolhidas'),
            onTap: () => _copy(ctx, exportDeckText(_deck, cards, printOf: ref.read(printsProvider).info)),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_2),
            title: const Text('Mostrar QR do deck'),
            subtitle: const Text('Para outro telemóvel ler em Decks → Importar lista'),
            onTap: () {
              Navigator.pop(ctx);
              final code = SharedDeck(_deck.name, _deck.format, exportDeckText(_deck, cards)).encode();
              showDialog<void>(
                context: context,
                builder: (d) => AlertDialog(
                  title: Text(_deck.name),
                  content: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    child: SizedBox(
                      width: 280,
                      height: 280,
                      child: QrImageView(data: code, errorCorrectionLevel: QrErrorCorrectLevel.L),
                    ),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Fechar'))],
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_all),
            title: const Text('Copiar lista (MTGO)'),
            subtitle: const Text('Deck, linha em branco, sideboard'),
            onTap: () => _copy(ctx, exportDeckText(_deck, cards, style: ExportStyle.mtgo)),
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: const Text('Exportar ficheiro do EDHere…'),
            subtitle: const Text('Com versões das cartas e notas; guardar ou enviar a alguém'),
            onTap: () {
              Navigator.pop(ctx);
              exportBackup(context, ref, deckIds: [_deck.id!], name: _deck.name);
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Partilhar lista…'),
            subtitle: const Text('WhatsApp, email, notas…'),
            onTap: () {
              Navigator.pop(ctx);
              shareText(exportDeckText(_deck, cards, printOf: ref.read(printsProvider).info),
                  subject: _deck.name);
            },
          ),
          if (ref.read(collectionProvider).owned.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.shopping_cart_outlined),
              title: const Text('Copiar as cartas que me faltam'),
              subtitle: const Text('Lista de compras (sem terrenos básicos)'),
              onTap: () => _copy(ctx, _missingList(cards)),
            ),
        ]),
      ),
    );
  }

  /// As cartas do deck que não estão nas minhas cartas, no formato "1 Nome".
  String _missingList(Map<String, db.Card> cards) {
    final owned = ref.read(collectionProvider).owned;
    final need = <String, int>{};
    for (final e in _deck.entries.where((e) => e.board == Board.main || e.board == Board.command)) {
      need[e.oracleId] = (need[e.oracleId] ?? 0) + e.qty;
    }
    final lines = <String>[
      for (final MapEntry(key: id, value: n) in need.entries)
        if (cards[id] case final c? when !c.isBasicLand && n > (owned[id] ?? 0))
          '${n - (owned[id] ?? 0)} ${c.name}',
    ]..sort((a, b) => a.substring(a.indexOf(' ')).compareTo(b.substring(b.indexOf(' '))));
    return lines.isEmpty ? '' : lines.join('\n');
  }

  Future<void> _copy(BuildContext sheet, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!sheet.mounted) return;
    Navigator.pop(sheet);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lista copiada.')));
  }

  Future<void> _editSettings() async {
    final r = await showDialog<(String, String)>(
      context: context,
      builder: (_) => DeckSettingsDialog(name: _deck.name, format: _deck.format, title: 'Editar deck'),
    );
    if (r != null) _update(_deck.copyWith(name: r.$1, format: r.$2));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apagar "${_deck.name}"?'),
        content: const Text('Esta ação não se pode desfazer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    ref.read(decksProvider).delete(_deck.id!);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(imagesProvider);
    ref.watch(printsProvider);
    final cards = _cards();
    final issues = _issues(cards);
    final errors = issues.where((i) => i.level == IssueLevel.error).length;
    final f = _format;
    final size = f.hasCommandZone ? _deck.playableCount : _deck.count(Board.main);
    final target = f.exactDeck ?? f.minDeck;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_deck.name, overflow: TextOverflow.ellipsis),
            Text('${f.label} · $size${target == null ? '' : '/$target'} cartas',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          actions: [
            IconButton(
              tooltip: 'Testar (goldfish)',
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: _deck.playableCount == 0
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => PlaytestScreen(deckIds: [_deck.id!]),
                      )),
            ),
            IconButton(
              tooltip: _grid ? 'Ver em lista' : 'Ver em grelha',
              icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
              onPressed: () {
                setState(() => _grid = !_grid);
                ref.read(deckStoreProvider).setSetting('deck_view', _grid ? 'grid' : 'list');
              },
            ),
            IconButton(tooltip: 'Exportar', icon: const Icon(Icons.ios_share), onPressed: _export),
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'edit' => _editSettings(),
                'own' => _ownDeck(),
                'hands' => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => HandSimulatorScreen(deck: _deck, cards: _cards()),
                  )),
                'delete' => _delete(),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'hands', child: Text('Simular mãos iniciais')),
                PopupMenuItem(value: 'own', child: Text('Tenho este deck (juntar às minhas cartas)')),
                PopupMenuItem(value: 'edit', child: Text('Nome e formato')),
                PopupMenuItem(value: 'delete', child: Text('Apagar deck')),
              ],
            ),
          ],
          bottom: TabBar(tabs: [
            const Tab(text: 'Cartas'),
            const Tab(text: 'Estatísticas'),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Validação'),
                const SizedBox(width: 6),
                if (!f.validates)
                  const Icon(Icons.remove_circle_outline, size: 16)
                else if (errors == 0)
                  const Icon(Icons.check_circle, size: 16, color: EdhColors.ok)
                else
                  Badge(label: Text('$errors'), backgroundColor: EdhColors.bad),
              ]),
            ),
          ]),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Juntar cartas',
          onPressed: () => _addCards(),
          child: const Icon(Icons.add),
        ),
        body: TabBarView(children: [
          _CardList(
            grid: _grid,
            deck: _deck,
            cards: cards,
            format: f,
            issues: issues,
            onTap: _entryActions,
            shown: (e, c) => ref.read(printsProvider).resolve(c, printId: e.printId),
            owned: ref.watch(collectionProvider).owned,
            onChooseCommander: () => _addCards(commander: true),
          ),
          _StatsView(deck: _deck, cards: cards, format: f),
          _IssuesView(issues: issues, format: f, cards: cards),
        ]),
      ),
    );
  }
}

enum _Group { type, mv }

class _CardList extends StatefulWidget {
  const _CardList({
    required this.deck,
    required this.cards,
    required this.format,
    required this.issues,
    required this.onTap,
    required this.onChooseCommander,
    required this.shown,
    this.owned = const {},
    this.grid = false,
  });

  /// A carta com a versão desta entrada (ou a preferida).
  final db.Card Function(DeckEntry e, db.Card base) shown;

  /// As minhas cartas (oracleId -> quantidade), para indicar o que falta.
  final Map<String, int> owned;
  final Deck deck;
  final Map<String, db.Card> cards;
  final GameFormat format;
  final List<DeckIssue> issues;
  final void Function(DeckEntry, db.Card) onTap;
  final VoidCallback onChooseCommander;
  final bool grid;

  @override
  State<_CardList> createState() => _CardListState();
}

class _CardListState extends State<_CardList> {
  String _filter = '';
  final _filterCtrl = TextEditingController();
  _Group _group = _Group.type;

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  db.Card Function(DeckEntry e, db.Card base) get shown => widget.shown;
  Map<String, int> get owned => widget.owned;
  Deck get deck => widget.deck;
  Map<String, db.Card> get cards => widget.cards;
  GameFormat get format => widget.format;
  List<DeckIssue> get issues => widget.issues;
  void Function(DeckEntry, db.Card) get onTap => widget.onTap;
  VoidCallback get onChooseCommander => widget.onChooseCommander;
  bool get grid => widget.grid;

  Widget _tile(DeckEntry e, db.Card c) => CardTile(
        shown(e, c),
        thumbWidth: 84,
        subtitle: [c.typeLine, if (_ownedNote(e) case final n?) n].join(' · '),
        leadingQty: e.qty,
        onTap: () => onTap(e, c),
        trailing:
            flagged(e) ? const Icon(Icons.warning_amber_rounded, color: EdhColors.warn, size: 22) : null,
      );

  bool flagged(DeckEntry e) => issues.any((i) => i.oracleId == e.oracleId);

  String? _ownedNote(DeckEntry e) {
    if (owned.isEmpty) return null;
    final have = owned[e.oracleId] ?? 0;
    final c = cards[e.oracleId];
    if (c != null && c.isBasicLand) return null;
    if (have == 0) return 'não tens';
    if (have < e.qty) return 'tens $have';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = normalizeName(_filter);
    bool matches(DeckEntry e) {
      if (q.isEmpty) return true;
      final c = cards[e.oracleId];
      return c != null && (normalizeName(c.name).contains(q) || normalizeName(c.typeLine).contains(q));
    }

    final flagged = {
      for (final i in issues)
        if (i.oracleId != null) i.oracleId!
    };
    final sections = <(String, List<DeckEntry>)>[];
    String nameOf(DeckEntry e) => cards[e.oracleId]?.name ?? '';
    List<DeckEntry> sorted(Iterable<DeckEntry> es) => es.toList()
      ..sort((a, b) {
        final ca = cards[a.oracleId], cb = cards[b.oracleId];
        final mv = (ca?.mv ?? 0).compareTo(cb?.mv ?? 0);
        return mv != 0 ? mv : nameOf(a).compareTo(nameOf(b));
      });

    if (format.hasCommandZone) {
      sections.add((
        format.commandZone == CommandZone.oathbreaker ? 'Zona de comando' : 'Comandante',
        sorted(deck.inBoard(Board.command).where(matches))
      ));
    }
    final main = deck.inBoard(Board.main).where(matches).toList();
    final groups = <String, List<DeckEntry>>{};
    for (final e in main) {
      final c = cards[e.oracleId];
      final String key;
      if (_group == _Group.mv) {
        // Terrenos à parte; o resto pelo valor de mana.
        key = (c?.isLand ?? false)
            ? 'Land'
            : 'Custo ${(c?.mv ?? 0).round() >= 7 ? '7+' : (c?.mv ?? 0).round()}';
      } else {
        key = e.category ??
            DeckStats.typeOrder.firstWhere((t) => c?.frontType.contains(t) ?? false, orElse: () => 'Outros');
      }
      groups.putIfAbsent(key, () => []).add(e);
    }
    const typeNames = {
      'Creature': 'Criaturas',
      'Instant': 'Instantâneos',
      'Sorcery': 'Feitiços',
      'Artifact': 'Artefactos',
      'Enchantment': 'Encantamentos',
      'Planeswalker': 'Planeswalkers',
      'Battle': 'Batalhas',
      'Land': 'Terrenos',
    };
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (_group == _Group.mv) {
          // "Custo 0" ... "Custo 7+" e os terrenos no fim.
          if (a == 'Land') return 1;
          if (b == 'Land') return -1;
          return a.compareTo(b);
        }
        final ia = DeckStats.typeOrder.indexOf(a), ib = DeckStats.typeOrder.indexOf(b);
        if (ia < 0 && ib < 0) return a.compareTo(b);
        if (ia < 0) return -1;
        if (ib < 0) return 1;
        return ia.compareTo(ib);
      });
    for (final k in keys) {
      sections.add((typeNames[k] ?? k, sorted(groups[k]!)));
    }
    if (!format.hasCommandZone || deck.count(Board.side) > 0) {
      sections.add(('Sideboard', sorted(deck.inBoard(Board.side).where(matches))));
    }
    if (deck.count(Board.maybe) > 0) {
      sections.add(('Talvez', sorted(deck.inBoard(Board.maybe).where(matches))));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (format.commandZone == CommandZone.commander && deck.count(Board.command) == 0)
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: onChooseCommander,
              icon: const Icon(Icons.star),
              label: const Text('Escolher comandante'),
            ),
          ),
        if (owned.isNotEmpty)
          Builder(builder: (context) {
            final relevant = deck.entries
                .where((e) => e.board != Board.maybe && !(cards[e.oracleId]?.isBasicLand ?? false));
            final need = relevant.fold(0, (n, e) => n + e.qty);
            final have = relevant.fold(0, (n, e) => n + ((owned[e.oracleId] ?? 0).clamp(0, e.qty)));
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                Icon(Icons.inventory_2_outlined, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Tens $have de $need cartas (sem terrenos básicos)', style: theme.textTheme.bodySmall),
              ]),
            );
          }),
        if (deck.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(deck.notes, style: theme.textTheme.bodySmall),
          ),
        // Procurar dentro do deck e escolher como agrupar.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: 'Procurar no deck',
                  suffixIcon: _filter.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() {
                            _filterCtrl.clear();
                            _filter = '';
                          }),
                        ),
                ),
                controller: _filterCtrl,
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
            const SizedBox(width: 8),
            SegmentedButton<_Group>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: _Group.type, label: Text('Tipo')),
                ButtonSegment(value: _Group.mv, label: Text('Custo')),
              ],
              selected: {_group},
              onSelectionChanged: (v) => setState(() => _group = v.first),
            ),
          ]),
        ),
        for (final (title, entries) in sections)
          if (entries.isNotEmpty || title == 'Comandante') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                '$title (${entries.fold(0, (n, e) => n + e.qty)})',
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
            if (grid)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: cardColumns(MediaQuery.of(context).size.width),
                  childAspectRatio: cardAspect,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final e in entries)
                      if (cards[e.oracleId] case final c?)
                        _GridCard(
                          card: shown(e, c),
                          qty: e.qty,
                          flagged: flagged.contains(e.oracleId),
                          onTap: () => onTap(e, c),
                        ),
                  ],
                ),
              )
            else if (isWide(context))
              // Tablet: a lista em várias colunas.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 520,
                    mainAxisExtent: 132,
                  ),
                  children: [
                    for (final e in entries)
                      if (cards[e.oracleId] case final c?) _tile(e, c),
                  ],
                ),
              )
            else
              for (final e in entries)
                if (cards[e.oracleId] case final c?) _tile(e, c),
          ],
      ],
    );
  }
}

class _StatsView extends StatelessWidget {
  const _StatsView({required this.deck, required this.cards, required this.format});

  final Deck deck;
  final Map<String, db.Card> cards;
  final GameFormat format;

  @override
  Widget build(BuildContext context) {
    final s = DeckStats.of(deck, cards);
    final theme = Theme.of(context);
    final maxCurve = s.curve.fold(1, (m, v) => v > m ? v : m);
    final library = deck.count(Board.main);
    const typeNames = {
      'Creature': 'Criaturas',
      'Instant': 'Instantâneos',
      'Sorcery': 'Feitiços',
      'Artifact': 'Artefactos',
      'Enchantment': 'Encantamentos',
      'Planeswalker': 'Planeswalkers',
      'Battle': 'Batalhas',
      'Land': 'Terrenos',
    };
    Widget title(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(t, style: theme.textTheme.titleMedium),
        );

    final bracket = BracketEstimate.of(deck, cards);
    final curve = <Widget>[
      title('Curva de mana'),
      Text('Valor de mana médio: ${s.averageMv.toStringAsFixed(2)} · '
          '${s.nonLands} não-terrenos, ${s.lands} terrenos'),
      const SizedBox(height: 12),
      SizedBox(
        height: 140,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < s.curve.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${s.curve[i]}', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Container(
                    height: 100 * s.curve[i] / maxCurve,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(i == 7 ? '7+' : '$i', style: theme.textTheme.labelSmall),
                ]),
              ),
            ),
        ]),
      ),
      title('Tipos'),
      for (final t in DeckStats.typeOrder)
        if ((s.types[t] ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text(typeNames[t] ?? t)),
              Text('${s.types[t]}', style: theme.textTheme.titleSmall),
            ]),
          ),
    ];
    String plural(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';
    final colors = <Widget>[
      if (format.hasCommandZone) ...[
        title('Bracket (regra zero)'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bracket mínimo: ${bracket.label}', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(bracket.count == 0
                  ? 'Sem Game Changers.'
                  : '${plural(bracket.count, 'Game Changer', 'Game Changers')}: ${bracket.gameChangers.join(', ')}'),
              if (bracket.landDenial.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Destruição de terrenos em massa (só nos brackets 4–5): ${bracket.landDenial.join(', ')}',
                    style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (bracket.extraTurns.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                    '${plural(bracket.extraTurns.length, 'carta de turno extra', 'cartas de turno extra')}: '
                    '${bracket.extraTurns.join(', ')}'
                    '${bracket.chainsExtraTurns ? '. Nos brackets 1–3 não se encadeiam turnos extra.' : ''}',
                    style: bracket.chainsExtraTurns ? TextStyle(color: theme.colorScheme.error) : null),
              ],
              const SizedBox(height: 4),
              Text(
                'Combos de duas cartas também contam para o bracket e não se detetam pela lista: '
                'fala disso com a mesa.',
                style: theme.textTheme.bodySmall,
              ),
            ]),
          ),
        ),
      ],
      title('Cores: símbolos e fontes'),
      for (final c in 'WUBRG'.split(''))
        if ((s.pips[c] ?? 0) > 0 || (s.sources[c] ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              ManaSymbol(c, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('${plural(s.pips[c] ?? 0, 'símbolo', 'símbolos')} nos custos')),
              Text(plural(s.sources[c] ?? 0, 'terreno', 'terrenos')),
            ]),
          ),
      if (library > 0 && s.lands > 0) ...[
        title('Mão inicial (7 cartas)'),
        for (final k in [2, 3, 4])
          Text('Pelo menos $k terrenos: '
              '${(probabilityAtLeast(library, s.lands - _commandLands(), 7, k) * 100).toStringAsFixed(0)}%'),
        const SizedBox(height: 4),
        Text('Calculado sobre as $library cartas do grimório.', style: theme.textTheme.bodySmall),
      ],
    ];

    // Tablet: duas colunas lado a lado.
    if (isWide(context)) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: curve)),
          const SizedBox(width: 32),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: colors)),
        ]),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [...curve, ...colors],
    );
  }

  int _commandLands() => deck
      .inBoard(Board.command)
      .where((e) => cards[e.oracleId]?.isLand ?? false)
      .fold(0, (n, e) => n + e.qty);
}

class _IssuesView extends StatelessWidget {
  const _IssuesView({required this.issues, required this.format, required this.cards});

  final List<DeckIssue> issues;
  final GameFormat format;
  final Map<String, db.Card> cards;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!format.validates) {
      return const Center(child: Text('Formato livre: sem validação.'));
    }
    if (issues.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, color: EdhColors.ok, size: 48),
          const SizedBox(height: 8),
          Text('Deck legal em ${format.label}.', style: theme.textTheme.titleMedium),
        ]),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Text('Avisos: a app nunca impede de jogar.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final i in issues)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              i.level == IssueLevel.error ? Icons.error_outline : Icons.info_outline,
              color: i.level == IssueLevel.error ? EdhColors.bad : EdhColors.warn,
            ),
            title: Text(i.message),
            onTap: i.oracleId == null || cards[i.oracleId] == null
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => CardDetailScreen(card: cards[i.oracleId]!),
                    )),
          ),
      ],
    );
  }
}

class _AddCardsScreen extends StatefulWidget {
  const _AddCardsScreen({
    required this.title,
    required this.fixedFilter,
    required this.filterLabel,
    required this.initialQuery,
    required this.qtyOf,
    required this.onAdd,
    this.copyLimit,
    this.defaultOrder = 'name',
  });

  final String title;
  final String fixedFilter;

  /// O filtro do deck dito por palavras ("Identidade WUBG · legal em Commander").
  final String filterLabel;
  final String initialQuery;
  final String defaultOrder;
  final int Function(String oracleId) qtyOf;

  /// Máximo de cópias (singleton); null = sem limite.
  final int? Function(db.Card c)? copyLimit;

  /// Junta a carta; devolve true para fechar o ecrã (comandante escolhido).
  final Future<bool> Function(db.Card) onAdd;

  @override
  State<_AddCardsScreen> createState() => _AddCardsScreenState();
}

class _AddCardsScreenState extends State<_AddCardsScreen> {
  bool _filtered = true;
  bool _onlyOwned = false;

  Future<void> _add(db.Card c, {bool force = false}) async {
    final have = widget.qtyOf(c.oracleId);
    final limit = widget.copyLimit?.call(c);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (!force && limit != null && have >= limit) {
      // Singleton: avisa em vez de juntar uma segunda cópia sem querer.
      messenger.showSnackBar(SnackBar(
        content: Text('Já tens ${c.name}: este formato só permite $limit.'),
        action: SnackBarAction(label: 'Juntar na mesma', onPressed: () => _add(c, force: true)),
      ));
      return;
    }
    final close = await widget.onAdd(c);
    if (!mounted) return;
    if (close) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
    messenger.showSnackBar(SnackBar(
      content: Text('${c.name} (${widget.qtyOf(c.oracleId)})'),
      duration: const Duration(milliseconds: 900),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasFilter = widget.fixedFilter.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: CardSearchView(
        onlyOwned: _onlyOwned,
        hint: _onlyOwned ? 'Só as minhas cartas…' : 'Nome ou filtros (t:dragon id:rg)',
        autofocus: widget.initialQuery.isEmpty && widget.defaultOrder == 'name',
        initialQuery: widget.initialQuery,
        defaultOrder: widget.defaultOrder,
        listWhenEmpty: widget.defaultOrder == 'edhrec',
        fixedFilter: _filtered ? widget.fixedFilter : '',
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            if (hasFilter)
              FilterChip(
                avatar: Icon(_filtered ? Icons.filter_alt : Icons.filter_alt_off, size: 16),
                label: Text(
                    _filtered && widget.filterLabel.isNotEmpty ? widget.filterLabel : 'Sem filtros do deck'),
                selected: _filtered,
                showCheckmark: false,
                onSelected: (v) => setState(() => _filtered = v),
              ),
            FilterChip(
              avatar: Icon(_onlyOwned ? Icons.inventory_2 : Icons.inventory_2_outlined, size: 16),
              label: const Text('Só as que tenho'),
              selected: _onlyOwned,
              showCheckmark: false,
              onSelected: (v) => setState(() => _onlyOwned = v),
            ),
          ]),
        ),
        onTap: (c) => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CardDetailScreen(card: c, actions: [
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _add(c);
              },
              icon: const Icon(Icons.add),
              label:
                  Text(widget.title == 'Escolher comandante' ? 'Escolher como comandante' : 'Juntar ao deck'),
            ),
          ]),
        )),
        trailingFor: (c) {
          final n = widget.qtyOf(c.oracleId);
          return Row(mainAxisSize: MainAxisSize.min, children: [
            if (n > 0) Text('$n', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _add(c)),
          ]);
        },
      ),
    );
  }
}

/// Carta na vista em grelha do deck, com a quantidade por cima.
class _GridCard extends StatelessWidget {
  const _GridCard({required this.card, required this.qty, required this.flagged, required this.onTap});

  final db.Card card;
  final int qty;
  final bool flagged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Stack(children: [
        Positioned.fill(child: CardImage(card, radius: 8)),
        if (qty > 1)
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(10)),
              child: Text('×$qty',
                  style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
          ),
        if (flagged)
          const Positioned(
            top: 4,
            right: 4,
            child: CircleAvatar(
              radius: 13,
              backgroundColor: Colors.black87,
              child: Icon(Icons.warning_amber_rounded, color: EdhColors.warn, size: 18),
            ),
          ),
      ]),
    );
  }
}
