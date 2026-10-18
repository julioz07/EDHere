import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/providers.dart';
import '../../data/settings.dart';
import '../../net/discovery.dart';
import '../create_room_screen.dart';
import '../join_screen.dart';
import '../limited/jumpstart_screen.dart';
import '../limited/limited_builder.dart';
import '../limited/sealed_screen.dart';
import '../playtest/playtest_setup_screen.dart';
import '../resume_game.dart';
import '../stats/stats_screen.dart';
import '../widgets/responsive.dart';

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

  /// Abre outro ecrã sem que o campo do nome fique com o foco ao voltar.
  Future<void> _push(Widget screen) async {
    _nameFocus.canRequestFocus = false;
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _nameFocus.canRequestFocus = true;
  }

  String get _playerName => _name.text.trim().isEmpty ? 'Jogador' : _name.text.trim();

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
        title: const Text('Como te chamas?'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 24,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'O nome que os outros veem na mesa', counterText: ''),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim().isEmpty ? null : c.text.trim()),
            child: const Text('Continuar'),
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
    return Scaffold(
      body: MaxWidth(
          child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SvgPicture.asset(Brand.horizontal(theme.brightness), height: 56),
              const SizedBox(height: 6),
              Text('Joga com quem está aqui',
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 24),
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
              decoration: const InputDecoration(
                labelText: 'O teu nome',
                helperText: 'É o nome que os outros veem na mesa',
                prefixIcon: Icon(Icons.person_outline),
                counterText: '',
              ),
            ),
            const SizedBox(height: 24),
            Text('Com outros, cada um com o seu telemóvel', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: hasData ? () => _go((n) => CreateRoomScreen(playerName: n), needsName: true) : null,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Criar sala'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _go((n) => JoinScreen(playerName: n), needsName: true),
              icon: const Icon(Icons.wifi_find_rounded),
              label: const Text('Entrar numa sala'),
            ),
            if (!hasData)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Descarrega primeiro a base de cartas (Definições → Dados).',
                    style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 24),
            Text('Abrir boosters', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: hasData ? () => _go((_) => const SealedSetupScreen()) : null,
                  icon: const Icon(Icons.card_giftcard),
                  label: const Text('Sealed'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: hasData ? () => _go((_) => const JumpstartScreen()) : null,
                  icon: const Icon(Icons.bolt),
                  label: const Text('JumpStart'),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            Text('Testar e ensinar', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: hasDecks ? () => _go((_) => const GoldfishSetupScreen()) : null,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Goldfish (testar um deck sozinho)'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: hasDecks ? () => _go((_) => const DuelSetupScreen()) : null,
              icon: const Icon(Icons.people_alt_outlined),
              label: const Text('1 contra 1 neste dispositivo'),
            ),
            if (!hasDecks)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Cria primeiro um deck.', style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  _push(const StatsScreen()),
              icon: const Icon(Icons.bar_chart),
              label: const Text('Histórico e estatísticas'),
            ),
            const SizedBox(height: 32),
            Text(
              'EDHere v$appVersion · conteúdo de fãs não oficial, permitido pela Fan Content '
              'Policy. Não aprovado/endossado pela Wizards.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ),
      )),
    );
  }
}
