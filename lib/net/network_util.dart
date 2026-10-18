import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

/// Endereços IPv4 deste dispositivo que outros na rede local podem usar.
///
/// Inclui a interface do hotspot, que o `network_info_plus` não vê.
/// Com [preferHotspot], o endereço do hotspot vem primeiro: é o único que os
/// clientes ligados ao hotspot conseguem alcançar.
Future<List<String>> localIPv4Addresses({bool preferHotspot = false}) async {
  // A interface do hotspot pode demorar um pouco a aparecer depois de ligado.
  final attempts = preferHotspot ? 6 : 1;
  var result = <String>[];
  for (var i = 0; i < attempts; i++) {
    result = await _rankedAddresses(preferHotspot);
    if (!preferHotspot || _hotspotFound) break;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return result;
}

bool _hotspotFound = false;

Future<List<String>> _rankedAddresses(bool preferHotspot) async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  // IP do Wi-Fi em modo cliente (router de casa); o do hotspot é outro.
  final wifiIp = preferHotspot ? await _wifiIp() : null;
  final entries = <(String, String)>[
    for (final i in interfaces)
      for (final a in i.addresses)
        if (!a.isLoopback && !a.isLinkLocal) (i.name, a.address),
  ];

  bool looksLikeHotspot(String iface, String ip) {
    if (ip == wifiIp) return false;
    final n = iface.toLowerCase();
    return n.contains('ap') || n.startsWith('swlan') || n == 'wlan1' || n.contains('softap');
  }

  int rank((String, String) e) {
    final (iface, ip) = e;
    if (preferHotspot && looksLikeHotspot(iface, ip)) return 0;
    // Mobile data (rmnet, ccmni) não serve na rede local.
    final n = iface.toLowerCase();
    if (n.startsWith('rmnet') || n.startsWith('ccmni') || n.startsWith('pdp')) {
      return 9;
    }
    if (ip.startsWith('192.168.')) return 1;
    if (ip.startsWith('10.')) return 2;
    if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) return 3;
    return 4;
  }

  entries.sort((a, b) => rank(a).compareTo(rank(b)));
  _hotspotFound = entries.any((e) => rank(e) == 0);
  return entries.map((e) => e.$2).toSet().toList();
}

Future<String?> _wifiIp() async {
  try {
    return await NetworkInfo().getWifiIP();
  } catch (_) {
    return null;
  }
}

/// IP do gateway do Wi-Fi atual. Num hotspot, é o próprio anfitrião.
Future<String?> wifiGatewayIp() async {
  try {
    final ip = await NetworkInfo().getWifiGatewayIP();
    if (ip == null || ip.isEmpty || ip == '0.0.0.0') return null;
    return ip;
  } catch (_) {
    return null;
  }
}

bool isValidIPv4(String s) {
  final parts = s.trim().split('.');
  if (parts.length != 4) return false;
  return parts.every((p) {
    final n = int.tryParse(p);
    return n != null && n >= 0 && n <= 255 && p == '$n';
  });
}
