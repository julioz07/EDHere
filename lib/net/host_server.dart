import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mesa_protocol/mesa_protocol.dart';

import 'room_link.dart';
import '../l10n/l10n.dart';

/// Anfitrião da sala: aceita ligações TCP, atribui `seq` a cada intenção,
/// guarda o registo e difunde os eventos a todos.
///
/// O próprio anfitrião é o jogador do lugar 0 e usa a mesma via ([submit])
/// que os clientes, por isso vê os eventos pela mesma ordem que eles.
class HostServer implements RoomLink {
  HostServer({
    required this.roomName,
    required this.hostName,
    this.pin,
    this.maxSeats = 6,
    this.preferredPort = defaultRoomPort,
    this.journalPath,
  });

  /// Volta a abrir a sala que este dispositivo tinha antes de a app fechar,
  /// a partir do diário ([journalPath]). Os clientes voltam sozinhos: tentam
  /// a mesma porta com o mesmo token e recebem o que lhes falta.
  static HostServer? restore(String journalPath) {
    final file = File(journalPath);
    if (!file.existsSync()) return null;
    Map? header;
    final log = <Envelope>[];
    final tokens = <String, ({int seat, String name})>{};
    try {
      for (final line in file.readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        final j = jsonDecode(line) as Map<String, dynamic>;
        if (j['h'] case final Map h) {
          // Ao reabrir escreve-se outro cabeçalho: vale o último (a porta).
          header = h;
        } else if (j['e'] case final Map e) {
          log.add(Envelope.fromJson(e.cast<String, dynamic>()));
        } else if (j['t'] case final String token) {
          tokens[token] = (seat: (j['s'] as num).toInt(), name: j['n'] as String? ?? '');
        } else if (j['x'] case final String token) {
          tokens.remove(token);
        }
      }
    } catch (_) {
      // Uma linha cortada a meio (a app morreu a escrever) não estraga o resto.
    }
    final h = header;
    if (h == null || log.isEmpty) return null;
    final server = HostServer(
      roomName: h['room'] as String,
      hostName: h['host'] as String,
      pin: h['pin'] as String?,
      maxSeats: (h['seats'] as num).toInt(),
      preferredPort: (h['port'] as num).toInt(),
      journalPath: journalPath,
    ).._restored = true;
    server._log.addAll(log);
    server._seq = log.last.seq;
    for (final MapEntry(key: token, value: t) in tokens.entries) {
      server._tokens[token] = t.seat;
      server._peers[t.seat] = _Peer(null)
        ..seat = t.seat
        ..token = token
        ..name = t.name;
    }
    return server;
  }

  final String roomName;
  final String hostName;
  final String? pin;
  final int maxSeats;
  final int preferredPort;

  /// Ficheiro onde o anfitrião vai escrevendo a sala (eventos e tokens) para
  /// a poder reabrir se a app fechar a meio. Apaga-se ao fechar a sala.
  final String? journalPath;
  RandomAccessFile? _journal;
  bool _restored = false;

  /// Esta sala foi reaberta a partir do diário.
  bool get restored => _restored;

  ServerSocket? _server;
  Timer? _watchdog;
  int _seq = 0;
  final List<Envelope> _log = [];
  final Map<int, _Peer> _peers = {};
  final Map<String, int> _tokens = {};
  final Set<_Peer> _pending = {};
  final _events = StreamController<Envelope>.broadcast();
  final _direct = StreamController<Envelope>.broadcast();
  final _status = StreamController<LinkStatus>.broadcast();
  LinkStatus _currentStatus = LinkStatus.connecting;
  final Random _random = Random.secure();

  int get port => _server?.port ?? 0;
  List<Envelope> get log => List.unmodifiable(_log);
  @override
  List<Envelope> get history => log;
  int get connectedPeers => _peers.values.where((p) => p.socket != null).length;

  @override
  Stream<Envelope> get events => _events.stream;
  @override
  Stream<Envelope> get direct => _direct.stream;

  @override
  void sendDirect(int to, String type, Map<String, dynamic> payload) =>
      _route(from: 0, to: to, type: type, payload: payload);

