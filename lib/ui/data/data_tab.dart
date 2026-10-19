import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/card_data_service.dart';
import '../../data/image_service.dart';
import '../../data/providers.dart';
import '../about_screen.dart';
import '../widgets/responsive.dart';
import '../../l10n/l10n.dart';

String formatBytes(int b) {
  if (b < 1024 * 1024) return tr('{v} KB', {'v': (b / 1024).toStringAsFixed(0)});
  if (b < 1024 * 1024 * 1024) return tr('{v} MB', {'v': (b / 1024 / 1024).toStringAsFixed(0)});
  return tr('{v} GB', {'v': (b / 1024 / 1024 / 1024).toStringAsFixed(1)});
}

String formatDate(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

class DataTab extends ConsumerStatefulWidget {
  const DataTab({super.key});

  @override
  ConsumerState<DataTab> createState() => _DataTabState();
}

class _DataTabState extends ConsumerState<DataTab> {
  bool _rulings = true;
  String _size = 'small';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final data = ref.read(cardDataProvider);
      if (data.remoteOracle == null && !data.busy) data.checkRemote();
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(cardDataProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Dados offline')),
        actions: [
          IconButton(
            tooltip: tr('Sobre'),
            icon: const Icon(Icons.info_outline),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
          ),
        ],
      ),
      body: MaxWidth(
          child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.storage_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(tr('Base de cartas'), style: theme.textTheme.titleMedium),
                ]),
                const SizedBox(height: 10),
                if (data.hasData) ...[
                  Text(tr('{cardCount} cartas · dados do Scryfall de {v}',
                      {'cardCount': data.cardCount, 'v': formatDate(data.localDate)})),
                  Text(data.hasRulings ? tr('Com rulings') : tr('Sem rulings'),
                      style: theme.textTheme.bodySmall),
                ] else
                  Text(tr('Ainda não descarregada.')),
                if (data.remoteOracle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    tr('No Scryfall: {v} · {v2}{v3}', {
                      'v': formatDate(data.remoteOracle!.updatedAt),
                      'v2': formatBytes(data.remoteOracle!.compressedSize),
                      'v3': _rulings && data.remoteRulings != null
                          ? tr(' + rulings {v}', {'v': formatBytes(data.remoteRulings!.compressedSize)})
                          : ''
                    }),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _rulings,
                  onChanged: data.busy ? null : (v) => setState(() => _rulings = v ?? true),
                  title: Text(tr('Incluir rulings')),
                  subtitle: Text(tr('Esclarecimentos oficiais sobre cada carta')),
                ),
                const CardLanguageTile(contentPadding: EdgeInsets.zero),
                if (data.busy || data.phase == DataPhase.error || data.message.isNotEmpty) ...[
                  if (data.busy) ...[
                    LinearProgressIndicator(value: data.progress),
                    const SizedBox(height: 6),
                  ],
                  Text(data.message,
                      style:
                          TextStyle(color: data.phase == DataPhase.error ? theme.colorScheme.error : null)),
                  const SizedBox(height: 8),
                ],
                Row(children: [
                  Expanded(
                    child: data.busy && data.phase == DataPhase.downloading
                        ? OutlinedButton(onPressed: data.cancel, child: Text(tr('Cancelar')))
                        : FilledButton(
                            onPressed: data.busy ? null : () => data.update(includeRulings: _rulings),
                            child: Text(!data.hasData
                                ? tr('Descarregar')
                                : data.updateAvailable
                                    ? tr('Atualizar')
                                    : tr('Descarregar outra vez')),
                          ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: tr('Verificar novidades'),
                    onPressed: data.busy ? null : data.checkRemote,
                    icon: const Icon(Icons.refresh),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: Text(tr('Pacotes de imagens'), style: theme.textTheme.titleMedium)),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'small', label: Text(tr('Pequena'))),
                ButtonSegment(value: 'normal', label: Text(tr('Normal'))),
              ],
              selected: {_size},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _size = s.first),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            _size == 'small'
                ? tr('Pequena (146×204): listas e campo de batalha. ~15 KB por carta.')
                : tr('Normal (488×680): zoom e leitura. ~108 KB por carta.'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            tr('Sem imagem, a carta aparece como carta de texto e tudo continua a funcionar.'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (!data.hasData) Text(tr('Descarrega primeiro a base de cartas.')) else _Packs(size: _size),
          if (data.hasData) ...[
            const SizedBox(height: 8),
            const _VersionsPack(),
          ],
          const SizedBox(height: 16),
          _Storage(),
        ],
      )),
    );
  }
}

