import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../bot/forge_engine.dart';
import '../../data/providers.dart';
import '../../data/settings.dart';
import '../../net/discovery.dart';
import '../bot/bot_setup_screen.dart';
import '../create_room_screen.dart';
import '../join_screen.dart';
import '../limited/jumpstart_screen.dart';
import '../limited/limited_builder.dart';
import '../limited/sealed_screen.dart';
import '../playtest/playtest_setup_screen.dart';
import '../resume_game.dart';
import '../stats/stats_screen.dart';
import '../tutorial/tutorial_home.dart';
import '../widgets/responsive.dart';
import '../../app/theme.dart';
import '../../l10n/l10n.dart';

class PlayTab extends ConsumerStatefulWidget {
  const PlayTab({super.key});

  @override
  ConsumerState<PlayTab> createState() => _PlayTabState();
}

class _PlayTabState extends ConsumerState<PlayTab> {
  late final TextEditingController _name = TextEditingController(text: ref.read(playerNameProvider));

  /// Ao voltar de outro ecrã o Flutter devolve o foco ao campo do nome (e
  /// abre o teclado). Enquanto há outro ecrã por cima, o campo não o aceita.
  final _nameFocus = FocusNode();

  /// O bot (motor do Forge) só corre no Android 8.0+; null enquanto não se sabe.
  bool? _botSupported;

  @override
  void initState() {
    super.initState();
    ForgeEngine.supported().then((v) {
      if (mounted) setState(() => _botSupported = v);
    });
  }

  /// Abre outro ecrã sem que o campo do nome fique com o foco ao voltar.
  Future<void> _push(Widget screen) async {
    _nameFocus.canRequestFocus = false;
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _nameFocus.canRequestFocus = true;
  }

  String get _playerName => _name.text.trim().isEmpty ? tr('Jogador') : _name.text.trim();

  Future<void> _go(Widget Function(String name) screen, {bool needsName = false}) async {
    // Numa sala os outros veem o nome: sem ele, ficam todos "Jogador".
    if (needsName && _name.text.trim().isEmpty) {
      final name = await _askName();
      if (name == null || !mounted) return;
      _name.text = name;
    }
    await ref.read(prefsProvider).setString('player_name', _name.text.trim());
    ref.read(playerNameProvider.notifier).state = _name.text.trim();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    await _push(screen(_playerName));
  }

