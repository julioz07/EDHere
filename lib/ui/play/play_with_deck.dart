import 'package:card_db/card_db.dart' show Deck, GameFormat;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../bot/bot_setup_screen.dart';
import '../create_room_screen.dart';
import '../join_screen.dart';
import '../playtest/playtest_screen.dart';

/// "Como te chamas?": numa sala os outros veem o nome (sem ele ficam todos
/// "Jogador"). Null se a pessoa cancelar.
Future<String?> askPlayerName(BuildContext context) {
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

/// Ir de um deck direto para um jogo com ele já escolhido: contra o bot, numa
/// sala nova, na sala de outro ou sozinho (pedido de um jogador: antes era
/// preciso ir ao separador Jogar e voltar a escolher o deck).
Future<void> showPlayWithDeck(BuildContext context, WidgetRef ref, Deck deck, {required bool botSupported}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(tr('Jogar com {v}', {'v': deck.name}),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(ctx).textTheme.titleMedium),
          ),
          if (botSupported)
            ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: Text(tr('Jogar contra o bot')),
              subtitle: Text(deck.format == 'commander'
                  ? tr('Commander contra 1 a 4 bots, com as regras completas, sem internet')
                  : tr('{v} contra o bot, com as regras completas, sem internet',
                      {'v': GameFormat.byId(deck.format).label})),
              onTap: () => Navigator.pop(ctx, 'bot'),
            ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: Text(tr('Criar sala')),
            subtitle: Text(tr('Os outros entram com o telemóvel deles, na mesma rede')),
            onTap: () => Navigator.pop(ctx, 'host'),
          ),
          ListTile(
            leading: const Icon(Icons.wifi_find_rounded),
            title: Text(tr('Entrar numa sala')),
            subtitle: Text(tr('Procura as salas à tua volta ou lê o QR')),
            onTap: () => Navigator.pop(ctx, 'join'),
          ),
          ListTile(
            leading: const Icon(Icons.play_arrow_rounded),
            title: Text(tr('Testar (goldfish)')),
            subtitle: Text(tr('Jogar o deck sozinho, sem adversário')),
            onTap: () => Navigator.pop(ctx, 'test'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  Future<String?> name() async {
    var n = ref.read(playerNameProvider).trim();
    if (n.isNotEmpty) return n;
    n = (await askPlayerName(context))?.trim() ?? '';
    if (n.isEmpty) return null;
    await ref.read(prefsProvider).setString('player_name', n);
    ref.read(playerNameProvider.notifier).state = n;
    return n;
  }

  final Widget screen;
  switch (choice) {
    case 'bot':
      screen = BotSetupScreen(deckId: deck.id);
    case 'test':
      screen = PlaytestScreen(deckIds: [deck.id!]);
    case 'host':
      final n = await name();
      if (n == null) return;
      screen = CreateRoomScreen(playerName: n, deck: deck);
    default:
      final n = await name();
      if (n == null) return;
      screen = JoinScreen(playerName: n, deck: deck);
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}
