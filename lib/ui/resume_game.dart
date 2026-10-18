import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../game/resume_store.dart';
import '../net/room_client.dart';
import '../room/room_session.dart';
import 'lobby_screen.dart';

/// Volta ao jogo em rede guardado: liga-se com o mesmo token (o anfitrião
/// devolve o mesmo lugar) e repõe a mão e o grimório.
Future<void> resumeGame(BuildContext context, WidgetRef ref, ResumeInfo info) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        SizedBox(width: 16),
        Expanded(child: Text('A voltar ao jogo…')),
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
      messenger.showSnackBar(const SnackBar(content: Text('Esse jogo já não existe.')));
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
      content: Text('Não foi possível voltar ao jogo: ${e.message}'),
      action: SnackBarAction(label: 'Esquecer', onPressed: () => ref.read(resumeProvider).clear()),
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
        title: Text('Jogo em curso: ${info.room}'),
        subtitle: const Text('A app fechou a meio do jogo. A tua mão e o grimório ficaram guardados.'),
        isThreeLine: true,
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
            onPressed: () => resumeGame(context, ref, info),
            child: const Text('Voltar'),
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
      title: const Text('Voltar ao jogo?'),
      content: Text('A app fechou durante o jogo em "${info.room}". '
          'A tua mão e o grimório ficaram guardados.'),
      actions: [
        TextButton(
          onPressed: () {
            ref.read(resumeProvider).clear();
            Navigator.pop(ctx, false);
          },
          child: const Text('Esquecer'),
        ),
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Agora não')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Voltar')),
      ],
    ),
  );
  if (go == true && context.mounted) await resumeGame(context, ref, info);
}