  Future<String?> _askName() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Como te chamas?')),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 24,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: tr('O nome que os outros veem na mesa'), counterText: ''),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim().isEmpty ? null : c.text.trim()),
            child: Text(tr('Continuar')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasDecks = ref.watch(decksProvider).decks.isNotEmpty;
    final hasData = ref.watch(cardDataProvider).hasData;
    // Em ecrãs baixos o cabeçalho encolhe, para as ações aparecerem logo.
    final short = MediaQuery.sizeOf(context).height < 700;
    return Scaffold(
      // mais largo que os formulários: no tablet os modos ficam em duas colunas
      body: MaxWidth(
          max: 920,
          child: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(24, short ? 16 : 32, 24, 24),
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SvgPicture.asset(Brand.horizontal(theme.brightness), height: short ? 40 : 56),
              const SizedBox(height: 6),
              Text(tr('Joga com quem está aqui'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
            SizedBox(height: short ? 16 : 24),
            const ResumeCard(),
            const SoloResumeCard(),
            const LimitedBuildsCard(),
            TextField(
              controller: _name,
              focusNode: _nameFocus,
              // Larga o foco ao tocar fora (num botão, por exemplo): senão,
              // ao voltar de outro ecrã, o campo volta a abrir o teclado.
              onTapOutside: (_) => _nameFocus.unfocus(),
              onSubmitted: (_) => _nameFocus.unfocus(),
              textCapitalization: TextCapitalization.words,
              maxLength: 24,
              decoration: InputDecoration(
                labelText: tr('O teu nome'),
                helperText: tr('É o nome que os outros veem na mesa'),
                prefixIcon: const Icon(Icons.person_outline),
                counterText: '',
              ),
            ),
            const SizedBox(height: 24),
            // o modo principal em destaque; os outros em cartões, em duas colunas no tablet
            _ModeCard(
              hero: true,
              icon: Icons.smart_toy_outlined,
              title: tr('Jogar contra o bot'),
              subtitle: tr('Commander contra 1 a 4 bots, com as regras completas, sem internet'),
              onTap: hasData && hasDecks && _botSupported == true ? () => _go((_) => const BotSetupScreen()) : null,
            ),
            if (_botSupported == false)
              _Hint(tr('O bot precisa do Android 8.0 ou mais recente. O resto da app funciona normalmente.')),
            _Section(tr('Com outros, cada um com o seu telemóvel'), [
              _ModeCard(
                icon: Icons.add_circle_outline,
                title: tr('Criar sala'),
                subtitle: tr('Os outros entram com o telemóvel deles, na mesma rede'),
                onTap: hasData ? () => _go((n) => CreateRoomScreen(playerName: n), needsName: true) : null,
              ),
              _ModeCard(
                icon: Icons.wifi_find_rounded,
                title: tr('Entrar numa sala'),
                subtitle: tr('Procura as salas à tua volta ou lê o QR'),
                onTap: () => _go((n) => JoinScreen(playerName: n), needsName: true),
              ),
            ]),
            if (!hasData) _Hint(tr('Descarrega primeiro a base de cartas (Definições → Dados).')),
            _Section(tr('Abrir boosters'), [
              _ModeCard(
                icon: Icons.card_giftcard,
                title: tr('Sealed'),
                subtitle: tr('Abre 6 boosters e monta um deck de 40'),
                onTap: hasData ? () => _go((_) => const SealedSetupScreen()) : null,
              ),
              _ModeCard(
                icon: Icons.bolt,
                title: tr('JumpStart'),
                subtitle: tr('Junta dois pacotes temáticos e joga logo'),
                onTap: hasData ? () => _go((_) => const JumpstartScreen()) : null,
              ),
            ]),
            _Section(tr('Testar e ensinar'), [
              _ModeCard(
                icon: Icons.school_outlined,
                title: tr('Aprender a jogar Commander'),
                subtitle: tr('Um jogo guiado, passo a passo'),
                onTap: () => _go((_) => const TutorialHome()),
              ),
              _ModeCard(
                icon: Icons.science_outlined,
                title: tr('Goldfish'),
                subtitle: tr('Testa um deck sozinho'),
                onTap: hasDecks ? () => _go((_) => const GoldfishSetupScreen()) : null,
              ),
              _ModeCard(
                icon: Icons.people_alt_outlined,
                title: tr('Vários decks, um aparelho'),
                subtitle: tr('Testa decks uns contra os outros'),
                onTap: hasDecks ? () => _go((_) => const TestMatchSetupScreen()) : null,
              ),
              _ModeCard(
                icon: Icons.bar_chart,
                title: tr('Histórico e estatísticas'),
                subtitle: tr('As tuas partidas e vitórias'),
                onTap: () => _push(const StatsScreen()),
              ),
            ]),
            if (!hasDecks) _Hint(tr('Cria primeiro um deck.')),
            const SizedBox(height: 32),
            Text(
              tr('EDHere v{appVersion} · conteúdo de fãs não oficial, permitido pela Fan Content Policy. Não aprovado/endossado pela Wizards.',
                  {'appVersion': appVersion}),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ),
      )),
    );
  }
}

/// Um título de secção e os seus modos: uma lista no telemóvel, duas colunas no tablet.
class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: EdhSize.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: EdhSize.s),
        LayoutBuilder(builder: (context, box) {
          final two = box.maxWidth >= 640;
          final w = two ? (box.maxWidth - EdhSize.m) / 2 : box.maxWidth;
          return Wrap(spacing: EdhSize.m, runSpacing: EdhSize.s, children: [
            for (final c in children) SizedBox(width: w, child: c),
          ]);
        }),
      ]),
    );
  }
}

/// Um modo de jogo: ícone, nome e uma linha a dizer o que é. O [hero] é o
/// modo principal, maior e na cor da app. Sem [onTap], fica esbatido.
class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.icon, required this.title, required this.subtitle, this.onTap, this.hero = false});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = hero ? scheme.onPrimary : scheme.onSurface;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: hero ? scheme.primary : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EdhSize.radiusM),
          side: hero ? BorderSide.none : BorderSide(color: scheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(hero ? EdhSize.l : EdhSize.m),
            child: Row(children: [
              Container(
                width: hero ? 52 : 40,
                height: hero ? 52 : 40,
                decoration: BoxDecoration(
                  color: hero ? scheme.onPrimary.withOpacity(0.18) : scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: hero ? 28 : 22, color: hero ? scheme.onPrimary : scheme.primary),
              ),
              const SizedBox(width: EdhSize.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      // no telemóvel estreito, um tamanho abaixo: "Jogar contra o bot" cabe numa linha
                      style: (hero && MediaQuery.sizeOf(context).width >= 400
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.titleMedium)
                          ?.copyWith(color: fg, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: hero ? scheme.onPrimary.withOpacity(0.85) : scheme.onSurfaceVariant)),
                ]),
              ),
              Icon(Icons.chevron_right, color: hero ? scheme.onPrimary : scheme.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Uma nota curta por baixo de um modo (porque não está disponível).
class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}
