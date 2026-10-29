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
import '../../l10n/l10n.dart';

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
          title: Text(tr('Exportar backup')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr(
                'Um ficheiro que podes guardar onde quiseres (Google Drive, PC…) e voltar a importar aqui ou noutro telemóvel.')),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: decks,
              onChanged: (v) => set_(() => decks = v!),
              title: Text(tr('Decks ({nDecks})', {'nDecks': nDecks})),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: collection,
              onChanged: (v) => set_(() => collection = v!),
              title: Text(tr('As minhas cartas ({nCards})', {'nCards': nCards})),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: games,
              onChanged: (v) => set_(() => games = v!),
              title: Text(tr('Histórico de partidas ({nGames})', {'nGames': nGames})),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
            FilledButton(
              onPressed: decks || collection || games ? () => Navigator.pop(ctx, true) : null,
              child: Text(tr('Continuar')),
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
  final file = name == null
      ? tr('EDHere-backup-{date}.json', {'date': date})
      : tr('EDHere-{v}.json', {'v': _safe(name)});

  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.save_alt),
          title: Text(tr('Guardar ficheiro…')),
          subtitle: Text(tr('Escolhe a pasta: Google Drive, Transferências, cartão…')),
          onTap: () => Navigator.pop(ctx, 'save'),
        ),
        ListTile(
          leading: const Icon(Icons.share_outlined),
          title: Text(tr('Enviar…')),
          subtitle: Text(tr('WhatsApp, email, Drive…')),
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
      if (path != null) {
        messenger.showSnackBar(SnackBar(content: Text(tr('Guardado: {file}', {'file': file}))));
      }
    } else {
      final dir = Directory(p.join(ref.read(pathsProvider).cache, 'share'))..createSync(recursive: true);
      final out = File(p.join(dir.path, file))..writeAsBytesSync(bytes);
      if (!await shareFile(out.path, subject: file)) {
        messenger.showSnackBar(SnackBar(content: Text(tr('Não foi possível partilhar o ficheiro.'))));
      }
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(tr('Não foi possível guardar: {e}', {'e': e}))));
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
    if (context.mounted) _info(context, tr('Não foi possível importar'), e.message);
    return;
  } catch (e) {
    if (context.mounted) _info(context, tr('Não foi possível importar'), '$e');
    return;
  }
  if (!context.mounted) return;
  if (backup.isEmpty) {
    _info(context, tr('Backup vazio'), tr('Este ficheiro não tem decks, cartas nem partidas.'));
    return;
  }
  var decks = backup.decks.isNotEmpty, collection = backup.collection.isNotEmpty;
  var games = backup.games.isNotEmpty;
  final when = backup.exportedAt;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set_) => AlertDialog(
        title: Text(tr('Importar backup')),
        content:
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('{v}\nExportado a {day}/{month}/{year}.',
              {'v': f.name, 'day': when.day, 'month': when.month, 'year': when.year})),
          const SizedBox(height: 4),
          Text(tr('Junta ao que já tens, sem apagar nada. Decks iguais não se repetem.')),
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
              title: Text(tr('As minhas cartas ({n})', {'n': backup.collection.length})),
            ),
          if (backup.games.isNotEmpty)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: games,
              onChanged: (v) => set_(() => games = v!),
              title: Text(backup.games.length == 1
                  ? tr('Histórico (1 partida)')
                  : tr('Histórico ({n} partidas)', {'n': backup.games.length})),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
          FilledButton(
            onPressed: decks || collection || games ? () => Navigator.pop(ctx, true) : null,
            child: Text(tr('Importar')),
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
      '${r.decksAdded == 1 ? tr('1 deck novo') : tr('{n} decks novos', {'n': r.decksAdded})}'
          '${r.decksSkipped == 0 ? '' : r.decksSkipped == 1 ? tr(' (1 já existia)') : tr(' ({n} já existiam)', {'n': r.decksSkipped})}',
    if (collection) tr('{cardsAdded} cartas atualizadas na coleção', {'cardsAdded': r.cardsAdded}),
    if (games) tr('{gamesAdded} partidas no histórico', {'gamesAdded': r.gamesAdded}),
    if (r.missing.isNotEmpty)
      tr('\nAinda não estão na base de cartas (ficam no deck e aparecem quando atualizares a base): {v}{v2}',
          {'v': r.missing.take(10).join(', '), 'v2': r.missing.length > 10 ? '…' : ''}),
  ];
  _info(context, tr('Importado'), lines.join('\n'));
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
