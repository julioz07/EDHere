import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/providers.dart';
import '../data/settings.dart';
import 'shell.dart';

/// Já se viu a introdução (guardado entre sessões).
const onboardingKey = 'onboarding_done';

/// Mostra a introdução na primeira vez (sem base de cartas e sem a ter visto)
/// e depois a app normal.
class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.read(prefsProvider).getBool(onboardingKey) ?? false;
    final hasData = ref.read(cardDataProvider).hasData;
    return seen || hasData ? const AppShell() : const OnboardingScreen();
  }
}

class _Slide {
  const _Slide(this.title, this.points, {this.image, this.icon});
  final String title;
  final List<(IconData, String)> points;

  /// Print da app (em assets/onboarding).
  final String? image;
  final IconData? icon;
}

const _slides = [
  _Slide(
    'Uma mesa de Magic no bolso',
    [
      (Icons.groups_outlined, 'Joga Commander (e outros formatos) com quem está ao teu lado.'),
      (Icons.wifi_off_rounded, 'Sem internet, sem contas, sem servidores: funciona em modo avião.'),
      (
        Icons.touch_app_outlined,
        'É uma mesa, não um árbitro: tu jogas as cartas e a app guarda vida, '
            'contadores, zonas e o registo.'
      ),
    ],
    image: 'assets/onboarding/table.jpg',
  ),
  _Slide(
    'Decks, cartas e boosters',
    [
      (Icons.search, 'Todas as cartas pesquisáveis offline, com as versões que escolheres.'),
      (Icons.style_outlined, 'Monta ou importa decks (Moxfield, Archidekt…) com validação e bracket.'),
      (Icons.card_giftcard, 'Abre boosters: sealed, draft, Commander draft e JumpStart.'),
    ],
    image: 'assets/onboarding/deck.jpg',
  ),
  _Slide(
    'Jogar juntos e aprender',
    [
      (Icons.router_outlined, 'Um cria a sala no Wi-Fi ou num hotspot; os outros entram pelo QR code.'),
      (Icons.smartphone, 'Cada um joga no seu telemóvel: a tua mão nunca sai do teu.'),
      (Icons.school_outlined, 'Nunca jogaste? O tutorial "Aprender a jogar Commander" ensina-te a jogar.'),
    ],
    image: 'assets/onboarding/room.jpg',
  ),
  _Slide(
    'Primeiro, as cartas',
    [
      (
        Icons.download_rounded,
        'Para jogar offline, a app descarrega a base de cartas uma vez (cerca de 30 MB, '
            'melhor em Wi-Fi).'
      ),
      (Icons.image_outlined, 'As imagens descarregam-se aos poucos, ou em pacotes nas Definições.'),
      (Icons.flight_rounded, 'Depois disso, tudo funciona sem rede.'),
    ],
    icon: Icons.cloud_download_outlined,
  ),
];

/// Introdução da primeira vez: o que é a app, como funciona e, no fim, o
/// download da base de cartas.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.replay = false});

  /// Vista outra vez (das Definições): no fim só fecha.
  final bool replay;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  bool get _last => _page == _slides.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int page) =>
      _pages.animateToPage(page, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);

  Future<void> _finish({required bool download}) async {
    final prefs = ref.read(prefsProvider);
    final data = ref.read(cardDataProvider);
    final nav = Navigator.of(context);
    if (widget.replay) {
      nav.pop();
    } else {
      // O separador Cartas mostra o progresso do download.
      nav.pushReplacement(MaterialPageRoute<void>(builder: (_) => AppShell(startDownload: download)));
    }
    await prefs.setBool(onboardingKey, true);
    if (widget.replay && download && !data.hasData) await data.update(includeRulings: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = ref.watch(cardDataProvider).hasData;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(children: [
              SvgPicture.asset(Brand.horizontal(theme.brightness), height: 30),
              const Spacer(),
              // A mesma altura em todos os passos (o logótipo não salta).
              SizedBox(
                height: 48,
                child: _last
                    ? null
                    : TextButton(
                        style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                        onPressed: () => _go(_slides.length - 1),
                        child: const Text('Saltar'),
                      ),
              ),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: _slides.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i == _page ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                    ),
                  ),
              ]),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _last
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                            FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                              onPressed: () => _finish(download: true),
                              icon: Icon(hasData ? Icons.check_rounded : Icons.download_rounded),
                              label: Text(hasData ? 'Começar' : 'Descarregar as cartas e começar'),
                            ),
                            if (!hasData)
                              TextButton(
                                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                                onPressed: () => _finish(download: false),
                                child: const Text('Mais tarde (Definições → Dados)'),
                              ),
                          ])
                    : Row(children: [
                        if (_page > 0)
                          TextButton(
                            style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                            onPressed: () => _go(_page - 1),
                            child: const Text('Anterior'),
                          ),
                        const Spacer(),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                          onPressed: () => _go(_page + 1),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Seguinte'),
                        ),
                      ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget picture(double maxH) => slide.image != null
        ? ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: AspectRatio(
              aspectRatio: 540 / 1120,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: theme.colorScheme.outline, width: 3),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 18, offset: Offset(0, 6))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(19),
                  child: Image.asset(slide.image!, fit: BoxFit.cover, alignment: Alignment.topCenter),
                ),
              ),
            ),
          )
        : Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primaryContainer),
            child: Icon(slide.icon, size: 72, color: theme.colorScheme.primary),
          );

    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(slide.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        for (final (icon, line) in slide.points)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(line, style: theme.textTheme.bodyLarge?.copyWith(height: 1.35))),
            ]),
          ),
      ],
    );

    return LayoutBuilder(builder: (context, box) {
      // Deitado (telemóvel ou tablet): imagem à esquerda, texto à direita.
      if (box.maxWidth > box.maxHeight * 1.1) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          child: Row(children: [
            Expanded(child: Center(child: picture(box.maxHeight - 24))),
            const SizedBox(width: 32),
            Expanded(child: SingleChildScrollView(child: text)),
          ]),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(children: [
              Center(child: picture(box.maxHeight * 0.52)),
              const SizedBox(height: 22),
              text,
            ]),
          ),
        ),
      );
    });
  }
}
