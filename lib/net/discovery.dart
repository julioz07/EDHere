import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

/// Tipo de serviço mDNS das salas (registado também no Info.plist do iOS).
const String roomServiceType = '_mesa._tcp';

const String appVersion = '0.9.1';

/// Data do bulk do Scryfall da base local, anunciada nas salas para se
/// ver quem tem uma base diferente. Atualizada pelo CardDataService.
String cardDbVersion = 'none';

/// Sala anunciada na rede local.
class RoomAd {
  const RoomAd({
    required this.name,
    required this.port,
    this.host,
    this.format = 'commander',
    this.freeSeats = 0,
    this.hasPin = false,
    this.appVersion = '',
    this.dbVersion = '',
  });

  final String name;
  final String? host;
  final int port;
  final String format;
  final int freeSeats;
  final bool hasPin;
  final String appVersion;
  final String dbVersion;

  Map<String, String> toAttributes() => {
        'fmt': format,
        'free': '$freeSeats',
        'pin': hasPin ? '1' : '0',
        'app': appVersion,
        'db': dbVersion,
      };

  static RoomAd fromService(BonsoirService s, {String? host}) {
    final a = s.attributes;
    return RoomAd(
      name: s.name,
      host: host,
      port: s.port,
      format: a['fmt'] ?? 'commander',
      freeSeats: int.tryParse(a['free'] ?? '') ?? 0,
      hasPin: a['pin'] == '1',
      appVersion: a['app'] ?? '',
      dbVersion: a['db'] ?? '',
    );
  }
}

/// Anuncia a sala do anfitrião por mDNS.
class RoomAdvertiser {
  BonsoirBroadcast? _broadcast;

  Future<void> start(RoomAd ad) async {
    await stop();
    final service = BonsoirService(
      name: ad.name,
      type: roomServiceType,
      port: ad.port,
      attributes: ad.toAttributes(),
    );
    final b = BonsoirBroadcast(service: service);
    _broadcast = b;
    await b.ready;
    await b.start();
  }

  Future<void> stop() async {
    final b = _broadcast;
    _broadcast = null;
    if (b != null && !b.isStopped) await b.stop();
  }
}

/// Procura salas na rede local e mantém a lista das que estão resolvidas
/// (com endereço).
class RoomBrowser {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  final Map<String, RoomAd> _rooms = {};
  final _controller = StreamController<List<RoomAd>>.broadcast();

  Stream<List<RoomAd>> get rooms => _controller.stream;
  List<RoomAd> get current => _rooms.values.toList();

  Future<void> start() async {
    await stop();
    final d = BonsoirDiscovery(type: roomServiceType);
    _discovery = d;
    await d.ready;
    _sub = d.eventStream!.listen((event) {
      final service = event.service;
      if (service == null) return;
      switch (event.type) {
        case BonsoirDiscoveryEventType.discoveryServiceFound:
          service.resolve(d.serviceResolver);
        case BonsoirDiscoveryEventType.discoveryServiceResolved:
          final host = service is ResolvedBonsoirService ? service.host : null;
          _rooms[service.name] = RoomAd.fromService(service, host: host);
          _emit();
        case BonsoirDiscoveryEventType.discoveryServiceLost:
          _rooms.remove(service.name);
          _emit();
        default:
          break;
      }
    });
    await d.start();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(current);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    final d = _discovery;
    _discovery = null;
    if (d != null && !d.isStopped) await d.stop();
    _rooms.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
