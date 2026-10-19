import 'dart:async';
import 'dart:io';

import 'package:mesa_protocol/mesa_protocol.dart';

import 'room_link.dart';
import '../l10n/l10n.dart';

/// Cliente de uma sala. Liga-se ao anfitrião, aplica os eventos pela ordem
/// de `seq` e volta a ligar-se sozinho quando a ligação cai, pedindo só os
/// eventos em falta.
class RoomClient implements RoomLink {
  RoomClient({
    required this.hosts,
    required this.port,
    required this.playerName,
    this.pin,
    this.connectTimeout = const Duration(seconds: 4),
    String? token,
  })  : _token = token,
        assert(hosts.isNotEmpty);

  /// Endereços candidatos do anfitrião, tentados por ordem.
  final List<String> hosts;
  final int port;
  final String playerName;
  final String? pin;
  final Duration connectTimeout;

  Socket? _socket;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _heartbeat;
  Timer? _reconnectTimer;
  DateTime _lastHeard = DateTime.now();
  String? _token;
  int _seat = -1;
  int _lastSeq = 0;
  int? _rtt;
  String? _connectedHost;
  Completer<void>? _handshake;
  final _events = StreamController<Envelope>.broadcast();
  final _direct = StreamController<Envelope>.broadcast();
  final _status = StreamController<LinkStatus>.broadcast();
  LinkStatus _currentStatus = LinkStatus.connecting;

  /// Quantas vezes se detetou um salto na ordem (deve ficar a 0).
  int seqGaps = 0;

  /// Quantas vezes a ligação foi recuperada.
  int reconnects = 0;

  String? get connectedHost => _connectedHost;

  /// Identifica este jogador no anfitrião; serve para voltar ao mesmo lugar.
  String? get token => _token;

  /// O anfitrião fechou a sala (não foi a rede que caiu).
  bool hostClosed = false;
  String? get roomName => _roomName;
  String? _roomName;
  int get lastSeq => _lastSeq;

  final List<Envelope> _history = [];

  @override
  List<Envelope> get history => List.unmodifiable(_history);
  @override
  Stream<Envelope> get events => _events.stream;
  @override
  Stream<Envelope> get direct => _direct.stream;

  @override
  void sendDirect(int to, String type, Map<String, dynamic> payload) {
    if (to == _seat) {
      _direct.add(Envelope(type: type, actor: _seat, ts: 0, payload: payload));
      return;
    }
    _sendRaw(
        Envelope.intent(MsgType.relay, actor: _seat, payload: {'to': to, 'type': type, 'payload': payload}));
  }

  @override
  Stream<LinkStatus> get statusChanges => _status.stream;
  @override
  LinkStatus get status => _currentStatus;
  @override
  int get mySeat => _seat;
  @override
  int? get rttMs => _rtt;
  @override
  String? lastError;

  /// Liga pela primeira vez. Lança [RoomJoinException] se não conseguir.
  Future<void> connect() async {
    _setStatus(LinkStatus.connecting);
    final ok = await _tryConnect();
    if (!ok) {
      final err = lastError ?? tr('Não foi possível ligar');
      if (_currentStatus != LinkStatus.rejected) await close();
      throw RoomJoinException(err);
    }
  }

  @override
  void submit(String type, [Map<String, dynamic> payload = const {}]) {
    if (_currentStatus != LinkStatus.connected) return;
    _sendRaw(Envelope.intent(type, actor: _seat, payload: payload));
  }

  /// Sai da sala de vez: o anfitrião liberta o lugar.
  Future<void> leave() async {
    if (_currentStatus == LinkStatus.connected) {
      _sendRaw(Envelope.intent(MsgType.leave, actor: _seat));
      await _socket?.flush().timeout(const Duration(seconds: 1), onTimeout: () {});
    }
    await close();
  }

  @override
  Future<void> close() async {
    if (_currentStatus == LinkStatus.closed) return;
    _setStatus(LinkStatus.closed);
    _heartbeat?.cancel();
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    _socket?.destroy();
    await _events.close();
    await _direct.close();
    await _status.close();
  }

  void _setStatus(LinkStatus s) {
    if (_currentStatus == LinkStatus.closed) return;
    _currentStatus = s;
    if (!_status.isClosed) _status.add(s);
  }

  Future<bool> _tryConnect() async {
    final order = [
      if (_connectedHost != null) _connectedHost!,
      ...hosts.where((h) => h != _connectedHost),
    ];
    for (final host in order) {
      if (_currentStatus == LinkStatus.closed) return false;
      try {
        final socket = await Socket.connect(host, port, timeout: connectTimeout);
        socket.setOption(SocketOption.tcpNoDelay, true);
        if (await _handshakeWith(socket)) {
          _connectedHost = host;
          return true;
        }
        if (_currentStatus == LinkStatus.rejected) return false;
      } on SocketException catch (e) {
        lastError = tr('Sem resposta de {host}:{port} ({message})',
            {'host': host, 'port': port, 'message': e.osError?.message ?? e.message});
      } on TimeoutException {
        lastError = tr('Sem resposta de {host}:{port}', {'host': host, 'port': port});
      }
    }
    return false;
  }

