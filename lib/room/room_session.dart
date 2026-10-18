import '../net/discovery.dart';
import '../net/host_server.dart';
import '../net/hotspot.dart';
import '../net/join_code.dart';
import '../net/room_client.dart';
import '../net/room_link.dart';

/// Tudo o que uma sala aberta neste dispositivo tem de fechar ao sair.
class RoomSession {
  RoomSession.host({
    required HostServer server,
    required this.roomName,
    required this.hostAddresses,
    this.advertiser,
    this.hotspot,
    this.hasPin = false,
  }) : link = server;

  RoomSession.client({
    required RoomClient client,
    required this.roomName,
  })  : link = client,
        hostAddresses = const [],
        advertiser = null,
        hotspot = null,
        hasPin = false;

  final RoomLink link;
  final String roomName;
  final List<String> hostAddresses;
  final RoomAdvertiser? advertiser;
  final HotspotInfo? hotspot;
  final bool hasPin;

  bool get isHost => link is HostServer;

  int get port => switch (link) {
        HostServer s => s.port,
        RoomClient c => c.port,
        _ => 0,
      };

  JoinCode get joinCode => JoinCode(
        hosts: hostAddresses,
        port: port,
        roomName: roomName,
        hasPin: hasPin,
      );

  Future<void> close() async {
    final l = link;
    if (l is RoomClient) {
      await l.leave();
    } else {
      await l.close();
    }
    await advertiser?.stop();
    if (hotspot != null) await Hotspot.stop();
  }
}
