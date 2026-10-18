import 'dart:convert';
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/collection.dart';
import '../../data/providers.dart';
import '../widgets/responsive.dart';

/// Importar cartas para "As minhas cartas": CSV (ManaBox, Moxfield,
/// Deckbox, Dragon Shield...) ou lista de texto, colada ou de um ficheiro.
class CollectionImportScreen extends ConsumerStatefulWidget {
  const CollectionImportScreen({super.key});

  @override
  ConsumerState<CollectionImportScreen> createState() => _CollectionImportScreenState();
}

class _CollectionImportScreenState extends ConsumerState<CollectionImportScreen> {
  final _text = TextEditingController();
  bool _replace = false;
  ({Map<String, int> cards, List<ParsedLine> unresolved})? _result;
  String? _fileName;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _check() {
    final repo = ref.read(cardRepoProvider)!;
    setState(() => _result = resolveCollection(parseCollectionText(_text.text), repo.findByName));
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    final f = res?.files.singleOrNull;
    if (f == null) return;
    final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    if (bytes == null) return;
    setState(() {
      _fileName = f.name;
      _text.text = utf8.decode(bytes, allowMalformed: true);
    });
    _check();
  }

  Future<void> _paste() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip?.text == null) return;
    setState(() {
      _fileName = null;
      _text.text = clip!.text!;
    });
    _check();
  }

  void _import() {
    final r = _result;
    if (r == null || r.cards.isEmpty) return;
    final collection = ref.read(collectionProvider);
    if (_replace) {
      for (final id in collection.owned.keys.toList()) {
        collection.store.setOwned(id, 0);
      }
    }
    collection.addAll(r.cards);
    final total = r.cards.values.fold(0, (a, b) => a + b);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$total cartas (${r.cards.length} diferentes) importadas.'),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result;
    final total = r?.cards.values.fold(0, (a, b) => a + b) ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Importar as minhas cartas')),
      body: MaxWidth(
          child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
          'Exporta a coleção do ManaBox, Moxfield, Deckbox, Dragon Shield ou outra app em CSV, '
          'ou cola uma lista de texto ("1 Sol Ring"). As várias edições da mesma carta '
          'somam-se.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.attach_file),
              label: const Text('Escolher ficheiro'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _paste,
              icon: const Icon(Icons.content_paste),
              label: const Text('Colar'),
            ),
          ),
        ]),
        if (_fileName != null) ...[
          const SizedBox(height: 8),
          Text('Ficheiro: $_fileName', style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          minLines: 6,
          maxLines: 12,
          onChanged: (_) => setState(() => _result = null),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(
            alignLabelWithHint: true,
            labelText: 'Lista ou CSV',
            hintText: 'Name,Set code,…,Quantity\nSol Ring,c21,…,2\n\nou\n\n2 Sol Ring\n4 Forest',
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.add), label: Text('Somar')),
            ButtonSegment(value: true, icon: Icon(Icons.swap_horiz), label: Text('Substituir tudo')),
          ],
          selected: {_replace},
          onSelectionChanged: (v) => setState(() => _replace = v.first),
        ),
        if (r != null) ...[
          const SizedBox(height: 16),
          Text('$total cartas reconhecidas (${r.cards.length} diferentes).',
              style: theme.textTheme.titleSmall),
          if (r.unresolved.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Não encontradas (${r.unresolved.length}):',
                style: TextStyle(color: theme.colorScheme.error)),
            for (final l in r.unresolved.take(30))
              Text('linha ${l.line}: ${l.qty} ${l.name}', style: theme.textTheme.bodySmall),
          ],
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _check, child: const Text('Verificar'))),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: r == null || r.cards.isEmpty ? null : _import,
              child: Text(_replace ? 'Substituir' : 'Importar'),
            ),
          ),
        ]),
      ])),
    );
  }
}
