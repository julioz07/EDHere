import 'dart:async';

import 'package:card_db/card_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../game/game_controller.dart';
import '../../game/solo_save.dart';
import '../table/table_screen.dart';
import '../table/tablet_table_screen.dart';
import '../../l10n/l10n.dart';

/// Playtest local com os decks escolhidos, no mesmo núcleo do jogo em rede.
/// Grava-se sozinho enquanto se joga; ao sair pergunta se fica gravado para
/// continuar depois.
class PlaytestScreen extends ConsumerStatefulWidget {
  const PlaytestScreen({
    super.key,
    required this.deckIds,
    this.names,
    this.randomFirst = false,
    this.tablet = false,
    this.openHands = false,
    this.resume,
  });

  /// Continuar este jogo gravado (os outros campos vêm dele).
  factory PlaytestScreen.resume(SoloSave save, {Key? key}) => PlaytestScreen(
        key: key,
        deckIds: save.deckIds,
        names: save.names,
        tablet: save.tablet,
        openHands: save.openHands,
        resume: save,
      );

  final List<int> deckIds;

  /// Nomes dos jogadores (no 1 contra 1); por defeito o meu nome.
  final List<String>? names;
  final bool randomFirst;

  /// Mesa partilhada: os dois à volta do mesmo ecrã.
  final bool tablet;

  /// Mãos à vista (para ensinar).
  final bool openHands;
  final SoloSave? resume;

  @override
  ConsumerState<PlaytestScreen> createState() => _PlaytestScreenState();
}

class _PlaytestScreenState extends ConsumerState<PlaytestScreen> {
  late final GameController _ctrl = _build();
  late final List<Deck> _decks;
  late final SoloSaveStore _saves = ref.read(soloSaveProvider);
  Timer? _debounce;

  /// Pode gravar por cima do que lá está (é este jogo, ou o jogador aceitou).
  late bool _mayWrite = widget.resume != null || _saves.save == null;

  GameController _build() {
    final store = ref.read(deckStoreProvider);
    final repo = ref.read(cardRepoProvider)!;
    final prints = ref.read(printsProvider);
    final r = widget.resume;
    // Um deck apagado entretanto: o jogo continua, só sem o nome no histórico.
    _decks = [
      for (var i = 0; i < widget.deckIds.length; i++)
        store.getDeck(widget.deckIds[i]) ?? Deck(name: 'Deck ${i + 1}', format: 'free'),
    ];
    if (r != null) {
      return GameController.restore(
        repo: repo,
        json: r.game,
        decks: {for (var i = 0; i < _decks.length; i++) i: _decks[i]},
        resolvePrint: (c, p) => prints.resolve(c, printId: p),
        effectivePrint: prints.effectivePrint,
      );
    }
    final format = GameFormat.byId(_decks.first.format);
    final player = ref.read(playerNameProvider);
    return GameController.playtest(
      repo: repo,
      resolvePrint: (c, p) => prints.resolve(c, printId: p),
      effectivePrint: prints.effectivePrint,
      format: format,
      randomFirst: widget.randomFirst,
      seats: [
        for (var i = 0; i < _decks.length; i++)
          SeatSetup(
            seat: i,
            name: widget.names != null && i < widget.names!.length
                ? widget.names![i]
                : (player.isEmpty ? tr('Eu') : player),
            deck: _decks[i],
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_changed);
    if (!_mayWrite) WidgetsBinding.instance.addPostFrameCallback((_) => _askReplace());
  }

  @override
  void dispose() {
    _ctrl.removeListener(_changed);
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// Já há outro jogo gravado: este novo só grava se o jogador aceitar.
  Future<void> _askReplace() async {
    final old = _saves.save;
    if (old == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Já tens um jogo gravado')),
        content: Text(tr('{title}, turno {turn}. Se jogares este, o gravado é substituído.',
            {'title': old.title, 'turn': old.turn})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Voltar'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Jogar este'))),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      _mayWrite = true;
      _write();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _changed() {
    if (_ctrl.state.over) {
      // Jogo acabado não se continua.
      _debounce?.cancel();
      if (_mayWrite) _saves.clear();
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _write);
  }

  void _write() {
    if (!_mayWrite || _ctrl.state.over) return;
    final names = _ctrl.state.players.values.map((p) => p.name).toList();
    _saves.write(SoloSave(
      deckIds: widget.deckIds,
      title: _decks.length == 1 ? tr('Goldfish · {v}', {'v': _decks.first.name}) : names.join(' vs '),
      turn: _ctrl.state.turn,
      savedAt: DateTime.now(),
      game: _ctrl.saveJson(),
      names: widget.names,
      tablet: widget.tablet,
      openHands: widget.openHands,
    ));
  }

  Future<bool> _confirmLeave(BuildContext context) async {
    if (_ctrl.state.over || !_mayWrite) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sair da mesa?')),
        content: Text(tr('Podes gravar o jogo como está e continuar depois, em Jogar.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'stay'), child: Text(tr('Ficar'))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'drop'), child: Text(tr('Sair sem gravar'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(tr('Gravar e sair'))),
        ],
      ),
    );
    switch (choice) {
      case 'save':
        _debounce?.cancel();
        _write();
        _saves.refresh();
        return true;
      case 'drop':
        _debounce?.cancel();
        _mayWrite = false;
        _saves.clear();
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.tablet
      ? TabletTableScreen(ctrl: _ctrl, openHands: widget.openHands, confirmLeave: _confirmLeave)
      : TableScreen(ctrl: _ctrl, confirmLeave: _confirmLeave);
}
