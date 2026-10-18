import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Tamanho máximo de uma mensagem. Os eventos de jogo têm poucas centenas de
/// bytes; snapshots de reconexão podem ser maiores.
const int maxFrameBytes = 4 * 1024 * 1024;

/// Codifica um objeto JSON numa frame: 4 bytes big-endian com o tamanho,
/// seguidos do JSON em UTF-8.
Uint8List encodeFrame(Map<String, dynamic> json) {
  final body = utf8.encode(jsonEncode(json));
  if (body.length > maxFrameBytes) {
    throw ArgumentError('Frame demasiado grande: ${body.length} bytes');
  }
  final out = Uint8List(4 + body.length);
  ByteData.sublistView(out).setUint32(0, body.length, Endian.big);
  out.setRange(4, out.length, body);
  return out;
}

/// Erro de protocolo: a ligação deve ser fechada.
class FrameException implements Exception {
  FrameException(this.message);
  final String message;
  @override
  String toString() => 'FrameException: $message';
}

/// Junta os bytes que chegam do socket (em pedaços arbitrários) e devolve
/// um objeto JSON por frame completa.
class FrameDecoder
    extends StreamTransformerBase<List<int>, Map<String, dynamic>> {
  const FrameDecoder();

  @override
  Stream<Map<String, dynamic>> bind(Stream<List<int>> stream) {
    return Stream.eventTransformed(stream, _FrameSink.new);
  }
}

class _FrameSink implements EventSink<List<int>> {
  _FrameSink(this._out);

  final EventSink<Map<String, dynamic>> _out;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  @override
  void add(List<int> chunk) {
    _buffer.add(_pending);
    _buffer.add(chunk);
    var data = _buffer.takeBytes();
    var offset = 0;
    while (data.length - offset >= 4) {
      final len = ByteData.sublistView(data, offset, offset + 4)
          .getUint32(0, Endian.big);
      if (len > maxFrameBytes) {
        _out.addError(FrameException('Frame de $len bytes excede o máximo'));
        _pending = Uint8List(0);
        return;
      }
      if (data.length - offset - 4 < len) break;
      final body = Uint8List.sublistView(data, offset + 4, offset + 4 + len);
      offset += 4 + len;
      try {
        final decoded = jsonDecode(utf8.decode(body));
        if (decoded is! Map) throw const FormatException('não é um objeto');
        _out.add(decoded.cast<String, dynamic>());
      } on FormatException catch (e) {
        _out.addError(FrameException('JSON inválido: ${e.message}'));
      }
    }
    _pending = Uint8List.fromList(Uint8List.sublistView(data, offset));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _out.addError(error, stackTrace);

  @override
  void close() => _out.close();
}
