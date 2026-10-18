import 'package:card_db/card_db.dart' hide Card;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/theme.dart';
import '../data/providers.dart';
import '../game/network_game.dart';
import '../net/room_link.dart';
import '../room/room_session.dart';
import 'room_screen.dart';
import 'table/table_screen.dart';
import 'widgets/responsive.dart';

/// Lobby de uma sala: cada jogador escolhe o deck e fica pronto; o
/// anfitrião começa o jogo. Depois mostra a mesa.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, required this.session, this.format, this.life});

  final RoomSession session;

  /// Valores iniciais escolhidos pelo anfitrião ao criar a sala.
  final String? format;
  final int? life;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  late final NetworkGame _game = NetworkGame(
    session: widget.session,
    repo: ref.read(cardRepoProvider)!,
    prints: ref.read(printsProvider),
    images: ref.read(imagesProvider),
  );
  bool _closing = false;
  bool _tableShown = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    if (widget.session.isHost && widget.format != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _game.configure(format: widget.format!, life: widget.life ?? 40));
    }
    _game.addListener(_maybeShowTable);
  }

  void _maybeShowTable() {
    final g = _game.game;
    if (g == null || _tableShown || !mounted) return;
    if (!g.state.players.containsKey(_game.mySeat)) {
      // Fiquei de fora (não estava pronto): vejo como espectador.
      g.viewSeat = g.state.activeSeat;
    }
    _tableShown = true;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
      builder: (_) => ListenableBuilder(
        listenable: _game,
        builder: (context, _) => TableScreen(
          ctrl: g,
          banner: switch (_game.link.status) {
            LinkStatus.reconnecting => const MaterialBanner(
                content: Text('Ligação perdida. A voltar a ligar…'),
                leading: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                actions: [SizedBox.shrink()],
              ),
            LinkStatus.closed => const MaterialBanner(
                content: Text('A sala foi fechada.'),
                leading: Icon(Icons.link_off),
                actions: [SizedBox.shrink()],
              ),
            _ => null,
          },
          onLeave: _leaveRoom,
        ),
      ),
    ))
        .then((_) {
      if (mounted && !_closing) Navigator.of(context).pop();
    });
  }

  Future<void> _leaveRoom() async {
    if (_closing) return;
    _closing = true;
    await widget.session.close();
  }

  @override
  void dispose() {
    _game.removeListener(_maybeShowTable);
    _game.dispose();
    WakelockPlus.disable();
    if (!_closing) widget.session.close();
    super.dispose();
  }

  Future<void> _pickDeck() async {
    final decks = ref.read(decksProvider).decks;
    final repo = ref.read(cardRepoProvider)!;
    final format = GameFormat.byId(_game.format);
    final chosen = await showModalBottomSheet<Deck>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Escolher deck (${format.label})', style: Theme.of(ctx).textTheme.titleMedium),
          ),
          if (decks.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Ainda não tens decks.')),
          for (final d in decks)
            ListTile(
              title: Text(d.name),
              subtitle: Text('${GameFormat.byId(d.format).label} · ${d.playableCount} cartas'),
              onTap: () => Navigator.pop(ctx, d),
            ),
        ]),
      ),
    );
    if (chosen == null) return;
    final cards = repo.getMany(chosen.entries.map((e) => e.oracleId));
    final issues = validateDeck(chosen, format, cards, repo.legalityIn(format.legalityKey ?? '', cards.keys));
    final legal = issues.where((i) => i.level == IssueLevel.error).isEmpty;
    _game.selectDeck(
      chosen,
      legal: legal,
      commanderNames: [
        for (final e in chosen.inBoard(Board.command)) cards[e.oracleId]?.name ?? '?',
      ],
    );
    if (!legal && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('O deck tem ${issues.length} avisos para ${format.label}. Podes jogar na mesma.'),
      ));
    }
  }

  Future<void> _configure() async {
    var format = _game.format;
    var life = _game.startingLife;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Regras da sala'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: format,
              decoration: const InputDecoration(labelText: 'Formato'),
              items: [for (final f in GameFormat.all) DropdownMenuItem(value: f.id, child: Text(f.label))],
              onChanged: (v) => set(() {
                format = v ?? format;
                life = GameFormat.byId(format).startingLife;
              }),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Vida inicial'),
              const Spacer(),
              IconButton(onPressed: () => set(() => life--), icon: const Icon(Icons.remove)),
              Text('$life', style: Theme.of(ctx).textTheme.titleMedium),
              IconButton(onPressed: () => set(() => life++), icon: const Icon(Icons.add)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            TextButton(
              onPressed: () {
                _game.configure(format: format, life: life);
                Navigator.pop(ctx);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(widget.session.isHost ? 'Fechar a sala?' : 'Sair da sala?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ficar')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sair')),
            ],
          ),
        );
        if (ok == true) {
          await _leaveRoom();
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: ListenableBuilder(
        listenable: _game,
        builder: (context, _) {
          final theme = Theme.of(context);
          final g = _game;
          final format = GameFormat.byId(g.format);
          final me = g.me;
          final status = g.link.status;
          return Scaffold(
            appBar: AppBar(
              title: Text(widget.session.roomName, overflow: TextOverflow.ellipsis),
              actions: [
                if (widget.session.isHost)
                  IconButton(
                    tooltip: 'QR code',
                    icon: const Icon(Icons.qr_code_2),
                    onPressed: () => showRoomQr(context, widget.session),
                  ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'diag') {
                      Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => RoomScreen(session: widget.session, diagnostics: true),
                      ));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'diag', child: Text('Diagnóstico de rede')),
                  ],
                ),
              ],
            ),
            body: MaxWidth(
                child: ListView(padding: const EdgeInsets.all(16), children: [
              if (status == LinkStatus.reconnecting)
                const Card(
                    child: ListTile(leading: CircularProgressIndicator(), title: Text('A voltar a ligar…'))),
              if (status == LinkStatus.closed && !_closing)
                const Card(
                    child: ListTile(leading: Icon(Icons.link_off), title: Text('A sala foi fechada.'))),
              Card(
                child: ListTile(
                  leading: Icon(Icons.rule, color: theme.colorScheme.primary),
                  title: Text('${format.label} · vida ${g.startingLife}'),
                  subtitle: Text('${g.players.length} jogadores na sala'),
                  trailing: g.isHost ? const Icon(Icons.edit) : null,
                  onTap: g.isHost ? _configure : null,
                ),
              ),
              const SizedBox(height: 16),
              Text('Jogadores', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final p in g.players.values)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      p.isHost ? Icons.star_rounded : Icons.person,
                      color: p.connected ? EdhColors.ok : EdhColors.bad,
                    ),
                    title: Text(p.seat == g.mySeat ? '${p.name} (tu)' : p.name),
                    subtitle: Text(p.deckName == null
                        ? 'Ainda sem deck'
                        : '${p.deckName} · ${p.deckSize} cartas'
                            '${p.commanders.isEmpty ? '' : ' · ${p.commanders.join(' + ')}'}'
                            '${p.deckLegal ? '' : ' · com avisos'}'),
                    trailing: p.ready
                        ? const Chip(label: Text('Pronto'), backgroundColor: Color(0x333FB27F))
                        : const Chip(label: Text('A escolher')),
                  ),
                ),
              for (final p in g.players.values)
                if (g.missingFrom(p.seat) case final missing when missing.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: theme.colorScheme.primaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.image_outlined),
                      title: Text('${p.name} tem ${missing.length} imagens que não tens'),
                      subtitle: Text(g.transfer?.seat == p.seat
                          ? 'A receber do dispositivo de ${p.name}… ${g.transfer!.received}/${g.transfer!.expected}'
                          : '~${(missing.length * smallImageBytes / 1024 / 1024).toStringAsFixed(1)} MB · '
                              'da internet ou, sem rede, do telemóvel de ${p.name}'),
                      trailing: g.downloadingFrom == p.seat || g.transfer?.seat == p.seat
                          ? const SizedBox.square(
                              dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : FilledButton(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                              onPressed: () => g.downloadMissing(p.seat),
                              child: const Text('Descarregar'),
                            ),
                    ),
                  ),
              const SizedBox(height: 16),
              if (me != null) ...[
                OutlinedButton.icon(
                  onPressed: me.ready ? null : _pickDeck,
                  icon: const Icon(Icons.style_outlined),
                  label: Text(g.myDeck == null ? 'Escolher deck' : 'Trocar deck (${g.myDeck!.name})'),
                ),
                const SizedBox(height: 10),
                FilledButton.tonal(
                  onPressed: g.myDeck == null ? null : () => g.setReady(!me.ready),
                  child: Text(me.ready ? 'Já não estou pronto' : 'Estou pronto'),
                ),
              ],
              if (g.isHost) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: g.players.values.any((p) => p.ready) ? () => g.start() : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(g.allReady ? 'Começar jogo' : 'Começar (só com quem está pronto)'),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Cada um joga com o seu telemóvel. A mão e o grimório de cada jogador nunca saem '
                'do telemóvel dele.',
                style: theme.textTheme.bodySmall,
              ),
            ])),
          );
        },
      ),
    );
  }
}
