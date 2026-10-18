import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:card_db/card_db.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/share.dart';
import '../../data/collection.dart';
import '../../data/providers.dart';
import '../data/data_tab.dart';

/// Exportar um backup (todos os decks, ou só [deckIds]) para um ficheiro:
/// guardar onde se quiser (Drive, Transferências…) ou enviar a alguém.
Future<void> exportBackup(BuildContext context, WidgetRef ref, {List<int>? deckIds, String? name}) async {
  final store = ref.read(deckStoreProvider);
  var decks = true, collection = deckIds == null, games = deckIds == null;
  if (deckIds == null) {
    final nDecks = store.listDecks().length;
    final nCards = store.collection().length;
    final nGames = store.listGames().length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set_) => AlertDialog(
          title: const Text('Exportar backup'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Um ficheiro que podes guardar onde quiseres (Google Drive, PC…) '
                'e voltar a importar aqui ou noutro telemóvel.'),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: decks,
              onChanged: (v) => set_(() => decks = v!),
              title: Text('Decks ($nDecks)'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: collection,
              onChanged: (v) => set_(() => collection = v!),
              title: Text('As minhas cartas ($nCards)'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: games,
              onChanged: (v) => set_(() => games = v!),
              title: Text('Histórico de partidas ($nGames)'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: decks || collection || games ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
  }
  final repo = ref.read(cardRepoProvider);
  final backup = Backup.collect(
    store,
    deckIds: decks ? deckIds : const [],
    collection: collection,
    games: games,
    nameOf: (id) => repo?.get(id)?.name,
  );
  final bytes = Uint8List.fromList(utf8.encode(backup.encode()));
  final now = DateTime.now();
  final date = '${now.year}-${_two(now.month)}-${_two(now.day)}';
  final file = name == null ? 'EDHere-backup-$date.json' : 'EDHere-${_safe(name)}.json';

  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.save_alt),
          title: const Text('Guardar ficheiro…'),
          subtitle: const Text('Escolhe a pasta: Google Drive, Transferências, cartão…'),
          onTap: () => Navigator.pop(ctx, 'save'),
        ),
        ListTile(
          leading: const Icon(Icons.share_outlined),
          title: const Text('Enviar…'),
          subtitle: const Text('WhatsApp, email, Drive…'),
          onTap: () => Navigator.pop(ctx, 'share'),
        ),
      ]),
    ),
  );
  if (action == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (action == 'save') {
      final path = await FilePicker.platform.saveFile(fileName: file, bytes: bytes);
      if (path != null) messenger.showSnackBar(SnackBar(content: Text('Guardado: $file')));
    } else {
      final dir = Directory(p.join(ref.read(pathsProvider).cache, 'share'))..createSync(recursive: true);
      final out = File(p.join(dir.path, file))..writeAsBytesSync(bytes);
      if (!await shareFile(out.path, subject: file)) {
        messenger.showSnackBar(const SnackBar(content: Text('Não foi possível partilhar o ficheiro.')));
      }
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Não foi possível guardar: $e')));
  }
}

/// Escolher um ficheiro de backup e juntar o que tem ao que já existe.
Future<void> importBackupFile(BuildContext context, WidgetRef ref) async {
  final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
  final f = res?.files.singleOrNull;
  if (f == null || !context.mounted) return;
  final Backup backup;
  try {
    final bytes = f.bytes ?? await File(f.path!).readAsBytes();
    backup = Backup.decode(utf8.decode(bytes, allowMalformed: true));
  } on FormatException catch (e) {
    if (context.mounted) _info(context, 'Não foi possível importar', e.message);
    return;
  } catch (e) {
    if (context.mounted) _info(context, 'Não foi possível importar', '$e');
    return;
  }
  if (!context.mounted) return;
  if (backup.isEmpty) {
    _info(context, 'Backup vazio', 'Este ficheiro não tem decks, cartas nem partidas.');
    return;
  }
  var decks = backup.decks.isNotEmpty, collection = backup.collection.isNotEmpty;
  var games = backup.games.isNotEmpty;
  final when = backup.exportedAt;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set_) => AlertDialog(
        title: const Text('Importar backup'),
        content:
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${f.name}\nExportado a ${when.day}/${when.month}/${when.year}.'),
          const SizedBox(height: 4),
          const Text('Junta ao que já tens, sem apagar nada. Decks iguais não se repetem.'),
          if (backup.decks.isNotEmpty)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: decks,
              onChanged: (v) => set_(() => decks = v!),
              title:
                  Text(backup.decks.length == 1 ? backup.decks.single.name : '${backup.decks.length} decks'),
            ),
          if (backup.collection.isNotEmpty)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: collection,
              onChanged: (v) => set_(() => collection = v!),
              title: Text('As minhas cartas (${backup.collection.length})'),
            ),
          if (backup.games.isNotEmpty)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: games,
              onChanged: (v) => set_(() => games = v!),
              title: Text('Histórico (${backup.games.length} partidas)'),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: decks || collection || games ? () => Navigator.pop(ctx, true) : null,
            child: const Text('Importar'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final repo = ref.read(cardRepoProvider);
  final r = importBackup(
    ref.read(deckStoreProvider),
    backup,
    decks: decks,
    collection: collection,
    games: games,
    resolve: repo == null
        ? null
        : (id, name) => repo.get(id) != null ? id : (name == null ? null : repo.findByName(name)?.oracleId),
  );
  ref.read(decksProvider).reload();
  ref.read(collectionProvider).reload();
  // Imagens pequenas das cartas importadas (com as versões dos decks), em
  // silêncio, se houver rede.
  final shown = deckCardsWithPrints(ref);
  ref.read(imagesProvider).ensure(shown.take(400));
  if (!context.mounted) return;
  final lines = [
    if (decks)
      '${r.decksAdded} ${r.decksAdded == 1 ? 'deck novo' : 'decks novos'}'
          '${r.decksSkipped > 0 ? ' (${r.decksSkipped} já ${r.decksSkipped == 1 ? 'existia' : 'existiam'})' : ''}',
    if (collection) '${r.cardsAdded} cartas atualizadas na coleção',
    if (games) '${r.gamesAdded} partidas no histórico',
    if (r.missing.isNotEmpty)
      '\nNão encontradas na base de cartas (atualiza a base e importa de novo): '
          '${r.missing.take(10).join(', ')}${r.missing.length > 10 ? '…' : ''}',
  ];
  _info(context, 'Importado', lines.join('\n'));
}

void _info(BuildContext context, String title, String text) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );

String _two(int n) => n.toString().padLeft(2, '0');
String _safe(String s) => s.replaceAll(RegExp(r'[^\w\- ]+', unicode: true), '').trim().replaceAll(' ', '-');
