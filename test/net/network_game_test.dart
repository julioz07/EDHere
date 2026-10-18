import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:edhoff/data/app_paths.dart';
import 'package:edhoff/data/image_service.dart';
import 'package:edhoff/game/network_game.dart';
import 'package:edhoff/net/host_server.dart';
import 'package:edhoff/net/room_client.dart';
import 'package:edhoff/room/room_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesa_core/mesa_core.dart';
import 'package:sqlite3/open.dart';

void _setUpSqlite() {
  if (!Platform.isWindows) return;
  for (final p in [Platform.environment['SQLITE3_DLL'], r'C:\Python313\DLLs\sqlite3.dll']) {
    if (p != null && File(p).existsSync()) {
      open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(p));
      return;
    }
  }
}

Map<String, dynamic> _card(String name, String type) => {
      'id': 'p-$name',
      'oracle_id': 'o-$name',
      'name': name,
      'layout': 'normal',
      'type_line': type,
      'oracle_text': '',
      'mana_cost': '',
      'cmc': 0,
      'colors': <String>[],
      'color_identity': <String>[],
      'legalities': {'commander': 'legal'},
      'games': ['paper'],
      // Endereço inacessível: obriga a pedir as imagens ao outro dispositivo.
      'image_uris': {'small': 'http://127.0.0.1:1/$name-s.jpg', 'normal': 'http://127.0.0.1:1/$name-n.jpg'},
    };

Future<CardRepository> _repo() async {
  final dir = Directory.systemTemp.createTempSync('netgame');
  final path = '${dir.path}/cards.sqlite';
  final imp = CardImporter(path)..open();
  await imp.importLines(Stream.fromIterable([
    _card('Boss', 'Legendary Creature — Goblin'),
    for (var i = 0; i < 20; i++) _card('Card$i', 'Creature — Goblin'),
    _card('Mountain', 'Basic Land — Mountain'),
  ].map(jsonEncode)));
  imp.finish({'bulk_updated_at': 'test'});
  return CardRepository.open(path)!;
}

Deck _deck(String name) {
  var d = Deck(name: name, format: 'commander').add('o-Boss', board: Board.command);
  for (var i = 0; i < 20; i++) {
    d = d.add('o-Card$i');
  }
  return d.add('o-Mountain', qty: 79);
}

Future<void> _until(bool Function() ok, [String what = '']) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('Timeout: $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

String _public(NetworkGame g) => jsonEncode(g.game!.state.toJson());

void main() {
  late CardRepository repo;
  setUpAll(() async {
    _setUpSqlite();
    repo = await _repo();
  });

  test('lobby, início, jogo sincronizado e zonas ocultas privadas', () async {
    final server = HostServer(roomName: 'Mesa', hostName: 'Ana', preferredPort: 0);
    await server.start();
    final host = NetworkGame(
      session: RoomSession.host(server: server, roomName: 'Mesa', hostAddresses: const ['127.0.0.1']),
      repo: repo,
    );
    final client = RoomClient(hosts: ['127.0.0.1'], port: server.port, playerName: 'Rui');
    await client.connect();
    final guest = NetworkGame(session: RoomSession.client(client: client, roomName: 'Mesa'), repo: repo);

    host.configure(format: 'commander', life: 40);
    await _until(() => guest.players.length == 2 && guest.startingLife == 40, 'lobby');

    host.selectDeck(_deck('A'), legal: true, commanderNames: ['Boss']);
    guest.selectDeck(_deck('B'), legal: true, commanderNames: ['Boss']);
    await _until(() => host.players[1]?.deckName == 'B', 'deck do convidado');
    host.setReady(true);
    guest.setReady(true);
    await _until(() => host.allReady, 'todos prontos');

    host.start(randomFirst: false);
    await _until(
        () =>
            guest.game != null &&
            host.game != null &&
            host.game!.state.players[0]?.handCount == 7 &&
            host.game!.state.players[1]?.handCount == 7 &&
            guest.game!.state.players[0]?.handCount == 7,
        'mãos iniciais');
    await _until(() => _public(host) == _public(guest), 'sincronia inicial');

    // Cada um só conhece a sua mão e o seu grimório.
    expect(host.game!.zones(0).hand.length, 7);
    expect(guest.game!.zones(1).hand.length, 7);
    expect(host.game!.table.private.containsKey(1), isFalse);
    expect(guest.game!.table.private.containsKey(0), isFalse);
    expect(host.game!.state.players[1]!.libraryCount, 92);

    // O convidado joga uma carta; ambos a veem.
    final pc = guest.game!.zones(1).hand.first;
    guest.game!.playFromHand(pc);
    await _until(
        () => host.game!.state.cards.values.any((c) => c.owner == 1 && c.zone == Zone.battlefield),
        'carta jogada');
    await _until(() => _public(host) == _public(guest), 'sincronia depois de jogar');
    expect(guest.game!.zones(1).hand.length, 6);

    // Desfaz a própria última ação.
    expect(guest.game!.canUndo, isTrue);
    guest.game!.undo();
    await _until(() => host.game!.state.players[1]!.handCount == 7, 'undo');
    await _until(() => _public(host) == _public(guest), 'sincronia depois do undo');
    expect(guest.game!.zones(1).hand.length, 7);

    // A ligação do convidado cai; o anfitrião continua a jogar.
    await server.dropPeerForTest(1);
    host.game!.life(1, -3);
    host.game!.passTurn();
    await _until(() => client.reconnects == 1, 'religação');
    await _until(() => _public(host) == _public(guest), 'sincronia depois de religar');
    expect(guest.game!.state.players[1]!.life, 37);
    expect(guest.game!.zones(1).hand.length, 7, reason: 'a mão sobrevive à queda');

    guest.dispose();
    host.dispose();
    await client.close();
    await server.close();
  });

  test('imagens que faltam vêm do outro dispositivo pela sala', () async {
    final server = HostServer(roomName: 'Mesa', hostName: 'Ana', preferredPort: 0);
    await server.start();
    final hostImages = ImageService(AppPaths.forTest(Directory.systemTemp.createTempSync('imgA').path));
    final guestImages = ImageService(AppPaths.forTest(Directory.systemTemp.createTempSync('imgB').path));
    // O anfitrião já tem as imagens do seu deck.
    for (final n in ['Boss', 'Mountain', for (var i = 0; i < 20; i++) 'Card$i']) {
      await hostImages.writeBytes('small', 'p-$n', [1, 2, 3, n.length]);
    }
    final host = NetworkGame(
      session: RoomSession.host(server: server, roomName: 'Mesa', hostAddresses: const ['127.0.0.1']),
      repo: repo,
      images: hostImages,
    );
    final client = RoomClient(hosts: ['127.0.0.1'], port: server.port, playerName: 'Rui');
    await client.connect();
    final guest = NetworkGame(
      session: RoomSession.client(client: client, roomName: 'Mesa'),
      repo: repo,
      images: guestImages,
    );

    host.selectDeck(_deck('A'), legal: true, commanderNames: ['Boss']);
    await _until(() => guest.missingFrom(0).length == 22, 'imagens anunciadas');
    expect(host.missingFrom(1), isEmpty, reason: 'o convidado ainda não escolheu deck');

    await guest.downloadMissing(0);
    await _until(() => guest.missingFrom(0).isEmpty, 'imagens recebidas');
    expect(await guestImages.readBytes('small', 'p-Boss'), [1, 2, 3, 4]);
    expect(server.log.where((e) => e.type.startsWith('d:')), isEmpty, reason: 'fora do registo');

    guest.dispose();
    host.dispose();
    await client.close();
    await server.close();
  });
}