class _Packs extends ConsumerWidget {
  const _Packs({required this.size});

  final String size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final images = ref.watch(imagesProvider);
    final repo = ref.watch(cardRepoProvider)!;
    final store = ref.watch(deckStoreProvider);
    ref.watch(decksProvider);
    final installed = store.installedPacks(size);
    final deckIds = store.allDeckOracleIds();
    final mine = deckCardsWithPrints(ref);
    final job = images.job;
    final theme = Theme.of(context);

    return Column(children: [
      for (final pack in ImagePack.all)
        Builder(builder: (context) {
          final refs = images.refsFor(pack, repo, deckIds, mine: mine);
          final st = images.status(refs, size);
          final running = job != null && job.pack.id == pack.id && job.size == size;
          final complete = st.missing == 0 && st.total > 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(pack.label, style: theme.textTheme.titleSmall),
                          if (installed.contains(pack.id) || pack.id == 'mine') ...[
                            const SizedBox(width: 6),
                            Icon(pack.id == 'mine' ? Icons.autorenew : Icons.check_circle,
                                size: 16, color: theme.colorScheme.primary),
                          ],
                        ]),
                        Text(
                          tr('{total} cartas · {v}', {
                            'total': st.total,
                            'v': complete
                                ? 'completo'
                                : tr('faltam {missing} (~{v})',
                                    {'missing': st.missing, 'v': formatBytes(st.estimateBytes(size))})
                          }),
                          style: theme.textTheme.bodySmall,
                        ),
                      ]),
                    ),
                    if (running)
                      TextButton(onPressed: images.cancel, child: Text(tr('Parar')))
                    else if (!complete && st.total > 0)
                      TextButton(
                        onPressed: job != null
                            ? null
                            : () => images.download(pack, size, refs,
                                onDone: () => store.markPackInstalled(pack.id, size)),
                        child: Text(tr('Descarregar')),
                      ),
                  ]),
                  if (running) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: job.total == 0 ? null : job.done / job.total),
                    const SizedBox(height: 4),
                    Text('${job.done}/${job.total}${job.failed > 0 ? ' · ${job.failed} falharam' : ''}',
                        style: theme.textTheme.bodySmall),
                  ],
                ]),
              ),
            ),
          );
        }),
      if (images.lastError != null && job == null)
        Text(tr('Último erro: {lastError}', {'lastError': images.lastError}),
            style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
    ]);
  }
}

class _Storage extends ConsumerStatefulWidget {
  @override
  ConsumerState<_Storage> createState() => _StorageState();
}

class _StorageState extends ConsumerState<_Storage> {
  Map<String, int>? _usage;

  Future<void> _measure() async {
    final images = ref.read(imagesProvider);
    final s = await images.diskUsage('small');
    final n = await images.diskUsage('normal');
    if (mounted) setState(() => _usage = {'small': s, 'normal': n});
  }

  @override
  Widget build(BuildContext context) {
    final images = ref.watch(imagesProvider);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Espaço usado'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(tr('Pequenas: {v} imagens{v2}', {
            'v': images.count('small'),
            'v2': _usage == null ? '' : ' · ${formatBytes(_usage!['small']!)}'
          })),
          Text(tr('Normais: {v} imagens{v2}', {
            'v': images.count('normal'),
            'v2': _usage == null ? '' : ' · ${formatBytes(_usage!['normal']!)}'
          })),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: _measure,
              child: Text(tr('Medir')),
            ),
            for (final size in ['small', 'normal'])
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: images.job != null
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(
                                tr('Apagar imagens {v}?', {'v': size == 'small' ? 'pequenas' : 'normais'})),
                            content: Text(tr('Podes voltar a descarregá-las depois.')),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Apagar'))),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await images.deleteAll(size);
                        final store = ref.read(deckStoreProvider);
                        for (final p in ImagePack.all) {
                          store.unmarkPack(p.id, size);
                        }
                        _usage = null;
                        if (mounted) setState(() {});
                      },
                child: Text(tr('Apagar {v}', {'v': size == 'small' ? 'pequenas' : 'normais'})),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// Todas as versões alternativas das cartas dos meus decks (imagens pequenas).
