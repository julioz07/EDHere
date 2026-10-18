import 'dart:async';

import 'package:mesa_protocol/mesa_protocol.dart';
import 'package:test/test.dart';

Future<List<Map<String, dynamic>>> decodeChunks(List<List<int>> chunks) =>
    Stream.fromIterable(chunks).transform(const FrameDecoder()).toList();

void main() {
  test('frame completa num só pedaço', () async {
    final out = await decodeChunks([
      encodeFrame({'a': 1}),
    ]);
    expect(out, [
      {'a': 1}
    ]);
  });

  test('várias frames no mesmo pedaço', () async {
    final out = await decodeChunks([
      [...encodeFrame({'n': 1}), ...encodeFrame({'n': 2}), ...encodeFrame({'n': 3})],
    ]);
    expect(out.map((m) => m['n']), [1, 2, 3]);
  });

  test('frame partida byte a byte, com texto não ASCII', () async {
    final bytes = [
      ...encodeFrame({'nome': 'Júlio', 'carta': 'Æther Vial'}),
      ...encodeFrame({'n': 2}),
    ];
    final out = await decodeChunks([for (final b in bytes) [b]]);
    expect(out, [
      {'nome': 'Júlio', 'carta': 'Æther Vial'},
      {'n': 2},
    ]);
  });

  test('cabeçalho partido entre pedaços', () async {
    final bytes = encodeFrame({'x': 'y'});
    final out = await decodeChunks([bytes.sublist(0, 2), bytes.sublist(2)]);
    expect(out, [
      {'x': 'y'}
    ]);
  });

  test('frame acima do máximo dá erro', () async {
    final header = [0x7f, 0xff, 0xff, 0xff];
    expect(decodeChunks([header]), throwsA(isA<FrameException>()));
  });

  test('envelope sobrevive a ida e volta', () async {
    final env = Envelope.intent('ping', actor: 2, payload: {'k': 'v'})
        .withSeq(42);
    final out = await decodeChunks([encodeFrame(env.toJson())]);
    final back = Envelope.fromJson(out.single);
    expect(back.seq, 42);
    expect(back.type, 'ping');
    expect(back.actor, 2);
    expect(back.payload, {'k': 'v'});
    expect(back.v, protocolVersion);
  });

  test('envelope sem type é recusado', () {
    expect(() => Envelope.fromJson({'seq': 1}), throwsFormatException);
  });
}
