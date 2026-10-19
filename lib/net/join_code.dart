import '../l10n/l10n.dart';

/// Conteúdo do QR code de uma sala: `edhere://join?h=IP1,IP2&p=PORTA&n=NOME&k=1`.
class JoinCode {
  const JoinCode({
    required this.hosts,
    required this.port,
    required this.roomName,
    this.hasPin = false,
  });

  final List<String> hosts;
  final int port;
  final String roomName;
  final bool hasPin;

  String encode() => Uri(
        scheme: 'edhere',
        host: 'join',
        queryParameters: {
          'h': hosts.join(','),
          'p': '$port',
          'n': roomName,
          if (hasPin) 'k': '1',
        },
      ).toString();

  static JoinCode? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'edhere' || uri.host != 'join') return null;
    final q = uri.queryParameters;
    final hosts = (q['h'] ?? '').split(',').where((h) => h.isNotEmpty).toList();
    final port = int.tryParse(q['p'] ?? '');
    if (hosts.isEmpty || port == null) return null;
    return JoinCode(
      hosts: hosts,
      port: port,
      roomName: q['n'] ?? tr('Sala'),
      hasPin: q['k'] == '1',
    );
  }
}

/// QR Wi-Fi standard, que a câmara do Android 10+ e do iOS usa para ligar
/// à rede sem escrever a password.
String wifiQr({required String ssid, required String password}) {
  String esc(String s) => s.replaceAllMapped(RegExp(r'([\\;,:"])'), (m) => '\\${m[1]}');
  return 'WIFI:T:WPA;S:${esc(ssid)};P:${esc(password)};;';
}