class _VersionsPack extends ConsumerWidget {
  const _VersionsPack();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prints = ref.watch(printsProvider);
    final store = ref.watch(deckStoreProvider);
    ref.watch(decksProvider);
    final repo = ref.watch(cardRepoProvider)!;
    final ids = store.allDeckOracleIds();
    final progress = prints.packProgress;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Versões alternativas dos meus decks'), style: theme.textTheme.titleSmall),
                Text(
                  tr('{n} cartas · todas as versões, imagem pequena. Precisa de internet. Escolher uma versão descarrega sempre só essa.',
                      {'n': ids.length}),
                  style: theme.textTheme.bodySmall,
                ),
              ]),
            ),
            if (progress != null)
              TextButton(onPressed: prints.cancelPack, child: Text(tr('Parar')))
            else
              TextButton(
                onPressed: ids.isEmpty ? null : () => prints.downloadVersionsFor(repo.getMany(ids)),
                child: Text(tr('Descarregar')),
              ),
          ]),
          if (progress != null) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: progress.total == 0 ? null : progress.done / progress.total),
            const SizedBox(height: 4),
            Text(
                tr('{done}/{total} cartas · {images} imagens',
                    {'done': progress.done, 'total': progress.total, 'images': progress.images}),
                style: theme.textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }
}

/// As cartas de todos os decks, cada uma com a versão escolhida no deck (ou
/// a preferida): são estas as imagens que aparecem na app.
List<db.Card> deckCardsWithPrints(WidgetRef ref) {
  final repo = ref.read(cardRepoProvider);
  if (repo == null) return const [];
  final prints = ref.read(printsProvider);
  final seen = <String>{};
  return [
    for (final d in ref.read(decksProvider).decks)
      for (final e in d.entries)
        if (repo.get(e.oracleId) case final c?)
          if (prints.resolve(c, printId: prints.effectivePrint(e.oracleId, e.printId)) case final shown
              when seen.add('${shown.oracleId}|${shown.printId}'))
            shown,
  ];
}

/// A língua em que as cartas aparecem (nome, texto e imagem), com o estado
/// do download. Mudar descarrega a língua nova (ou volta ao inglês).
class CardLanguageTile extends ConsumerWidget {
  const CardLanguageTile({super.key, this.contentPadding, this.icon = true});
  final EdgeInsetsGeometry? contentPadding;
  final bool icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(cardDataProvider);
    final theme = Theme.of(context);
    final wanted = data.wantedCardLang;
    final label = langName(wanted);
    final status = !data.hasData
        ? tr('Descarrega-se com a base de cartas.')
        : data.languagePending
            ? tr('Ainda em {lang}: falta descarregar (~20 MB).', {'lang': langName(data.cardLang)})
            : wanted == 'en'
                ? tr('O texto oficial (Oracle).')
                : tr('{n} cartas em {lang}; as que não existem nessa língua ficam em inglês.',
                    {'n': data.localizedCount, 'lang': label});
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
        contentPadding: contentPadding,
        leading: icon ? const Icon(Icons.translate) : null,
        title: Text(tr('Língua das cartas')),
        subtitle: Text(status),
        trailing: DropdownButton<String>(
          value: wanted,
          underline: const SizedBox.shrink(),
          items: [
            for (final l in AppLang.values) DropdownMenuItem(value: l.code, child: Text(l.label)),
          ],
          onChanged: data.busy ? null : (code) => code == null ? null : data.setCardLang(code),
        ),
      ),
      if (data.languagePending && !data.busy)
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: contentPadding == EdgeInsets.zero
                ? const EdgeInsets.only(bottom: 8)
                : const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton.icon(
              onPressed: data.syncLanguage,
              icon: const Icon(Icons.download_rounded),
              label: Text(tr('Descarregar as cartas em {lang}', {'lang': label})),
            ),
          ),
        ),
      if (!data.busy && data.phase == DataPhase.error && contentPadding != EdgeInsets.zero)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child:
              Text(data.message, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        ),
      if (data.busy && contentPadding != EdgeInsets.zero) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LinearProgressIndicator(value: data.progress),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(data.message, style: theme.textTheme.bodySmall),
        ),
      ],
    ]);
  }
}
