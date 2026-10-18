/// Tipos de mensagem da camada de sala (Fase 0).
///
/// Os eventos de jogo (`move`, `tap`, `draw`, ...) chegam com a Fase 2 e
/// usam o mesmo envelope.
abstract final class MsgType {
  // Cliente -> anfitrião (fora da ordem global, sem seq).
  static const hello = 'hello';
  static const heartbeat = 'heartbeat';

  // Anfitrião -> cliente (fora da ordem global, sem seq).
  static const welcome = 'welcome';
  static const reject = 'reject';
  static const heartbeatAck = 'heartbeat_ack';

  /// Mensagem direta para um lugar, encaminhada pelo anfitrião sem `seq`
  /// e sem ficar no registo (por exemplo, imagens de cartas).
  /// Payload: `{to, type, payload}`.
  static const relay = 'relay';

  // Eventos ordenados pelo anfitrião (com seq).
  static const join = 'join';
  static const leave = 'leave';
  static const playerStatus = 'player_status';
  static const ping = 'ping';
  static const rollDie = 'roll_die';
  static const flipCoin = 'flip_coin';
  static const burst = 'burst';
}

/// Motivos de recusa enviados em [MsgType.reject].
abstract final class RejectReason {
  static const badPin = 'bad_pin';
  static const roomFull = 'room_full';
  static const versionMismatch = 'version_mismatch';
}
