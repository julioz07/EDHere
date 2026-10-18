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
    });
  }

  void _import() {
    final r = _resolve();
    if (r.entries.isEmpty) {
      setState(() {
        _unresolved = r.unresolved;
        _found = 0;
      });
      return;
    }
    final name = _name.text.trim().isEmpty ? 'Deck importado' : _name.text.trim();
    final deck = ref.read(decksProvider).save(Deck(
          name: name,
          format: _format,
          entries: r.entries,
          notes: r.unresolved.isEmpty
              ? ''
              : 'Não encontradas na importação:\n${r.unresolved.map((l) => '${l.qty} ${l.name}').join('\n')}',
        ));
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
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
            if (_unresolved!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Não encontradas (${_unresolved!.length}):',
                  style: TextStyle(color: theme.colorScheme.error)),
              for (final l in _unresolved!.take(30))
                Text('linha ${l.line}: ${l.qty} ${l.name}', style: theme.textTheme.bodySmall),
            ],
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _check, child: const Text('Verificar'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(onPressed: _import, child: const Text('Importar'))),
          ]),
        ],
      )),
    );
  }
}
