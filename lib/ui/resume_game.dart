import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../game/resume_store.dart';
import '../net/room_client.dart';
import '../room/room_session.dart';
import 'lobby_screen.dart';
import 'playtest/playtest_screen.dart';
import '../l10n/l10n.dart';

/// Volta ao jogo em rede guardado: liga-se com o mesmo token (o anfitrião
/// devolve o mesmo lugar) e repõe a mão e o grimório.
Future<void> resumeGame(BuildContext context, WidgetRef ref, ResumeInfo info) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(width: 16),
        Expanded(child: Text(tr('A voltar ao jogo…'))),
      ]),
    ),
  );
  final client = RoomClient(
    hosts: info.hosts,
    port: info.port,
    playerName: info.name,
    pin: info.pin,
    token: info.token,
  );
  try {
    await client.connect();
    navigator.pop();
    if (client.mySeat != info.seat) {
      // O anfitrião já não conhece este lugar (a sala é outra ou recomeçou).
      await client.leave();
      ref.read(resumeProvider).clear();
      messenger.showSnackBar(SnackBar(content: Text(tr('Esse jogo já não existe.'))));
      return;
    }
    final session = RoomSession.client(client: client, roomName: client.roomName ?? info.room);
    await navigator.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'lobby'),
      builder: (_) => LobbyScreen(session: session, resume: info),
    ));
  } on RoomJoinException catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(tr('Não foi possível voltar ao jogo: {message}', {'message': e.message})),
      action: SnackBarAction(label: tr('Esquecer'), onPressed: () => ref.read(resumeProvider).clear()),
    ));
  }
}

/// Cartão "Voltar ao jogo" (separador Jogar).
class ResumeCard extends ConsumerWidget {
  const ResumeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(resumeProvider).current;
    if (info == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      margin: const EdgeInsets.only(bottom: 20),
      child: ListTile(
        leading: const Icon(Icons.replay_circle_filled_rounded),
        title: Text(tr('Jogo em curso: {room}', {'room': info.room})),
        subtitle: Text(tr('A app fechou a meio do jogo. A tua mão e o grimório ficaram guardados.')),
        isThreeLine: true,
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
            onPressed: () => resumeGame(context, ref, info),
            child: Text(tr('Voltar')),
          ),
        ]),
        onLongPress: () => ref.read(resumeProvider).clear(),
      ),
    );
  }
}

/// Ao abrir a app: pergunta se quer voltar ao jogo que ficou a meio.
Future<void> offerResume(BuildContext context, WidgetRef ref) async {
  final info = ref.read(resumeProvider).current;
  if (info == null) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.replay_circle_filled_rounded),
      title: Text(tr('Voltar ao jogo?')),
      content: Text(tr('A app fechou durante o jogo em "{room}". A tua mão e o grimório ficaram guardados.',
          {'room': info.room})),
      actions: [
        TextButton(
          onPressed: () {
            ref.read(resumeProvider).clear();
            Navigator.pop(ctx, false);
          },
          child: Text(tr('Esquecer')),
        ),
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Agora não'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Voltar'))),
      ],
    ),
  );
  if (go == true && context.mounted) await resumeGame(context, ref, info);
}

/// Cartão "Continuar jogo" de um goldfish ou 1 contra 1 gravado.
class SoloResumeCard extends ConsumerWidget {
  const SoloResumeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final save = ref.watch(soloSaveProvider).save;
    if (save == null || ref.watch(cardRepoProvider) == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final d = save.savedAt;
    final when = tr('{day}/{month} às {hour}:{v}',
        {'day': d.day, 'month': d.month, 'hour': d.hour, 'v': d.minute.toString().padLeft(2, '0')});
    return Card(
      color: scheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: 20),
      child: ListTile(
        leading: const Icon(Icons.bookmark_rounded),
        title: Text(save.title),
        subtitle: Text(tr('Jogo gravado · turno {turn} · {when}', {'turn': save.turn, 'when': when})),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: tr('Apagar'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(tr('Apagar o jogo gravado?')),
                  content: Text(tr('{title}, turno {turn}.', {'title': save.title, 'turn': save.turn})),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Apagar'))),
                  ],
                ),
              );
              if (ok == true) ref.read(soloSaveProvider).clear();
            },
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => PlaytestScreen.resume(save),
            )),
            child: Text(tr('Continuar')),
          ),
        ]),
      ),
    );
  }
}
