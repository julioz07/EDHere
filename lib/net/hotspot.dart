import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Rede criada pelo hotspot local do Android.
class HotspotInfo {
  const HotspotInfo({required this.ssid, required this.password});
  final String ssid;
  final String password;
}

class HotspotException implements Exception {
  const HotspotException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Hotspot local do Android (`LocalOnlyHotspot`, Android 8+), por platform
/// channel em Kotlin. No iOS o utilizador liga o Hotspot Pessoal à mão.
class Hotspot {
  static const _channel = MethodChannel('edhere/hotspot');

  static bool get isSupported => Platform.isAndroid;

  /// Pede as permissões necessárias e liga o hotspot.
  static Future<HotspotInfo> start() async {
    if (!isSupported) {
      throw const HotspotException('Só disponível no Android');
    }
    await _requestPermissions();
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('start');
      return HotspotInfo(
        ssid: res?['ssid'] as String? ?? '',
        password: res?['password'] as String? ?? '',
      );
    } on PlatformException catch (e) {
      throw HotspotException(_describe(e));
    }
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Já estava desligado.
    }
  }

  static Future<void> _requestPermissions() async {
    // Android 13+ usa NEARBY_WIFI_DEVICES; 8 a 12 usa a localização.
    final statuses = await [
      Permission.nearbyWifiDevices,
      Permission.locationWhenInUse,
    ].request();
    final nearby = statuses[Permission.nearbyWifiDevices];
    final location = statuses[Permission.locationWhenInUse];
    final granted = (nearby?.isGranted ?? false) || (location?.isGranted ?? false);
    if (!granted) {
      throw const HotspotException(
          'Sem permissão para criar o hotspot. Autoriza "Dispositivos próximos" '
          'ou "Localização" nas definições da app.');
    }
  }

  static String _describe(PlatformException e) => switch (e.code) {
        'incompatible_mode' =>
          'O hotspot normal do telemóvel está ligado. Desliga-o e tenta outra vez, '
              'ou usa-o diretamente: os outros ligam-se a ele.',
        'no_channel' => 'Sem canal Wi-Fi livre para o hotspot.',
        'tethering_disallowed' => 'O sistema não permite criar hotspots.',
        'location_off' => 'Liga a Localização do telemóvel para criar o hotspot.',
        'unsupported' => 'Precisa de Android 8 ou mais recente.',
        _ => e.message ?? 'Não foi possível criar o hotspot (${e.code}).',
      };
}
