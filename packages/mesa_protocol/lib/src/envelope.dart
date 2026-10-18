/// Versão do protocolo. Muda sempre que o formato das mensagens deixa de ser
/// compatível com versões anteriores.
const int protocolVersion = 1;

/// Mensagem trocada entre anfitrião e clientes.
///
/// `seq` é atribuído pelo anfitrião e define a ordem global dos eventos.
/// Intenções enviadas por clientes levam `seq == 0` até o anfitrião as aceitar.
class Envelope {
  const Envelope({
    this.v = protocolVersion,
    this.seq = 0,
    required this.type,
    required this.actor,
    required this.ts,
    this.payload = const {},
  });

  /// Cria uma intenção (ainda sem `seq`) com o relógio atual.
  factory Envelope.intent(
    String type, {
    required int actor,
    Map<String, dynamic> payload = const {},
  }) =>
      Envelope(
        type: type,
        actor: actor,
        ts: DateTime.now().millisecondsSinceEpoch,
        payload: payload,
      );

  factory Envelope.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String || type.isEmpty) {
      throw const FormatException('Envelope sem "type"');
    }
    return Envelope(
      v: (json['v'] as num?)?.toInt() ?? 0,
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      type: type,
      actor: (json['actor'] as num?)?.toInt() ?? -1,
      ts: (json['ts'] as num?)?.toInt() ?? 0,
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  final int v;
  final int seq;
  final String type;

  /// Lugar (seat) do jogador que originou o evento; -1 para o sistema.
  final int actor;

  /// Milissegundos desde a epoch, no relógio de quem criou a mensagem.
  final int ts;
  final Map<String, dynamic> payload;

  bool get isSequenced => seq > 0;

  Envelope withSeq(int seq) => Envelope(
        v: v,
        seq: seq,
        type: type,
        actor: actor,
        ts: ts,
        payload: payload,
      );

  Map<String, dynamic> toJson() => {
        'v': v,
        'seq': seq,
        'type': type,
        'actor': actor,
        'ts': ts,
        'payload': payload,
      };

  @override
  String toString() => 'Envelope(#$seq $type actor=$actor $payload)';
}
