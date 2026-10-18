import 'dart:math';

import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/booster_service.dart';
import '../../data/providers.dart';
import '../decks/deck_editor_screen.dart';
import '../table/table_card.dart';
import '../widgets/card_view.dart';
import '../widgets/mana.dart';
import '../widgets/responsive.dart';
import '../widgets/set_symbol.dart';
import 'limited_common.dart';

/// Nomes dos produtos JumpStart (o código vem do MTGJSON).
const _jumpstartNames = {
  'JMP': 'Jumpstart (2020)',
  'J22': 'Jumpstart 2022',
  'J25': 'Foundations Jumpstart',
  'FDN': 'Foundations',
  'DMU': 'Dominaria United',
  'BRO': "The Brothers' War",
  'ONE': 'Phyrexia: All Will Be One',
  'MOM': 'March of the Machine',
  'LTR': 'The Lord of the Rings',
  'CLU': 'Ravnica: Clue Edition',
  'MSH': 'Marvel Super Heroes',
  'TLE': 'Avatar: The Last Airbender',
};

/// JumpStart: escolhes 2 pacotes de 20 cartas vendo só o tema e a carta de
/// destaque; juntos fazem o deck de 40, pronto a jogar.
class JumpstartScreen extends ConsumerStatefulWidget {
  const JumpstartScreen({super.key});

  @override
  ConsumerState<JumpstartScreen> createState() => _JumpstartScreenState();
}

class _JumpstartScreenState extends ConsumerState<JumpstartScreen> {
  final _random = Random();
  List<db.JumpstartPacket> _all = const [];
  String? _set; // null = todos
  final List<db.JumpstartPacket> _chosen = [];
  List<db.JumpstartPacket> _offer = const [];
  List<List<PoolCard>>? _revealed;

  @override
  void initState() {
    super.initState();
    ref.read(boosterServiceProvider).jumpstart().then((p) {
      if (!mounted) return;
      setState(() => _all = p);
      _deal();
    });
  }

  List<db.JumpstartPacket> get _available => _all.where((p) => _set == null || p.set == _set).toList();

  /// Três pacotes de temas diferentes (e diferentes do já escolhido).
  void _deal() {
    final pool = _available.where((p) => !_chosen.any((c) => c.theme == p.theme)).toList()..shuffle(_random);
    final offer = <db.JumpstartPacket>[];
    for (final p in pool) {
      if (offer.any((o) => o.theme == p.theme)) continue;
      offer.add(p);
      if (offer.length == 3) break;
    }
    setState(() => _offer = offer);
    final repo = ref.read(cardRepoProvider);
    if (repo == null) return;
    // Imagens das cartas de destaque, para escolher pela arte.
    final featured = [
      for (final p in offer)
        if (repo.get(p.featured.oracleId) case final base?) base.withPrint(p.featured.printInfo(base)),
    ];
    ref.read(imagesProvider).ensure(featured);
  }

  /// Cores do pacote (pelas cartas que não são terrenos), em WUBRG.
  List<String> _colorsOf(db.JumpstartPacket p) {
    final repo = ref.read(cardRepoProvider);
    var mask = 0;
    for (final (print, _) in p.cards) {
      final c = repo?.get(print.oracleId);
      if (c != null && !c.isLand) mask |= c.colorMask;
    }
    return db.ManaColors.lettersOf(mask);
  }

  void _pick(db.JumpstartPacket p) {
    setState(() => _chosen.add(p));
    if (_chosen.length < 2) _deal();
  }

  /// As cartas de um pacote. Alguns pacotes (BRO, DMU, LTR, MOM, ONE) têm só 19
  /// cartas fixas nos dados: completa-se até 20 com o terreno básico que o
  /// pacote mais usa, para o deck ter as 40 do mínimo de limited.
  List<db.PackCard> _packetCards(db.JumpstartPacket p) {
    final out = [
      for (final (print, n) in p.cards)
        for (var i = 0; i < n; i++) db.PackCard(print),
    ];
    if (out.length >= 20) return out;
    final repo = ref.read(cardRepoProvider);
    (db.BoosterPrint, int)? basic;
    for (final (print, n) in p.cards) {
      final c = repo?.get(print.oracleId);
      if (c != null && c.isBasicLand && (basic == null || n > basic.$2)) basic = (print, n);
    }
    if (basic != null) {
      for (var i = out.length; i < 20; i++) {
        out.add(db.PackCard(basic.$1));
      }
    }
    return out;
  }

