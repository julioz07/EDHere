import 'package:card_db/card_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../qr_scan_screen.dart';
import 'deck_editor_screen.dart';
import '../widgets/responsive.dart';

/// Importar uma lista colada (Moxfield, Archidekt, MTGO, Arena).
class DeckImportScreen extends ConsumerStatefulWidget {
  const DeckImportScreen({super.key});

  @override
  ConsumerState<DeckImportScreen> createState() => _DeckImportScreenState();
}

class _DeckImportScreenState extends ConsumerState<DeckImportScreen> {
  final _name = TextEditingController();
  final _text = TextEditingController();
  String _format = 'commander';
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
    final raw =
        await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (raw == null || !mounted) return;
    final shared = SharedDeck.tryDecode(raw);
    if (shared == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Este QR não é de um deck do EDHere.')));
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
        if (repo.get(e.oracleId) case final c?) c.frontName.split(',').first,
    ];
    final name = _name.text.trim().isNotEmpty
        ? _name.text.trim()
        : commanders.isNotEmpty
            ? commanders.join(' + ')
            : 'Deck importado';
    var entries = r.entries;
    String? warning;
    // As versões da lista (coleção e número): as que já se conhecem saem
    // logo; as outras pede-se ao Scryfall.
    if (_usePrints && r.printings.isNotEmpty) {
      setState(() {
        _busy = true;
        _progress = 'A buscar as versões das cartas…';
      });
      final cards = repo.getMany(r.printings.keys);
      final res = await ref.read(printsProvider).listPrints(r.printings, cards, onProgress: (done, total) {
        if (mounted) setState(() => _progress = 'A buscar as versões das cartas… $done/$total');
      });
      if (!mounted) return;
      entries = [
        for (final e in entries)
          res.prints[e.oracleId] != null ? e.copyWith(printId: res.prints[e.oracleId]) : e,
      ];
      if (res.offline) {
        warning = 'Sem internet: ${res.missing} cartas ficaram com a versão base. '
            'Podes trocar a versão de cada carta no deck.';
      } else if (res.missing > 0) {
        warning = '${res.missing} versões não foram encontradas no Scryfall; ficaram as versões base.';
      }
      setState(() {
        _busy = false;
        _progress = null;
      });
    }
    final deck = ref.read(decksProvider).save(Deck(
          name: name,
          format: _format,
          entries: entries,
          notes: r.unresolved.isEmpty
              ? ''
              : 'Não encontradas na importação:\n${r.unresolved.map((l) => '${l.qty} ${l.name}').join('\n')}',
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
        title: const Text('Importar lista'),
        actions: [
          IconButton(tooltip: 'Ler QR de um deck', onPressed: _scan, icon: const Icon(Icons.qr_code_scanner)),
        ],
      ),
      body: MaxWidth(
          child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nome do deck'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _format,
            decoration: const InputDecoration(labelText: 'Formato'),
            items: [
              for (final f in GameFormat.all) DropdownMenuItem(value: f.id, child: Text(f.label)),
            ],
            onChanged: (v) => setState(() => _format = v ?? _format),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 10,
            maxLines: 18,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              alignLabelWithHint: true,
              labelText: 'Lista',
              hintText: 'Commander\n1 Atraxa, Praetors\' Voice\n\nDeck\n1 Sol Ring\n35 Forest\n…',
              suffixIcon: IconButton(
                tooltip: 'Colar',
                icon: const Icon(Icons.content_paste),
                onPressed: _paste,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Aceita "1 Nome", "1x Nome (SET) 123 *F* [Categoria]" e secções Commander, '
            'Deck, Sideboard e Maybeboard. Sem secções, uma linha em branco separa o '
            'sideboard (estilo MTGO).',
            style: theme.textTheme.bodySmall,
          ),
          if (_unresolved != null) ...[
            const SizedBox(height: 12),
            Text('$_found cartas reconhecidas.', style: theme.textTheme.titleSmall),
            if (_withPrint > 0)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _usePrints,
                onChanged: (v) => setState(() => _usePrints = v!),
                title: const Text('Usar as versões da lista'),
                subtitle: Text('$_withPrint cartas trazem coleção e número: ficam com essa arte '
                    '(as que não estão no telemóvel vêm do Scryfall).'),
              ),
            if (_unresolved!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Não encontradas (${_unresolved!.length}):',
                  style: TextStyle(color: theme.colorScheme.error)),
              for (final l in _unresolved!.take(30))
                Text('linha ${l.line}: ${l.qty} ${l.name}', style: theme.textTheme.bodySmall),
            ],
          ],
          const SizedBox(height: 16),
          if (_progress != null) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text(_progress!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
          ],
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _busy ? null : _check, child: const Text('Verificar'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(onPressed: _busy ? null : _import, child: const Text('Importar'))),
          ]),
        ],
      )),
    );
  }
}