  Future<bool> _handshakeWith(Socket socket) async {
    await _sub?.cancel();
    _socket?.destroy();
    _socket = socket;
    _handshake = Completer<void>();
    _sub = socket.cast<List<int>>().transform(const FrameDecoder()).listen(
          _onMessage,
          onError: (_) => _onLost(socket),
          onDone: () => _onLost(socket),
          cancelOnError: true,
        );
    _sendRaw(Envelope.intent(MsgType.hello, actor: _seat, payload: {
      'name': playerName,
      if (pin != null) 'pin': pin,
      if (_token != null) 'token': _token,
      'lastSeq': _lastSeq,
    }));
    try {
      await _handshake!.future.timeout(connectTimeout);
    } on TimeoutException {
      lastError = tr('O anfitrião não respondeu');
      socket.destroy();
      return false;
    } on RoomJoinException catch (e) {
      lastError = e.message;
      return false;
    }
    _lastHeard = DateTime.now();
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => _beat());
    _setStatus(LinkStatus.connected);
    return true;
  }

  void _onMessage(Map<String, dynamic> json) {
    final Envelope env;
    try {
      env = Envelope.fromJson(json);
    } on FormatException {
      return;
    }
    _lastHeard = DateTime.now();

    switch (env.type) {
      case MsgType.welcome:
        _seat = (env.payload['seat'] as num).toInt();
        _token = env.payload['token'] as String?;
        _roomName = env.payload['room'] as String?;
        for (final raw in (env.payload['events'] as List? ?? const [])) {
          _applySequenced(Envelope.fromJson((raw as Map).cast<String, dynamic>()));
        }
        if (_handshake?.isCompleted == false) _handshake!.complete();
      case MsgType.reject:
        final reason = env.payload['reason'] as String? ?? '?';
        _setStatus(LinkStatus.rejected);
        if (_handshake?.isCompleted == false) {
          _handshake!.completeError(RoomJoinException(_describeReject(reason)));
        }
      case MsgType.roomClosed:
        hostClosed = true;
        lastError = tr('O anfitrião fechou a sala.');
        close();
      case MsgType.heartbeatAck:
        final echo = (env.payload['echo'] as num?)?.toInt();
        if (echo != null) _rtt = DateTime.now().millisecondsSinceEpoch - echo;
      default:
        if (env.isSequenced) {
          _applySequenced(env);
        } else if (!_direct.isClosed) {
          // Sem seq e de tipo desconhecido: mensagem direta de outro jogador.
          _direct.add(env);
        }
    }
  }

  void _applySequenced(Envelope env) {
    if (env.seq <= _lastSeq) return; // duplicado
    if (env.seq != _lastSeq + 1) {
      // Faltam eventos: volta a ligar para os pedir ao anfitrião.
      seqGaps++;
      final socket = _socket;
      if (socket != null) _onLost(socket);
      return;
    }
    _lastSeq = env.seq;
    _history.add(env);
    if (!_events.isClosed) _events.add(env);
  }

  void _beat() {
    if (DateTime.now().difference(_lastHeard) > peerTimeout) {
      final socket = _socket;
      if (socket != null) _onLost(socket);
      return;
    }
    _sendRaw(Envelope.intent(MsgType.heartbeat, actor: _seat));
  }

  void _sendRaw(Envelope env) {
    try {
      _socket?.add(encodeFrame(env.toJson()));
    } catch (_) {}
  }

  void _onLost(Socket socket) {
    if (socket != _socket) return;
    _socket = null;
    _sub?.cancel();
    socket.destroy();
    _heartbeat?.cancel();
    if (_handshake?.isCompleted == false) {
      _handshake!.completeError(RoomJoinException(tr('Ligação recusada')));
      return;
    }
    if (_currentStatus == LinkStatus.closed || _currentStatus == LinkStatus.rejected) {
      return;
    }
    _setStatus(LinkStatus.reconnecting);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(heartbeatInterval, () async {
      if (_currentStatus != LinkStatus.reconnecting) return;
      if (await _tryConnect()) {
        reconnects++;
      } else if (_currentStatus == LinkStatus.reconnecting) {
        _scheduleReconnect();
      }
    });
  }

  static String _describeReject(String reason) => switch (reason) {
        RejectReason.badPin => tr('PIN errado'),
        RejectReason.roomFull => tr('A sala está cheia'),
        RejectReason.versionMismatch => tr('Versão da app diferente da do anfitrião'),
        _ => tr('Recusado pelo anfitrião ({reason})', {'reason': reason}),
      };
}

class RoomJoinException implements Exception {
  const RoomJoinException(this.message);
  final String message;
  @override
  String toString() => message;
}
