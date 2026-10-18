import 'package:edhoff/net/host_server.dart';
import 'package:edhoff/net/room_client.dart';
import 'package:edhoff/net/room_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesa_protocol/mesa_protocol.dart';

/// Recolhe os eventos ordenados que um [RoomLink] vai recebendo.
class Recorder {
  Recorder(RoomLink link) {
    seen.addAll(link.history);
    link.events.listen(seen.add);
  }
  final List<Envelope> seen = [];

  Future<void> waitForSeq(int seq) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (seen.isEmpty || seen.last.seq < seq) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timeout à espera de seq $seq (último: ${seen.lastOrNull?.seq})');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}

void main() {
  late HostServer host;

  Future<RoomClient> join(String name, {String? pin}) async {
    final c = RoomClient(
      hosts: ['127.0.0.1'],
      port: host.port,
      playerName: name,
      pin: pin,
    );
    await c.connect();
    return c;
  }

  tearDown(() => host.close());

  test('3 clientes recebem uma rajada pela mesma ordem do anfitrião', () async {
    host = HostServer(roomName: 'Teste', hostName: 'Anfitrião', preferredPort: 0);
    await host.start();
    final hostRec = Recorder(host);

    final clients = [for (final n in ['Ana', 'Bruno', 'Carla']) await join(n)];
    final recs = [for (final c in clients) Recorder(c)];
    expect(clients.map((c) => c.mySeat), [1, 2, 3]);

    // Cada um envia 50 eventos em simultâneo.
    for (var i = 0; i < 50; i++) {
      host.submit(MsgType.burst, {'i': i});
      for (final c in clients) {
        c.submit(MsgType.burst, {'i': i});
      }
    }
    final lastSeq = host.log.length + 150; // 50 já sequenciados + 150 a caminho
    await hostRec.waitForSeq(lastSeq);
    for (final r in recs) {
      await r.waitForSeq(lastSeq);
    }

    final hostOrder = host.log.map((e) => '${e.seq}:${e.actor}:${e.type}').toList();
    for (final c in clients) {
      expect(c.seqGaps, 0);
    }
    for (final r in recs) {
      // Clientes que entraram mais tarde recebem o registo anterior no welcome.
      final order = r.seen.map((e) => '${e.seq}:${e.actor}:${e.type}').toList();
      expect(order, hostOrder.sublist(hostOrder.length - order.length));
      expect(r.seen.first.seq, 1);
    }

    // O anfitrião decide o autor de cada evento, não o cliente.
    final bursts = host.log.where((e) => e.type == MsgType.burst);
    expect(bursts.where((e) => e.actor == 2).length, 50);

    for (final c in clients) {
      await c.close();
    }
  });

  test('PIN errado é recusado e PIN certo entra', () async {
    host = HostServer(roomName: 'P', hostName: 'H', pin: '1234', preferredPort: 0);
    await host.start();
    await expectLater(join('X', pin: '0000'), throwsA(isA<RoomJoinException>()));
    final ok = await join('Y', pin: '1234');
    expect(ok.mySeat, 1);
    await ok.close();
  });

  test('sala cheia recusa o jogador a mais', () async {
    host = HostServer(roomName: 'C', hostName: 'H', maxSeats: 2, preferredPort: 0);
    await host.start();
    final a = await join('A');
    await expectLater(join('B'), throwsA(isA<RoomJoinException>()));
    await a.close();
  });

  test('cliente que cai recupera o lugar e os eventos que perdeu', () async {
    host = HostServer(roomName: 'R', hostName: 'H', preferredPort: 0);
    await host.start();
    final c = await join('Ana');
    final rec = Recorder(c);
    final seat = c.mySeat;

    // Simula a queda da ligação do lado do anfitrião.
    await host.dropPeerForTest(seat);
    // Enquanto está fora, o anfitrião continua a jogar.
    for (var i = 0; i < 5; i++) {
      host.submit(MsgType.ping, {'i': i});
    }

    final target = host.log.last.seq + 1; // + player_status connected
    await rec.waitForSeq(target);
    expect(c.mySeat, seat);
    expect(c.reconnects, 1);
    expect(c.seqGaps, 0);
    expect(rec.seen.where((e) => e.type == MsgType.ping).length, 5);
    final status = rec.seen.where((e) => e.type == MsgType.playerStatus).toList();
    expect(status.last.payload, {'seat': seat, 'connected': true});
    await c.close();
  });

  test('mensagens diretas chegam só ao destino e não entram no registo', () async {
    host = HostServer(roomName: 'D', hostName: 'H', preferredPort: 0);
    await host.start();
    final a = await join('A');
    final b = await join('B');
    final gotB = <Envelope>[];
    final gotHost = <Envelope>[];
    final gotA = <Envelope>[];
    b.direct.listen(gotB.add);
    a.direct.listen(gotA.add);
    host.direct.listen(gotHost.add);
    final logBefore = host.log.length;

    a.sendDirect(b.mySeat, 'd:test', {'x': 1});
    a.sendDirect(0, 'd:test', {'x': 2});
    host.sendDirect(a.mySeat, 'd:test', {'x': 3});
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(gotB.single.payload, {'x': 1});
    expect(gotB.single.actor, a.mySeat);
    expect(gotHost.single.payload, {'x': 2});
    expect(gotA.single.payload, {'x': 3});
    expect(host.log.length, logBefore);
    await a.close();
    await b.close();
  });

  test('sair liberta o lugar para outro jogador', () async {
    host = HostServer(roomName: 'L', hostName: 'H', maxSeats: 2, preferredPort: 0);
    await host.start();
    final a = await join('A');
    await a.leave();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final b = await join('B');
    expect(b.mySeat, 1);
    expect(host.log.any((e) => e.type == MsgType.leave), isTrue);
    await b.close();
  });
}
