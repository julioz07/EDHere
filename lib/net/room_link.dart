import 'dart:async';

import 'package:mesa_protocol/mesa_protocol.dart';

/// Porta por defeito das salas. Se estiver ocupada, o anfitrião usa outra
/// e anuncia-a por mDNS e no QR code.
const int defaultRoomPort = 47820;

/// Heartbeat a cada 2 s; sem sinal durante 10 s o jogador fica desligado.
const Duration heartbeatInterval = Duration(seconds: 2);
const Duration peerTimeout = Duration(seconds: 10);

enum LinkStatus { connecting, connected, reconnecting, rejected, closed }

/// Ligação de um dispositivo a uma sala, seja como anfitrião ou cliente.
///
/// A UI só vê eventos já ordenados (com `seq`) e envia intenções.
abstract class RoomLink {
  /// Eventos ordenados pelo anfitrião, pela ordem de `seq`, sem falhas.
  /// Só traz eventos novos: quem começa a ouvir mais tarde lê [history].
  Stream<Envelope> get events;

  /// Todos os eventos ordenados já aplicados neste dispositivo.
  List<Envelope> get history;

  /// Estado da ligação; muda ao longo da vida da sala.
  Stream<LinkStatus> get statusChanges;
  LinkStatus get status;

  /// Lugar deste dispositivo na sala (0 é o anfitrião).
  int get mySeat;

  /// Último tempo de ida e volta medido até ao anfitrião, em ms.
  int? get rttMs;

  /// Motivo da última recusa ou erro, para mostrar ao utilizador.
  String? get lastError;

  /// Envia uma intenção. O anfitrião atribui-lhe `seq` e difunde-a.
  void submit(String type, [Map<String, dynamic> payload = const {}]);

  /// Mensagens diretas recebidas (fora da ordem global e do registo).
  /// O `actor` é o lugar de quem as enviou.
  Stream<Envelope> get direct;

  /// Envia uma mensagem direta a um lugar, através do anfitrião.
  void sendDirect(int to, String type, Map<String, dynamic> payload);

  Future<void> close();
}
