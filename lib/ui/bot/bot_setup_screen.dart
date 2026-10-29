import 'dart:async';
import 'dart:math';

import 'package:card_db/card_db.dart' hide Card;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../bot/forge_engine.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../widgets/responsive.dart';
import 'bot_table_screen.dart';

/// Preparar uma partida contra o bot: o meu deck, quantos bots (1 a 4), o deck
/// de cada um e a dificuldade.
class BotSetupScreen extends ConsumerStatefulWidget {
  const BotSetupScreen({super.key, this.deckId});

  /// O meu deck já escolhido (vindo do menu de um deck).
  final int? deckId;

  @override
  ConsumerState<BotSetupScreen> createState() => _BotSetupScreenState();
}

class _BotSetupScreenState extends ConsumerState<BotSetupScreen> {
  int? _myDeck;

  /// O deck de cada bot (o tamanho é o número de adversários).
  List<int?> _botDecks = [null];
  BotLevel _level = BotLevel.normal;

  /// Memória do aparelho (MB): com 3 ou 4 bots num aparelho modesto, avisa-se.
  int? _memoryMb;
  bool _busy = false;

  /// Progresso do arranque do motor (0 a 1), enquanto não está pronto.
  double? _loading;
  bool _ready = false;
  StreamSubscription<Map<String, dynamic>>? _progress;

  @override
  void initState() {
    super.initState();
    final ids = [
      for (final d in ref.read(decksProvider).decks)
        if (d.playableCount > 0) d.id!,
    ];
    if (ids.isNotEmpty) {
      _myDeck = ids.contains(widget.deckId) ? widget.deckId : ids.first;
      // o do bot: outro do mesmo formato, como ao mudar o número de adversários
      _botDecks = [];
      _setBots(1);
    }
    ForgeEngine.memoryMb().then((v) {
      if (mounted) setState(() => _memoryMb = v);
    });
    // O motor demora uns segundos a arrancar: começa já, enquanto se escolhem
    // os decks. Se falhar, "Jogar" tenta outra vez e mostra o erro.
    _progress = ForgeEngine.events.listen((e) {
      if (e['type'] != 'loading' || !mounted || _ready) return;
      final max = (e['max'] as int?) ?? 100;
      setState(() => _loading = ((e['value'] as int?) ?? 0) / (max <= 0 ? 100 : max));
    });
    ForgeEngine.init().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _progress?.cancel();
    super.dispose();
  }

  /// Muda o número de adversários: os novos ficam com os decks seguintes (outros que não o meu, se houver).
  void _setBots(int n) {
    final decks = ref.read(decksProvider).decks.where((d) => d.playableCount > 0).toList();
    // primeiro os do mesmo formato que o meu: misturar formatos tira o Commander à partida
    final format = decks.where((d) => d.id == _myDeck).firstOrNull?.format;
    final same = decks.where((d) => d.format == format).toList();
    final ids = [for (final d in same.length > 1 ? same : decks) d.id!];
    final others = ids.where((id) => id != _myDeck).toList();
    final pool = others.isEmpty ? ids : others;
    setState(() {
      _botDecks = [
        for (var i = 0; i < n; i++)
          i < _botDecks.length ? _botDecks[i] : (pool.isEmpty ? null : pool[i % pool.length]),
      ];
    });
  }

  bool get _ok => _myDeck != null && _botDecks.every((d) => d != null);

  /// No deck de um bot: um ao calhas, só se sabe qual na mesa.
  static const _random = -1;

  /// O deck ao calhas: um do meu formato que não seja o meu (se houver).
  int _randomDeck(Random rng) {
    final decks = ref.read(decksProvider).decks.where((d) => d.playableCount > 0).toList();
    final format = decks.where((d) => d.id == _myDeck).firstOrNull?.format;
    for (final pool in [
      decks.where((d) => d.format == format && d.id != _myDeck),
      decks.where((d) => d.id != _myDeck),
      decks,
    ]) {
      final ids = [for (final d in pool) d.id!];
      if (ids.isNotEmpty) return ids[rng.nextInt(ids.length)];
    }
    return _myDeck!;
  }

