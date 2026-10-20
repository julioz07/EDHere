import 'package:card_db/card_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../qr_scan_screen.dart';
import 'deck_editor_screen.dart';
import '../widgets/responsive.dart';
import '../../l10n/l10n.dart';

/// Importar uma lista colada (Moxfield, Archidekt, MTGO, Arena). Com
/// [intoDeckId], importa para um deck que já existe: junta às cartas que lá
/// estão ou substitui-as.
class DeckImportScreen extends ConsumerStatefulWidget {
  const DeckImportScreen({super.key, this.intoDeckId});

  final int? intoDeckId;

  @override
  ConsumerState<DeckImportScreen> createState() => _DeckImportScreenState();
}

class _DeckImportScreenState extends ConsumerState<DeckImportScreen> {
  final _name = TextEditingController();
  final _text = TextEditingController();
  late String _format = _target?.format ?? 'commander';
  late final Deck? _target = widget.intoDeckId == null ? null : ref.read(deckStoreProvider).getDeck(widget.intoDeckId!);

  /// Num deck que já existe: substituir as cartas (senão junta-as).
  bool _replace = false;
  List<ParsedLine>? _unresolved;
  int _found = 0;

  /// Cartas com versão indicada na lista ("(FDC) 86") e se é para a usar.
  int _withPrint = 0;
  bool _usePrints = true;
  bool _busy = false;
  String? _progress;

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip?.text != null) setState(() => _text.text = clip!.text!);
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (raw == null || !mounted) return;
    final shared = SharedDeck.tryDecode(raw);
    if (shared == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Este QR não é de um deck do EDHere.'))));
      return;
    }
    setState(() {
      _name.text = shared.name;
      _format = GameFormat.all.any((f) => f.id == shared.format) ? shared.format : 'free';
      _text.text = shared.text;
    });
    _check();
  }

  ImportResult _resolve() {
    final repo = ref.read(cardRepoProvider)!;
    final format = GameFormat.byId(_format);
    final parsed = parseDeckText(_text.text, hasCommandZone: format.hasCommandZone);
    return resolveDeckText(parsed, repo.findByName);
  }

  void _check() {
    final r = _resolve();
    setState(() {
      _unresolved = r.unresolved;
      _found = r.entries.fold(0, (n, e) => n + e.qty);
      _withPrint = r.printings.length;
    });
  }

  Future<void> _import() async {
    final r = _resolve();
    if (r.entries.isEmpty) {
      setState(() {
        _unresolved = r.unresolved;
        _found = 0;
      });
      return;
    }
    // Sem nome: usa o do comandante (é assim que os jogadores chamam aos decks).
    final repo = ref.read(cardRepoProvider)!;
    final commanders = [
      for (final e in r.entries.where((e) => e.board == Board.command))
        if (repo.get(e.oracleId) case final c?) c.displayFrontName.split(',').first,
    ];
    final name = _name.text.trim().isNotEmpty
        ? _name.text.trim()
        : commanders.isNotEmpty
            ? commanders.join(' + ')
            : tr('Deck importado');
    var entries = r.entries;
    String? warning;
    // As versões da lista (coleção e número): as que já se conhecem saem
    // logo; as outras pede-se ao Scryfall.
    if (_usePrints && r.printings.isNotEmpty) {
      setState(() {
        _busy = true;
        _progress = tr('A buscar as versões das cartas…');
      });
      final cards = repo.getMany(r.printings.keys);
      final res = await ref.read(printsProvider).listPrints(r.printings, cards, onProgress: (done, total) {
        if (mounted) {
          setState(
              () => _progress = tr('A buscar as versões das cartas… {done}/{total}', {'done': done, 'total': total}));
        }
      });
      if (!mounted) return;
      entries = [
        for (final e in entries) res.prints[e.oracleId] != null ? e.copyWith(printId: res.prints[e.oracleId]) : e,
      ];
      if (res.offline) {
        warning = tr(
            'Sem internet: {missing} cartas ficaram com a versão base. Podes trocar a versão de cada carta no deck.',
            {'missing': res.missing});
      } else if (res.missing > 0) {
        warning = tr(
            '{missing} versões não foram encontradas no Scryfall; ficaram as versões base.', {'missing': res.missing});
      }
      setState(() {
        _busy = false;
        _progress = null;
      });
    }
    final notes = r.unresolved.isEmpty
        ? ''
        : tr('Não encontradas na importação:\n{v}', {'v': r.unresolved.map((l) => '${l.qty} ${l.name}').join('\n')});
    if (_target case final target?) {
      var d = _replace ? target.copyWith(entries: const []) : target;
      for (final e in entries) {
        d = d.add(e.oracleId, qty: e.qty, board: e.board, category: e.category, printId: e.printId);
      }
      if (notes.isNotEmpty) d = d.copyWith(notes: [d.notes, notes].where((n) => n.isNotEmpty).join('\n\n'));
      ref.read(decksProvider).save(d);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(warning ??
              (entries.fold<int>(0, (n, e) => n + e.qty) == 1
                  ? tr('1 carta importada para {v}.', {'v': d.name})
                  : tr('{found} cartas importadas para {v}.',
                      {'found': entries.fold<int>(0, (n, e) => n + e.qty), 'v': d.name})))));
      Navigator.of(context).pop(true);
      return;
    }
    final deck = ref.read(decksProvider).save(Deck(
          name: name,
          format: _format,
          entries: entries,
          notes: notes,
        ));
    if (warning != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(warning)));
    }
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => DeckEditorScreen(deckId: deck.id!),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_target == null ? tr('Importar lista') : tr('Importar para {v}', {'v': _target.name})),
        actions: [
          IconButton(tooltip: tr('Ler QR de um deck'), onPressed: _scan, icon: const Icon(Icons.qr_code_scanner)),
        ],
      ),
      // Os botões ficam fora da lista: com o teclado aberto continuam à vista.
      body: Column(children: [
        Expanded(
          child: MaxWidth(
              child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_target == null) ...[
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: tr('Nome do deck')),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _format,
                  decoration: InputDecoration(labelText: tr('Formato')),
                  items: [
                    for (final f in GameFormat.all) DropdownMenuItem(value: f.id, child: Text(f.label)),
                  ],
                  onChanged: (v) => setState(() => _format = v ?? _format),
                ),
              ] else
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                        value: false, icon: const Icon(Icons.playlist_add), label: Text(tr('Juntar às que lá estão'))),
                    ButtonSegment(
                        value: true, icon: const Icon(Icons.swap_horiz), label: Text(tr('Substituir o deck'))),
                  ],
                  selected: {_replace},
                  onSelectionChanged: (v) => setState(() => _replace = v.first),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                minLines: 10,
                maxLines: 18,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  alignLabelWithHint: true,
                  labelText: tr('Lista'),
                  hintText: tr('Commander\n1 Atraxa, Praetors\' Voice\n\nDeck\n1 Sol Ring\n35 Forest\n…'),
                  suffixIcon: IconButton(
                    tooltip: tr('Colar'),
                    icon: const Icon(Icons.content_paste),
                    onPressed: _paste,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('Aceita "1 Nome", "1x Nome (SET) 123 *F* [Categoria]" e secções Commander, Deck, Sideboard e Maybeboard. Sem secções, uma linha em branco separa o sideboard (estilo MTGO).'),
                style: theme.textTheme.bodySmall,
              ),
              if (_unresolved != null) ...[
                const SizedBox(height: 12),
                Text(tr('{found} cartas reconhecidas.', {'found': _found}), style: theme.textTheme.titleSmall),
                if (_withPrint > 0)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _usePrints,
                    onChanged: (v) => setState(() => _usePrints = v!),
                    title: Text(tr('Usar as versões da lista')),
                    subtitle: Text(tr(
                        '{withPrint} cartas trazem coleção e número: ficam com essa arte (as que não estão no telemóvel vêm do Scryfall).',
                        {'withPrint': _withPrint})),
                  ),
                if (_unresolved!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(tr('Não encontradas ({n}):', {'n': _unresolved!.length}),
                      style: TextStyle(color: theme.colorScheme.error)),
                  for (final l in _unresolved!.take(30))
                    Text(tr('linha {line}: {qty} {v}', {'line': l.line, 'qty': l.qty, 'v': l.name}),
                        style: theme.textTheme.bodySmall),
                ],
              ],
              if (_progress != null) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 6),
                Text(_progress!, style: theme.textTheme.bodySmall),
              ],
            ],
          )),
        ),
        BottomActions(children: [
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _busy ? null : _check, child: Text(tr('Verificar')))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(onPressed: _busy ? null : _import, child: Text(tr('Importar')))),
          ]),
        ]),
      ]),
    );
  }
}