  /// Entrega uma mensagem direta: ao anfitrião (lugar 0) ou a um cliente.
  void _route(
      {required int from, required int to, required String type, required Map<String, dynamic> payload}) {
    final env = Envelope(
      type: type,
      actor: from,
      ts: DateTime.now().millisecondsSinceEpoch,
      payload: payload,
    );
    if (to == 0) {
      if (!_direct.isClosed) _direct.add(env);
      return;
    }
    final peer = _peers[to];
    if (peer != null) _send(peer, env);
  }

  @override
  Stream<LinkStatus> get statusChanges => _status.stream;
  @override
  LinkStatus get status => _currentStatus;
  @override
  int get mySeat => 0;
  @override
  int? get rttMs => 0;
  @override
  String? lastError;

  Future<void> start() async {
    // Ao reabrir, os clientes procuram a sala na porta antiga: tenta-a umas
    // vezes antes de desistir dela.
    for (var attempt = 0;; attempt++) {
      try {
        _server = await ServerSocket.bind(InternetAddress.anyIPv4, preferredPort);
        break;
      } on SocketException {
        if (!_restored || attempt >= 4) {
          _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    _server!.listen(_onConnection, onError: (Object e) => lastError = '$e');
    _watchdog = Timer.periodic(heartbeatInterval, (_) => _checkTimeouts());
    _openJournal();
    _setStatus(LinkStatus.connected);
    if (_restored) {
      // Ninguém está ligado até voltar a dizer olá.
      for (final seat in [..._peers.keys]) {
        _sequence(Envelope.intent(MsgType.playerStatus, actor: -1, payload: {'seat': seat, 'connected': false}));
      }
    } else {
      _sequence(Envelope.intent(MsgType.join, actor: 0, payload: {'seat': 0, 'name': hostName, 'host': true}));
    }
  }

  void _openJournal() {
    final path = journalPath;
    if (path == null) return;
    try {
      _journal = File(path).openSync(mode: _restored ? FileMode.append : FileMode.write);
      // A porta pode ter mudado (a antiga estava ocupada).
      _write({
        'h': {'room': roomName, 'host': hostName, 'pin': pin, 'seats': maxSeats, 'port': port}
      });
    } catch (_) {
      _journal = null;
    }
  }

  void _write(Map<String, dynamic> j) {
    try {
      _journal?.writeStringSync('${jsonEncode(j)}\n');
    } catch (_) {
      _journal = null;
    }
  }

  /// Fecha e apaga o diário: a sala acabou de propósito.
  void _dropJournal() {
    try {
      _journal?.closeSync();
    } catch (_) {}
    _journal = null;
    final path = journalPath;
    if (path != null) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
  }

  @override
  void submit(String type, [Map<String, dynamic> payload = const {}]) {
    if (_currentStatus == LinkStatus.closed) return;
    _sequence(Envelope.intent(type, actor: 0, payload: payload));
  }

  @override
  Future<void> close() async {
    if (_currentStatus == LinkStatus.closed) return;
    _watchdog?.cancel();
    // Avisa os clientes antes de cortar, para não ficarem a tentar voltar.
    final bye = Envelope(type: MsgType.roomClosed, actor: 0, ts: DateTime.now().millisecondsSinceEpoch);
    final flushing = <Future<void>>[];
    for (final peer in _peers.values) {
      final socket = peer.socket;
      if (socket == null) continue;
      _send(peer, bye);
      flushing.add(socket.flush().catchError((_) {}));
    }
    await Future.wait(flushing).timeout(const Duration(milliseconds: 600), onTimeout: () => const []);
    _dropJournal();
    _setStatus(LinkStatus.closed);
    for (final peer in [..._peers.values, ..._pending]) {
      peer.socket?.destroy();
    }
    await _server?.close();
    await _events.close();
    await _direct.close();
    await _status.close();
  }

  /// Tira um jogador da sala: o lugar fica livre e ele não volta com o token
  /// que tinha (por exemplo, quem saiu sem fechar a app e deixou o lugar preso).
  void kick(int seat) {
    if (seat == 0) return;
    final peer = _peers.remove(seat);
    if (peer == null) return;
    if (peer.token != null) {
      _tokens.remove(peer.token);
      _write({'x': peer.token});
    }
    final socket = peer.socket;
    peer.socket = null;
    if (socket != null) {
      peer.subscription?.cancel();
      try {
        socket.add(encodeFrame(Envelope(
          type: MsgType.reject,
          actor: 0,
          ts: DateTime.now().millisecondsSinceEpoch,
          payload: {'reason': RejectReason.kicked},
        ).toJson()));
      } catch (_) {}
      socket.flush().whenComplete(socket.destroy).ignore();
    }
    _sequence(Envelope.intent(MsgType.leave, actor: -1, payload: {'seat': seat}));
  }

  /// Morre como se a app tivesse sido fechada pelo sistema: sem avisar os
  /// clientes e sem apagar o diário. Só para testes.
  Future<void> crashForTest() async {
    _watchdog?.cancel();
    try {
      _journal?.closeSync();
    } catch (_) {}
    _journal = null;
    _setStatus(LinkStatus.closed);
    for (final peer in [..._peers.values, ..._pending]) {
      await peer.subscription?.cancel();
      peer.socket?.destroy();
    }
    await _server?.close();
  }

  /// Corta a ligação de um jogador como se a rede tivesse caído. Só para testes.
  Future<void> dropPeerForTest(int seat) async {
    final peer = _peers[seat];
    final socket = peer?.socket;
    if (peer == null || socket == null) return;
    await peer.subscription?.cancel();
    _dropSocket(peer, socket);
  }

  void _setStatus(LinkStatus s) {
    _currentStatus = s;
    if (!_status.isClosed) _status.add(s);
  }

  void _onConnection(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    final peer = _Peer(socket);
    _pending.add(peer);
    peer.subscription = socket.cast<List<int>>().transform(const FrameDecoder()).listen(
          (json) => _onMessage(peer, json),
          onError: (_) => _dropSocket(peer, socket),
          onDone: () => _dropSocket(peer, socket),
          cancelOnError: true,
        );
  }

  void _onMessage(_Peer peer, Map<String, dynamic> json) {
    final Envelope env;
    try {
      env = Envelope.fromJson(json);
    } on FormatException {
      return;
    }
    peer.lastSeen = DateTime.now();

    if (peer.seat == null) {
      if (env.type == MsgType.hello) _onHello(peer, env);
      return;
    }
    switch (env.type) {
      case MsgType.heartbeat:
        _send(
            peer,
            Envelope(
              type: MsgType.heartbeatAck,
              actor: 0,
              ts: DateTime.now().millisecondsSinceEpoch,
              payload: {'echo': env.ts},
            ));
      case MsgType.hello:
        break;
      case MsgType.relay:
        _route(
          from: peer.seat!,
          to: (env.payload['to'] as num).toInt(),
          type: env.payload['type'] as String,
          payload: (env.payload['payload'] as Map).cast<String, dynamic>(),
        );
      case MsgType.leave:
        // Saída voluntária: o lugar fica livre e o token deixa de valer.
        final seat = peer.seat!;
        _peers.remove(seat);
        _tokens.remove(peer.token);
        if (peer.token != null) _write({'x': peer.token});
        final socket = peer.socket;
        peer.socket = null;
        peer.subscription?.cancel();
        socket?.destroy();
        _sequence(Envelope.intent(MsgType.leave, actor: seat, payload: {'seat': seat}));
      default:
        // O anfitrião é a autoridade sobre quem é o autor de cada intenção.
        _sequence(Envelope(
          type: env.type,
          actor: peer.seat!,
          ts: env.ts,
          payload: env.payload,
        ));
    }
  }

  void _onHello(_Peer peer, Envelope hello) {
    final p = hello.payload;
    if (hello.v != protocolVersion) {
      return _reject(peer, RejectReason.versionMismatch);
    }
    if (pin != null && pin!.isNotEmpty && p['pin'] != pin) {
      return _reject(peer, RejectReason.badPin);
    }

    final token = p['token'] as String?;
    final lastSeq = (p['lastSeq'] as num?)?.toInt() ?? 0;
    final knownSeat = token == null ? null : _tokens[token];

    if (knownSeat != null) {
      // Reconexão: substitui o socket antigo e envia só o que falta.
      final old = _peers[knownSeat];
      if (old != null && old != peer) {
        old.subscription?.cancel();
        old.socket?.destroy();
      }
      _pending.remove(peer);
      peer
        ..seat = knownSeat
        ..token = token
        ..name = old?.name ?? p['name'] as String? ?? tr('Jogador');
      _peers[knownSeat] = peer;
      _sendWelcome(peer, since: lastSeq);
      _sequence(
          Envelope.intent(MsgType.playerStatus, actor: -1, payload: {'seat': knownSeat, 'connected': true}));
      return;
    }

    final seat = _freeSeat();
    if (seat == null) return _reject(peer, RejectReason.roomFull);
    final newToken = _newToken();
    _pending.remove(peer);
    peer
      ..seat = seat
      ..token = newToken
      ..name = _uniqueName((p['name'] as String?)?.trim().isNotEmpty == true
          ? (p['name'] as String).trim()
          : tr('Jogador {seat}', {'seat': seat}));
    _peers[seat] = peer;
    _tokens[newToken] = seat;
    _write({'t': newToken, 's': seat, 'n': peer.name});
    _sendWelcome(peer, since: 0);
    _sequence(Envelope.intent(MsgType.join, actor: -1, payload: {'seat': seat, 'name': peer.name}));
  }

  void _sendWelcome(_Peer peer, {required int since}) {
    _send(
        peer,
        Envelope(
          type: MsgType.welcome,
          actor: 0,
          ts: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'seat': peer.seat,
            'token': peer.token,
            'room': roomName,
            'events': [
              for (final e in _log)
                if (e.seq > since) e.toJson(),
            ],
          },
        ));
  }

  void _reject(_Peer peer, String reason) {
    _send(
        peer,
        Envelope(
          type: MsgType.reject,
          actor: 0,
          ts: DateTime.now().millisecondsSinceEpoch,
          payload: {'reason': reason},
        ));
    _pending.remove(peer);
    peer.socket?.flush().whenComplete(() => peer.socket?.destroy());
  }

  int? _freeSeat() {
    // Lugares de jogadores que saíram de vez ficam livres; os desligados não.
    for (var s = 1; s < maxSeats; s++) {
      if (!_peers.containsKey(s)) return s;
    }
    return null;
  }

  /// Dois jogadores com o mesmo nome confundem tudo (alvos, vencedor,
  /// registo): o segundo fica com um número.
  String _uniqueName(String name) {
    final taken = {hostName, for (final p in _peers.values) p.name};
    if (!taken.contains(name)) return name;
    for (var n = 2;; n++) {
      if (!taken.contains('$name $n')) return '$name $n';
    }
  }

  String _newToken() =>
      List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  void _sequence(Envelope intent) {
    if (_currentStatus == LinkStatus.closed) return;
    final env = intent.withSeq(++_seq);
    _log.add(env);
    _write({'e': env.toJson()});
    final frame = encodeFrame(env.toJson());
    for (final peer in _peers.values) {
      final socket = peer.socket;
      if (socket == null) continue;
      try {
        socket.add(frame);
      } catch (_) {
        // O socket foi fechado entretanto; o onDone trata do resto.
      }
    }
    _events.add(env);
  }

  void _send(_Peer peer, Envelope env) {
    try {
      peer.socket?.add(encodeFrame(env.toJson()));
    } catch (_) {}
  }

  void _dropSocket(_Peer peer, Socket socket) {
    _pending.remove(peer);
    if (peer.socket != socket) return;
    peer.socket = null;
    socket.destroy();
    final seat = peer.seat;
    if (seat != null && _peers[seat] == peer) {
      _sequence(
          Envelope.intent(MsgType.playerStatus, actor: -1, payload: {'seat': seat, 'connected': false}));
    }
  }

  void _checkTimeouts() {
    final now = DateTime.now();
    for (final peer in [..._peers.values, ..._pending]) {
      final socket = peer.socket;
      if (socket != null && now.difference(peer.lastSeen) > peerTimeout) {
        peer.subscription?.cancel();
        _dropSocket(peer, socket);
      }
    }
  }
}

class _Peer {
  _Peer(this.socket);

  Socket? socket;
  StreamSubscription<Map<String, dynamic>>? subscription;
  DateTime lastSeen = DateTime.now();
  int? seat;
  String? token;
  String name = '';
}