  /// [watch]: o meu deck também fica com um bot (para ver o motor a jogar).
  Future<void> _start({bool watch = false}) async {
    final store = ref.read(deckStoreProvider);
    final repo = ref.read(cardRepoProvider);
    final mine = store.getDeck(_myDeck!);
    final rng = Random();
    final theirs = [for (final id in _botDecks) store.getDeck(id == _random ? _randomDeck(rng) : id!)];
    if (repo == null || mine == null || theirs.any((d) => d == null)) return;
    final all = [mine, ...theirs.whereType<Deck>()];
    final commander = all.every((d) => d.format == 'commander');
    if (commander && all.any((d) => d.count(Board.command) == 0)) {
      _snack(tr('Em Commander, todos os decks precisam de um comandante.'));
      return;
    }
    // o motor só joga Commander com todos os decks de Commander: com um Brawl, um
    // Oathbreaker ou outro qualquer, a partida é sem comandante e a 20 vidas
    if (!commander && all.any((d) => d.format == 'commander' || d.count(Board.command) > 0)) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Partida sem comandante')),
          content: Text(tr(
              'Nem todos os decks são de Commander, por isso a partida é normal: 20 vidas e sem zona de comando. Para jogar Commander, escolhe só decks de Commander.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Jogar assim'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Mudar os decks'))),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    final player = ref.read(playerNameProvider);
    final n = theirs.length;
    final seats = [
      watch
          ? ForgeSeat(name: tr('Bot 1'), deck: mine, bot: BotLevel.normal)
          : ForgeSeat(name: player.isEmpty ? tr('Jogador') : player, deck: mine),
      for (var i = 0; i < n; i++)
        ForgeSeat(
          // com um só, o nível no nome; com vários, numerados (o nível é o mesmo para todos)
          name: n == 1 ? tr('Bot ({v})', {'v': _level.label}) : tr('Bot {n}', {'n': i + (watch ? 2 : 1)}),
          deck: theirs[i]!,
          bot: _level,
        ),
    ];
    setState(() => _busy = true);
    try {
      await ForgeEngine.init();
      final missing = await ForgeEngine.checkDecks(seats, repo);
      if (!mounted) return;
      final unknown = {for (final m in missing) ...m}.toList()..sort();
      if (unknown.isNotEmpty && !await _confirmMissing(unknown)) return;
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => BotTableScreen(seats: seats, commander: commander),
      ));
    } on Exception catch (e) {
      _snack(tr('Não foi possível arrancar o bot: {v}', {'v': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmMissing(List<String> names) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Cartas que o bot ainda não conhece')),
        content: SingleChildScrollView(
          child: Text(
            '${tr('O motor do bot ainda não sabe jogar estas cartas, por isso ficam de fora da partida:')}\n\n'
            '${names.join('\n')}',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Jogar sem elas'))),
        ],
      ),
    );
    return ok ?? false;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).decks.where((d) => d.playableCount > 0).toList();
    final bots = _botDecks.length;
    final theme = Theme.of(context);
    DropdownButtonFormField<int> deckField(String label, int? value, ValueChanged<int?> onChanged,
            {Color? color, bool random = false}) =>
        DropdownButtonFormField<int>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            // a cor do lugar na mesa: a mesma com que aparece lá
            prefixIcon: color == null
                ? null
                : Icon(Icons.circle, size: 14, color: color),
          ),
          items: [
            if (random)
              DropdownMenuItem(
                value: _random,
                child: Row(children: [
                  const Icon(Icons.shuffle, size: 18),
                  const SizedBox(width: 8),
                  Flexible(child: Text(tr('Deck aleatório'), overflow: TextOverflow.ellipsis)),
                ]),
              ),
            for (final d in decks)
              DropdownMenuItem(
                value: d.id,
                // o formato só quando não é Commander: no telemóvel cortava o nome, e
                // assim salta à vista o deck que vai tirar o comandante à partida
                child: Text(d.format == 'commander' ? d.name : '${d.name} · ${GameFormat.byId(d.format).label}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        );
    return Scaffold(
      appBar: AppBar(title: FitText(tr('Jogar contra o bot'), alignment: Alignment.centerLeft)),
      body: Column(children: [
        Expanded(
          child: MaxWidth(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text(
                bots == 1
                    ? tr('Uma partida 1 contra 1 com as regras completas: o bot é o motor do Forge, que aplica as regras e joga sozinho. Funciona sem internet.')
                    : tr('Commander a {n}: tu contra {b} bots, com as regras completas. Cada bot pensa na sua vez, por isso a partida é mais longa, como numa mesa a sério.',
                        {'n': bots + 1, 'b': bots}),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(tr('Adversários'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [for (var i = 1; i <= 4; i++) ButtonSegment(value: i, label: Text('$i'))],
                selected: {bots},
                onSelectionChanged: (s) => _setBots(s.first),
              ),
              if (bots >= 3 && _memoryMb != null && _memoryMb! < 6000)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline, size: 18, color: EdhColors.warn),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          tr('Este aparelho tem pouca memória para {n} bots: a partida pode ficar lenta. Com 1 ou 2 corre melhor.',
                              {'n': bots}),
                          style: theme.textTheme.bodySmall),
                    ),
                  ]),
                ),
              const SizedBox(height: 16),
              deckField(tr('O teu deck'), _myDeck, (v) => setState(() => _myDeck = v), color: GameColors.player(0)),
              for (var i = 0; i < bots; i++) ...[
                const SizedBox(height: 12),
                deckField(
                  bots == 1 ? tr('O deck do bot') : tr('O deck do bot {n}', {'n': i + 1}),
                  _botDecks[i],
                  (v) => setState(() => _botDecks[i] = v),
                  color: GameColors.player(i + 1),
                  random: true,
                ),
              ],
              const SizedBox(height: 20),
              Text(tr('Dificuldade'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<BotLevel>(
                // sem o visto: em ecrãs pequenos parte "Normal" em duas linhas
                showSelectedIcon: false,
                segments: [for (final l in BotLevel.values) ButtonSegment(value: l, label: Text(l.label))],
                selected: {_level},
                onSelectionChanged: (s) => setState(() => _level = s.first),
              ),
              const SizedBox(height: 8),
              Text(switch (_level) {
                BotLevel.easy => tr('Comete erros de propósito: às vezes não joga o que podia, ataca com menos criaturas ou esquece-se de bloquear.'),
                BotLevel.normal => tr('O bot do Forge tal como é: joga bem, sem batota.'),
                BotLevel.hard => tr('Pensa mais em cada jogada e tem baralhamentos que lhe dão melhor mana.'),
              }, style: theme.textTheme.bodySmall),
              if (decks.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(tr('Cria primeiro um deck.'), style: theme.textTheme.bodySmall),
                ),
            ]),
          ),
        ),
        BottomActions(children: [
          // o motor do bot a arrancar (da primeira vez, ou com a app acabada de abrir, demora mais)
          if (!_ready)
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(
                _loading == null
                    ? tr('A preparar o motor do bot…')
                    : tr('A preparar o motor do bot… {n}%', {'n': ((_loading ?? 0) * 100).round()}),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: _loading, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            ]),
          OutlinedButton.icon(
            onPressed: _busy || !_ok ? null : () => _start(watch: true),
            icon: const Icon(Icons.visibility_outlined),
            label: Text(tr('Ver o bot a jogar')),
          ),
          FilledButton.icon(
            onPressed: _busy || !_ok ? null : _start,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_busy ? tr('A preparar o bot…') : tr('Jogar')),
          ),
        ]),
      ]),
    );
  }
}
