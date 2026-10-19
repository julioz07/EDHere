import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/providers.dart';
import '../../tutorial/tutorial.dart';
import '../../tutorial/tutorial_runner.dart';
import '../table/table_screen.dart';
import '../widgets/card_view.dart';
import '../widgets/mana.dart';
import '../widgets/responsive.dart';
import 'glossary_screen.dart';
import '../../l10n/l10n.dart';

/// Capítulos do tutorial já feitos (guardado entre sessões).
class TutorialProgress extends ChangeNotifier {
  TutorialProgress(this._prefs) : _done = {...?_prefs.getStringList(_key)};
  static const _key = 'tutorial_done';
  final SharedPreferences _prefs;
  final Set<String> _done;

  bool isDone(String id) => _done.contains(id);

  void markDone(String id) {
    if (!_done.add(id)) return;
    _prefs.setStringList(_key, _done.toList());
    notifyListeners();
  }

  void reset() {
    _done.clear();
    _prefs.remove(_key);
    notifyListeners();
  }
}

final tutorialProgressProvider =
    ChangeNotifierProvider<TutorialProgress>((ref) => TutorialProgress(ref.watch(prefsProvider)));

/// Texto com **negrito**, linhas "• " como lista e símbolos de mana {G}.
class RichLesson extends StatelessWidget {
  const RichLesson(this.text, {super.key, this.style, this.textAlign});
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  static final _mana = RegExp(r'\{([0-9WUBRGCXTS]|[WUBRG2]/[WUBRGP])\}');

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyLarge;
    final spans = <InlineSpan>[];
    final size = (base?.fontSize ?? 14) * 1.05;
    final parts = text.split('**');
    for (var i = 0; i < parts.length; i++) {
      final bold = i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null;
      // Os custos ({1}{G}, {T}…) desenham-se como símbolos de mana.
      var last = 0;
      for (final m in _mana.allMatches(parts[i])) {
        if (m.start > last) spans.add(TextSpan(text: parts[i].substring(last, m.start), style: bold));
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: ManaSymbol(m.group(1)!, size: size),
        ));
        last = m.end;
      }
      if (last < parts[i].length) spans.add(TextSpan(text: parts[i].substring(last), style: bold));
    }
    return Text.rich(TextSpan(style: base?.copyWith(height: 1.4), children: spans), textAlign: textAlign);
  }
}

