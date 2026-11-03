import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:card_db/card_db.dart';
import 'package:edhoff/data/app_paths.dart';
import 'package:edhoff/data/image_service.dart';
import 'package:edhoff/game/draft.dart';
import 'package:edhoff/game/network_game.dart';
import 'package:edhoff/net/host_server.dart';
import 'package:edhoff/net/room_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edhoff/net/room_link.dart';
import 'package:edhoff/game/resume_store.dart';
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
    await _until(() => host.game!.state.cards.values.any((c) => c.owner == 1 && c.zone == Zone.battlefield),
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

  test('o anfitrião que fecha a meio volta ao jogo com a mão e a sala de antes', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ResumeStore(await SharedPreferences.getInstance());
    final journal = '${Directory.systemTemp.createTempSync('hostj').path}/host.jsonl';
    final server = HostServer(roomName: 'Mesa', hostName: 'Ana', preferredPort: 0, journalPath: journal);
    await server.start();
    final deckA = _deck('A');
    final host = NetworkGame(
      session: RoomSession.host(server: server, roomName: 'Mesa', hostAddresses: const ['127.0.0.1']),
      repo: repo,
      resumeStore: store,
    );
    final client = RoomClient(hosts: ['127.0.0.1'], port: server.port, playerName: 'Rui');
    await client.connect();
    final guest = NetworkGame(session: RoomSession.client(client: client, roomName: 'Mesa'), repo: repo);
    host.configure(format: 'commander', life: 40);
    await _until(() => guest.players.length == 2, 'lobby');
    host.selectDeck(deckA, legal: true, commanderNames: ['Boss']);
    guest.selectDeck(_deck('B'), legal: true, commanderNames: ['Boss']);
    await _until(() => host.players[1]?.deckName == 'B', 'decks');
    host.setReady(true);
    guest.setReady(true);
    await _until(() => host.allReady, 'prontos');
    host.start(randomFirst: false);
    await _until(() => host.game?.state.players[0]?.handCount == 7 && guest.game?.state.players[1]?.handCount == 7,
        'mãos');
    host.game!.playFromHand(host.game!.zones(0).hand.first);
    await _until(() => guest.game!.state.cards.values.any((c) => c.owner == 0 && c.zone == Zone.battlefield),
        'carta do anfitrião');
    final hand = host.game!.zones(0).hand.map((c) => c.oracleId).toList();
    expect(store.current?.isHost, isTrue);

    // A app do anfitrião morre; volta pelo diário e pelo que guardou.
    final info = store.current!;
    host.dispose();
    await server.crashForTest();
    final again = HostServer.restore(info.journal!)!;
    await again.start();
    final back = NetworkGame(
      session: RoomSession.host(server: again, roomName: 'Mesa', hostAddresses: const ['127.0.0.1']),
      repo: repo,
      resume: info,
      resumeStore: store,
      resumeDeck: deckA,
    );
    expect(back.game, isNotNull);
    expect(back.game!.zones(0).hand.map((c) => c.oracleId).toList(), hand, reason: 'a mão volta igual');

    // O convidado volta a ligar-se sozinho e o jogo continua.
    await _until(() => client.reconnects >= 1 && client.status == LinkStatus.connected, 'religação');
    back.game!.life(1, -2);
    await _until(() => guest.game!.state.players[1]!.life == 38, 'evento depois de reabrir');
    await _until(() => _public(back) == _public(guest), 'sincronia');

    guest.dispose();
    back.dispose();
    await client.close();
    await again.close();
  });

  test('quem sai da mesa a meio fica com o lugar e volta com a mesma mão', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ResumeStore(await SharedPreferences.getInstance());
    final server = HostServer(roomName: 'Mesa', hostName: 'Ana', preferredPort: 0);
    await server.start();
    final host = NetworkGame(
      session: RoomSession.host(server: server, roomName: 'Mesa', hostAddresses: const ['127.0.0.1']),
      repo: repo,
    );
    final client = RoomClient(hosts: ['127.0.0.1'], port: server.port, playerName: 'Rui');
    await client.connect();
    final session = RoomSession.client(client: client, roomName: 'Mesa');
    final deckB = _deck('B');
    final guest = NetworkGame(session: session, repo: repo, resumeStore: store);
    host.configure(format: 'commander', life: 40);
    await _until(() => guest.players.length == 2, 'lobby');
    host.selectDeck(_deck('A'), legal: true, commanderNames: ['Boss']);
    guest.selectDeck(deckB, legal: true, commanderNames: ['Boss']);
    await _until(() => host.players[1]?.deckName == 'B', 'decks');
    host.setReady(true);
    guest.setReady(true);
    await _until(() => host.allReady, 'prontos');
    host.start(randomFirst: false);
    await _until(() => guest.game?.zones(1).hand.length == 7, 'mão do convidado');
    final hand = guest.game!.zones(1).hand.map((c) => c.oracleId).toList();

    // Sai da mesa a meio: só desliga, o lugar e o token continuam a valer.
    final info = store.current!;
    guest.dispose();
    await session.close(keepSeat: true);
    await _until(() => host.players[1]?.connected == false, 'desligado no anfitrião');
    expect(host.players.containsKey(1), isTrue);
    host.game!.life(1, -4);

    // Volta pelo "Voltar ao jogo": mesmo lugar, mesma mão, nada a dobrar.
    final again = RoomClient(hosts: ['127.0.0.1'], port: server.port, playerName: 'Rui', token: info.token);
    await again.connect();
    final back = NetworkGame(
      session: RoomSession.client(client: again, roomName: 'Mesa'),
      repo: repo,
      resume: info,
      resumeStore: store,
      resumeDeck: deckB,
    );
    expect(again.mySeat, 1);
    await _until(() => back.game?.state.players[1]?.life == 36, 'apanha o que perdeu');
    expect(back.game!.zones(1).hand.map((c) => c.oracleId).toList(), hand);
    await _until(() => host.players[1]?.connected == true, 'ligado outra vez');
    expect(host.game!.state.players[1]!.handCount, 7, reason: 'não recebe outra mão');
    expect(host.game!.state.players[1]!.libraryCount, 92);
    await _until(() => _public(back) == _public(host), 'sincronia');

    back.dispose();
    host.dispose();
    await again.close();
    await server.close();
  });

  test('draft em rede: cada um recebe o seu pack com cartas', () async {
    final server = HostServer(roomName: 'Mesa', hostName: 'Ana', preferredPort: 0);
    await server.start();
    final host = NetworkGame(
      session: RoomSession.host(server: server, roomName: 'Mesa', hostAddresses: const ['127.0.0.1']),
      repo: repo,
    );
    final client = RoomClient(hosts: ['127.0.0.1'], port: server.port, playerName: 'Rui');
    await client.connect();
    final guest = NetworkGame(session: RoomSession.client(client: client, roomName: 'Mesa'), repo: repo);
    await _until(() => host.players.length == 2 && guest.players.length == 2, 'lobby');
    var id = 0;
    List<DraftCard> pack() => [
          for (var i = 0; i < 14; i++) DraftCard(++id, BoosterPrint('p-Card$i', 'o-Card$i', 'C', '$i', setCode: 'fra')),
        ];
    host.startDraft(
      const DraftConfig(title: 'FRA', setCode: 'FRA', packs: 1, seats: [(seat: 0, name: 'Ana'), (seat: 1, name: 'Rui')]),
      [
        [pack(), pack()],
      ],
    );
    await _until(() => guest.draftClient?.pack != null && host.draftClient?.pack != null, 'packs');
    expect(guest.draftClient!.pack!.length, 14);
    expect(host.draftClient!.pack!.length, 14);

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

  test('Modern a 4: duas mesas 1 contra 1, à melhor de 3, e depois a ronda seguinte', () async {
    final server = HostServer(roomName: 'Mesa', hostName: 'Ana', preferredPort: 0);
    await server.start();
    final host = NetworkGame(
      session: RoomSession.host(server: server, roomName: 'Mesa', hostAddresses: const ['127.0.0.1']),
      repo: repo,
    );
    final clients = <RoomClient>[];
    final all = [host];
    for (final name in ['Rui', 'Eva', 'Leo']) {
      final c = RoomClient(hosts: ['127.0.0.1'], port: server.port, playerName: name);
      await c.connect();
      clients.add(c);
      all.add(NetworkGame(session: RoomSession.client(client: c, roomName: 'Mesa'), repo: repo));
    }
    host.configure(format: 'modern', life: 20);
    await _until(() => all.every((g) => g.players.length == 4 && g.format == 'modern'), 'lobby');
    expect(host.oneVsOne, isTrue);
    var d = const Deck(name: 'M', format: 'modern');
    for (var i = 0; i < 20; i++) {
      d = d.add('o-Card$i');
    }
    d = d.add('o-Mountain', qty: 40);
    for (final g in all) {
      g.selectDeck(d, legal: true, commanderNames: const []);
    }
    await _until(() => host.players.values.every((p) => p.deckName != null), 'decks');
    for (final g in all) {
      g.setReady(true);
    }
    await _until(() => host.allReady, 'prontos');

    host.startMatches();
    await _until(
        () => all.every((g) => g.game != null && g.game!.state.players[g.mySeat]?.handCount == 7), 'mãos iniciais');
    // Cada mesa tem só os dois do encontro, com vida 20.
    for (final g in all) {
      expect(g.game!.state.players.length, 2);
      expect(g.game!.state.players.values.every((p) => p.life == 20), isTrue);
      final m = g.myMatch!;
      expect(g.game!.state.players.keys.toSet(), {m.a, m.b});
    }
    // O que se faz numa mesa não aparece na outra.
    final m0 = host.myMatch!;
    final other = all.firstWhere((g) => !m0.has(g.mySeat));
    final mate = all.firstWhere((g) => g != host && m0.has(g.mySeat));
    host.game!.life(m0.other(0), -5);
    await _until(() => mate.game!.state.players[m0.other(0)]!.life == 15, 'vida na mesa do anfitrião');
    expect(other.game!.state.players.values.every((p) => p.life == 20), isTrue);

    // Jogo 1: o anfitrião ganha; o seguinte começa quem perdeu.
    host.game!.gameOver(0);
    await _until(() => all.every((g) => g.tournament!.matchOf(0, 0)!.games.length == 1), 'resultado do jogo 1');
    final firstTable = host.myTable;
    // Sideboard: uma Mountain sai do deck só para este encontro.
    host.sideboard(host.myDeck!.setQty('o-Mountain', Board.main, 39).add('o-Mountain', board: Board.side));
    mate.requestNextGame();
    host.requestNextGame(); // os dois pedem: só começa um jogo
    await _until(() => host.myTable != firstTable && host.game?.state.players[0]?.handCount == 7, 'jogo 2');
    expect(host.myTableInfo!.game, 2);
    expect(host.game!.state.players[0]!.libraryCount, 59 - 7, reason: 'o jogo 2 usa o deck com o sideboard');
    expect(host.myTableInfo!.first, m0.other(0), reason: 'quem perdeu começa');
    expect(host.tables.values.where((t) => t.round == 0 && t.a == m0.a).length, 2);
    host.game!.gameOver(0);
    await _until(() => all.every((g) => g.tournament!.matchOf(0, 0)!.done), 'encontro 2-0');
    expect(host.tournament!.roundDone(0), isFalse, reason: 'a outra mesa ainda joga');

    // A outra mesa acaba 2-1 (com o pedido do jogo seguinte pelo meio).
    final m1 = other.myMatch!;
    for (final (i, w) in [m1.a, m1.b, m1.a].indexed) {
      final before = other.myTable;
      other.game!.gameOver(w);
      await _until(() => host.tournament!.matchOf(0, m1.a)!.games.length == i + 1, 'jogo da outra mesa');
      if (!host.tournament!.matchOf(0, m1.a)!.done) {
        other.requestNextGame();
        await _until(() => other.myTable != before && other.game != null, 'jogo seguinte da outra mesa');
      }
    }
    expect(host.tournament!.matchOf(0, m1.a)!.winner, m1.a);
    await _until(() => host.tournament!.roundDone(0), 'ronda 1 acabada');

    host.startNextRound();
    await _until(() => all.every((g) => g.tournament!.round == 1 && g.game != null && g.myTableInfo?.round == 1),
        'ronda 2');
    for (final g in all) {
      final m = g.myMatch!;
      expect(g.game!.state.players.keys.toSet(), {m.a, m.b});
    }
    expect(host.tournament!.standings().first.points, 3);
    expect(host.myDeck!.count(Board.main), 60, reason: 'no encontro seguinte o deck volta ao original');

    for (final g in all.reversed) {
      g.dispose();
    }
    for (final c in clients) {
      await c.close();
    }
    await server.close();
  });
}
