import 'package:card_db/card_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/image_service.dart';
import '../../data/providers.dart';
import '../../tutorial/chapters_basics.dart';
import '../../tutorial/chapters_commander.dart';
import '../../tutorial/tutorial.dart';
import '../widgets/responsive.dart';
import 'glossary_screen.dart';
import 'tutorial_screen.dart';

/// "Aprender a jogar Commander": duas versões e a lista de capítulos.
class TutorialHome extends ConsumerStatefulWidget {
  const TutorialHome({super.key});

  @override
  ConsumerState<TutorialHome> createState() => _TutorialHomeState();
}

class _TutorialHomeState extends ConsumerState<TutorialHome> {
  /// true = "Nunca joguei" (com o básico do Magic primeiro).
  bool _full = false;

  List<Chapter> get _chapters => _full ? [...basicsChapters, ...commanderChapters] : commanderChapters;

  /// Imagens de todas as cartas do tutorial.
  List<db.ImageRef> _refs() {
    final repo = ref.read(cardRepoProvider);
    if (repo == null) return const [];
    final names = <String>{
      for (final ch in [...basicsChapters, ...commanderChapters]) ...[
        for (final p in ch.pages) ...p.cards.map((c) => c.name),
        if (ch.setup case final s?)
          for (final seat in s.seats) ...[
            if (seat.commander != null) seat.commander!,
            ...seat.battlefield,
            ...seat.hand,
            ...seat.library,
          ],
      ],
    };
    final prints = ref.read(printsProvider);
    return [
      for (final n in names)
        if (repo.findByName(n) case final c?) ...db.ImageRef.allOf(prints.resolve(c)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = ref.watch(tutorialProgressProvider);
    final images = ref.watch(imagesProvider);
    final hasData = ref.watch(cardDataProvider).hasData;
    final chapters = _chapters;
    final done = chapters.where((c) => progress.isDone(c.id)).length;
    final refs = hasData ? _refs() : const <db.ImageRef>[];
    final missing = refs.where((r) => !images.has('small', r.key)).length;
    final job = images.job;
    return Scaffold(
      appBar: AppBar(title: const Text('Aprender a jogar Commander'), actions: [
        IconButton(
          tooltip: 'Glossário',
          icon: const Icon(Icons.menu_book_outlined),
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GlossaryScreen())),
        ),
      ]),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(
            'Um jogo guiado contra dois adversários simulados. Lês um pouco, jogas um pouco: a mesa só deixa '
            'fazer o que o passo pede, e explica quando te enganas.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.bolt), label: Text('Já sei jogar Magic')),
              ButtonSegment(value: true, icon: Icon(Icons.school_outlined), label: Text('Nunca joguei')),
            ],
            selected: {_full},
            onSelectionChanged: (v) => setState(() => _full = v.first),
          ),
          const SizedBox(height: 8),
          Text(
            _full
                ? 'Começa pelo Magic: cartas, mana, turnos, combate e a pilha. Depois tudo o que o Commander '
                    'tem de especial.'
                : 'Só o que o Commander tem de especial: o baralho de 100, a zona de comando, a taxa, o dano de '
                    'comandante e o jogo a vários.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(
              '$done de ${chapters.length} capítulos · cerca de ${chapters.fold(0, (n, c) => n + c.minutes)} '
              'minutos',
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: chapters.isEmpty ? 0 : done / chapters.length),
          const SizedBox(height: 12),
          if (!hasData)
            const Card(
              margin: EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(Icons.cloud_download_outlined),
                title: Text('Descarrega primeiro a base de cartas'),
                subtitle: Text('Em Definições → Dados. O tutorial usa cartas reais.'),
              ),
            )
          else if (missing > 0)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text('Imagens do tutorial: ${refs.length - missing} de ${refs.length}'),
                subtitle: job != null && job.pack.id == 'tutorial'
                    ? LinearProgressIndicator(value: job.total == 0 ? null : job.done / job.total)
                    : const Text(
                        'Sem imagens, as cartas aparecem só com o texto. Descarrega (menos de 1 MB).'),
                trailing: job != null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.download),
                        tooltip: 'Descarregar',
                        onPressed: () => images.download(
                            const ImagePack('tutorial', 'Tutorial', 'Cartas do tutorial', null),
                            'small',
                            refs),
                      ),
              ),
            ),
          for (var i = 0; i < chapters.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                enabled: hasData,
                leading: CircleAvatar(
                  backgroundColor:
                      progress.isDone(chapters[i].id) ? Colors.green : theme.colorScheme.secondaryContainer,
                  child: progress.isDone(chapters[i].id)
                      ? const Icon(Icons.check, color: Colors.white)
                      : Text('${i + 1}'),
                ),
                title: Text(chapters[i].title),
                subtitle: Text('${chapters[i].summary} · ${chapters[i].minutes} min'
                    '${chapters[i].hasGame ? ' · com jogo' : ''}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => TutorialScreen(chapters: chapters, index: i),
                )),
              ),
            ),
          if (done > 0)
            Center(
              child: TextButton.icon(
                onPressed: progress.reset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Recomeçar o progresso'),
              ),
            ),
        ]),
      ),
    );
  }
}