/// Um capítulo: as páginas e depois o jogo guiado.
class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key, required this.chapters, required this.index});
  final List<Chapter> chapters;
  final int index;

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen> {
  Chapter get chapter => widget.chapters[widget.index];
  final _pages = PageController();
  int _page = 0;
  TutorialRunner? _runner;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    if (chapter.pages.isEmpty && chapter.hasGame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _runner?.removeListener(_changed);
    _runner?.dispose();
    super.dispose();
  }

  void _play() {
    final repo = ref.read(cardRepoProvider)!;
    final prints = ref.read(printsProvider);
    final name = ref.read(playerNameProvider).trim();
    final r = TutorialRunner(
      chapter: chapter,
      repo: repo,
      playerName: name.isEmpty ? tr('Jogador') : name,
      resolvePrint: (c, p) => prints.resolve(c, printId: p),
    );
    if (!r.build()) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Faltam cartas na base')),
          content: Text(tr('Atualiza a base de cartas em Definições → Dados. Em falta: {v}.',
              {'v': r.missing.join(', ')})),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }
    r.addListener(_changed);
    setState(() => _runner = r);
    r.start();
  }

  int _lastStep = -1;

  void _changed() {
    final r = _runner;
    // Um passo novo: fecha folhas abertas (vida, contadores…), para se ler o
    // texto seguinte.
    if (r != null && r.step != _lastStep) {
      _lastStep = r.step;
      if (mounted) Navigator.of(context).popUntil((route) => route is! PopupRoute);
    }
    if (_runner?.finished == true && !_ended) {
      _ended = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  Future<void> _finish() async {
    ref.read(tutorialProgressProvider).markDone(chapter.id);
    if (!mounted) return;
    final hasNext = widget.index + 1 < widget.chapters.length;
    if (!hasNext) {
      await _trackDone();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.emoji_events_outlined, size: 40),
        title: Text(tr('"{title}" concluído', {'title': chapter.title})),
        content: Text(hasNext
            ? tr('Segue-se: {title}.', {'title': widget.chapters[widget.index + 1].title})
            : tr('Chegaste ao fim do tutorial. Agora é jogar!')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Voltar à lista'))),
          if (hasNext) FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Seguinte'))),
        ],
      ),
    );
    if (!mounted) return;
    if (go == true) {
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => TutorialScreen(chapters: widget.chapters, index: widget.index + 1),
      ));
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Fim de uma versão do tutorial: o que se aprendeu.
  Future<void> _trackDone() => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            icon: const Icon(Icons.emoji_events, size: 48, color: Colors.amber),
            title: Text(tr('Tutorial concluído!')),
            content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Aprendeste:')),
                    const SizedBox(height: 6),
                    for (final c in widget.chapters)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.check_circle, size: 18, color: Colors.green),
                          const SizedBox(width: 6),
                          Expanded(child: Text(c.title, style: theme.textTheme.bodyMedium)),
                        ]),
                      ),
                    const SizedBox(height: 8),
                    Text(
                        tr('Próximo passo: monta (ou importa) o teu deck e cria uma sala com os amigos. O glossário está sempre no ícone do livro.'),
                        style: theme.textTheme.bodySmall),
                  ]),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Bons jogos!')))],
          );
        },
      );

  Future<bool> _confirmLeave(BuildContext context) async {
    if (_runner?.finished == true) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sair do capítulo?')),
        content: Text(tr('Podes recomeçá-lo quando quiseres.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Ficar'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sair'))),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final r = _runner;
    if (r != null) {
      return TableScreen(
        ctrl: r.ctrl,
        title: chapter.title,
        banner: CoachPanel(runner: r),
        confirmLeave: _confirmLeave,
      );
    }
    final theme = Theme.of(context);
    final pages = chapter.pages;
    final last = _page >= pages.length - 1;
    return Scaffold(
      appBar: AppBar(title: Text(chapter.title)),
      body: pages.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _pages,
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _LessonPage(page: pages[i]),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            for (var i = 0; i < pages.length; i++)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _page ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                ),
              ),
            const Spacer(),
            if (_page > 0)
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () =>
                    _pages.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: Text(tr('Anterior')),
              ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () {
                if (!last) {
                  _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                } else if (chapter.hasGame) {
                  _play();
                } else {
                  _ended = true;
                  _finish();
                }
              },
              icon: Icon(
                  !last ? Icons.arrow_forward : (chapter.hasGame ? Icons.play_arrow_rounded : Icons.check)),
              label: Text(!last ? tr('Seguinte') : (chapter.hasGame ? tr('Jogar') : tr('Concluir'))),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LessonPage extends ConsumerWidget {
  const _LessonPage({required this.page});
  final TPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.watch(cardRepoProvider);
    final prints = ref.watch(printsProvider);
    return MaxWidth(
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
        Text(page.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        for (final para in page.body.split('\n'))
          Padding(
            padding: EdgeInsets.only(bottom: para.isEmpty ? 4 : 2, left: para.startsWith('• ') ? 8 : 0),
            child: RichLesson(para),
          ),
        if (page.cards.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
            for (final tc in page.cards)
              if (repo?.findByName(tc.name) case final c?)
                SizedBox(
                  width: 128,
                  child: Column(children: [
                    Stack(children: [
                      CardImage(prints.resolve(c), radius: 8),
                      if (tc.ok != null)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: tc.ok! ? Colors.green : theme.colorScheme.error,
                            child: Icon(tc.ok! ? Icons.check : Icons.close, size: 18, color: Colors.white),
                          ),
                        ),
                    ]),
                    if (tc.caption != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: RichLesson(tc.caption!,
                            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                      ),
                  ]),
                ),
          ]),
        ],
      ]),
    );
  }
}