  Future<void> _save(List<PoolCard> cards) async {
    final entries = <db.DeckEntry>[];
    for (final c in cards) {
      // Uma entrada por carta (a base de decks junta versões diferentes da mesma).
      final i = entries.indexWhere((e) => e.oracleId == c.base.oracleId);
      if (i >= 0) {
        entries[i] =
            db.DeckEntry(oracleId: entries[i].oracleId, qty: entries[i].qty + 1, printId: entries[i].printId);
      } else {
        entries.add(db.DeckEntry(oracleId: c.base.oracleId, qty: 1, printId: c.printId));
      }
    }
    final deck = ref.read(decksProvider).save(db.Deck(
          name: 'JumpStart · ${_chosen.map((p) => p.theme).join(' + ')}',
          format: 'limited',
          entries: entries,
          notes: 'Pacotes: ${_chosen.map((p) => '${p.name} (${p.set})').join(', ')}',
        ));
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => DeckEditorScreen(deckId: deck.id!),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sets = {for (final p in _all) p.set}.toList()..sort();
    if (_chosen.length == 2) return _reveal(context);
    return Scaffold(
      appBar: AppBar(title: const Text('JumpStart')),
      body: _all.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : MaxWidth(
              max: 960,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text(
                  _chosen.isEmpty
                      ? 'Escolhe o primeiro pacote. Só vês o tema, as cores e a carta de destaque; as outras '
                          '19 cartas aparecem no fim.'
                      : 'Primeiro: ${_chosen.first.theme}. Agora escolhe o segundo pacote.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (_chosen.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
                      onPressed: () {
                        setState(_chosen.clear);
                        _deal();
                      },
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Trocar o primeiro'),
                    ),
                  ),
                const SizedBox(height: 12),
                if (_chosen.isEmpty)
                  SizedBox(
                    height: 44,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      ChoiceChip(
                        label: Text('Todos (${_all.length})'),
                        selected: _set == null,
                        onSelected: (_) {
                          setState(() => _set = null);
                          _deal();
                        },
                      ),
                      for (final s in sets)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ChoiceChip(
                            avatar: SetSymbol(s, size: 16),
                            label: Text(_jumpstartNames[s] ?? s),
                            selected: _set == s,
                            onSelected: (_) {
                              setState(() => _set = s);
                              _deal();
                            },
                          ),
                        ),
                    ]),
                  ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, box) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final p in _offer)
                        SizedBox(
                          width: ((box.maxWidth - 24) / 3).clamp(100.0, 260.0),
                          child: _PacketCard(packet: p, colors: _colorsOf(p), onTap: () => _pick(p)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: _deal,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Outros três'),
                  ),
                ),
              ]),
            ),
    );
  }

  Widget _reveal(BuildContext context) {
    final theme = Theme.of(context);
    final packets = _revealed ??= [for (final p in _chosen) resolvePool(ref, _packetCards(p))];
    final cards = [for (final p in packets) ...p];
    int order(PoolCard a, PoolCard b) {
      final la = a.base.isLand ? 1 : 0, lb = b.base.isLand ? 1 : 0;
      if (la != lb) return la.compareTo(lb);
      return a.base.mv.compareTo(b.base.mv);
    }

    // Cada pacote com as suas cartas; cópias iguais numa só (com ×N).
    List<(PoolCard, int)> grouped(List<PoolCard> list) {
      final g = <String, (PoolCard, int)>{};
      for (final c in [...list]..sort(order)) {
        final k = '${c.base.oracleId}|${c.printId}';
        g[k] = (g[k]?.$1 ?? c, (g[k]?.$2 ?? 0) + 1);
      }
      return g.values.toList();
    }

    return Scaffold(
      appBar: AppBar(title: Text('${_chosen.map((p) => p.theme).join(' + ')} · ${cards.length} cartas')),
      body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        for (var i = 0; i < _chosen.length; i++) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              SetSymbol(_chosen[i].set, rarity: 'R', size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${_chosen[i].name} · ${_jumpstartNames[_chosen[i].set] ?? _chosen[i].set}',
                    style: theme.textTheme.titleMedium),
              ),
              for (final c in _colorsOf(_chosen[i])) ManaSymbol(c, size: 18),
            ]),
          ),
          PoolGrid(target: 110, children: [
            for (final (c, n) in grouped(packets[i])) PoolCardView(card: c, qty: n),
          ]),
        ],
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _chosen.clear();
                    _revealed = null;
                  });
                  _deal();
                },
                icon: const Icon(Icons.restart_alt),
                label: const Text('Escolher outros'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _save(cards),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar o deck'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Um pacote fechado: tema, produto e a carta de destaque.
class _PacketCard extends ConsumerWidget {
  const _PacketCard({required this.packet, required this.colors, required this.onTap});
  final db.JumpstartPacket packet;
  final List<String> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.watch(cardRepoProvider);
    final base = repo?.get(packet.featured.oracleId);
    final shown = base?.withPrint(packet.featured.printInfo(base));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            Text(packet.theme,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SetSymbol(packet.set, rarity: 'R', size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(_jumpstartNames[packet.set] ?? packet.set,
                    style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
              ),
            ]),
            if (colors.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final c in colors)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: ManaSymbol(c, size: 18)),
              ]),
            ],
            const SizedBox(height: 8),
            if (shown != null) CardImage(shown, radius: 8) else const CardBack(),
            const SizedBox(height: 8),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: onTap,
              child: const FittedBox(child: Text('Escolher')),
            ),
          ]),
        ),
      ),
    );
  }
}