/// O guia por cima da mesa: o que fazer agora, os avisos e o "Continuar".
class CoachPanel extends StatefulWidget {
  const CoachPanel({super.key, required this.runner});
  final TutorialRunner runner;

  @override
  State<CoachPanel> createState() => _CoachPanelState();
}

class _CoachPanelState extends State<CoachPanel> {
  bool _small = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.runner,
      builder: (context, _) {
        final r = widget.runner;
        final s = r.current;
        final total = r.chapter.steps.length;
        // Telemóvel deitado: pouca altura, o guia fica compacto para a mesa caber.
        final screenH = MediaQuery.sizeOf(context).height;
        final short = screenH < 520;
        // O texto do passo tem altura limitada (com scroll), proporcional ao
        // ecrã; em telemóveis pequenos o "Continuar" sobe para a linha do título.
        final textMax = (screenH * 0.16).clamp(64.0, 180.0);
        final inlineNext = screenH < 760;
        final showNext = s != null && s.done == null && !r.busy;
        Widget nextButton() => FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: Size(0, inlineNext ? 34 : 40),
                  padding: inlineNext ? const EdgeInsets.symmetric(horizontal: 14) : null),
              onPressed: r.next,
              child: Text(r.step + 1 >= total ? tr('Concluir') : tr('Continuar')),
            );
        return Material(
          color: theme.colorScheme.primaryContainer,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                // No tablet, linhas curtas lêem-se melhor.
                constraints: const BoxConstraints(maxWidth: 820),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14, short ? 2 : 8, 6, short ? 2 : 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Icon(Icons.school_outlined, size: 18, color: theme.colorScheme.onPrimaryContainer),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          r.finished
                              ? tr('Capítulo concluído')
                              : tr('Passo {v} de {total}', {'v': r.step + 1, 'total': total}),
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                        ),
                      ),
                      if (inlineNext && showNext) nextButton(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: tr('Glossário'),
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => const GlossaryScreen())),
                        icon: const Icon(Icons.menu_book_outlined, size: 20),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: _small ? tr('Mostrar o guia') : tr('Encolher o guia'),
                        onPressed: () => setState(() => _small = !_small),
                        icon: Icon(_small ? Icons.expand_more : Icons.expand_less),
                      ),
                    ]),
                    if (!_small) ...[
                      if (r.busy && r.narration != null)
                        // Tudo o que os adversários fizeram nesta vez; a última em destaque.
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: textMax),
                          child: SingleChildScrollView(
                            reverse: true,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              for (final (i, line) in r.narrated.indexed)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4, right: 8),
                                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Icon(
                                      i == r.narrated.length - 1
                                          ? Icons.hourglass_top_rounded
                                          : Icons.check_rounded,
                                      size: 20,
                                      color: i == r.narrated.length - 1
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: RichLesson(line,
                                          style: i == r.narrated.length - 1
                                              ? theme.textTheme.bodyMedium
                                                  ?.copyWith(fontWeight: FontWeight.w600)
                                              : theme.textTheme.bodyMedium
                                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                    ),
                                  ]),
                                ),
                            ]),
                          ),
                        )
                      else if (s != null && !r.busy)
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: textMax),
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: RichLesson(s.text, style: theme.textTheme.bodyMedium),
                            ),
                          ),
                        ),
                      if (r.hint != null && !r.busy)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 8),
                          child: Row(children: [
                            Icon(Icons.info_outline, size: 18, color: theme.colorScheme.error),
                            const SizedBox(width: 6),
                            Expanded(
                              child: RichLesson(r.hint!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
                            ),
                          ]),
                        ),
                      if (showNext && !inlineNext)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6, right: 8),
                            child: nextButton(),
                          ),
                        ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
