import 'package:flutter/services.dart';

/// Os efeitos sonoros da mesa contra o bot (tocados pelo SoundPool do
/// Android; ver MainActivity e tool/sfx/gen_sfx.py).
abstract final class Sfx {
  static const _ch = MethodChannel('edhere/sfx');

  static const prefKey = 'bot_sound';
  static bool enabled = true;

  /// Carrega os sons (o primeiro "play" só os prepara).
  static void warm() => _play('', 0);

  static void card() => _play('card', 0.7);
  static void land() => _play('land', 0.9);
  static void attack() => _play('attack', 0.8);
  static void hit() => _play('hit', 1);
  static void death() => _play('death', 0.8);
  static void gain() => _play('gain', 0.7);
  static void turn() => _play('turn', 0.5);
  static void win() => _play('win', 0.9);
  static void lose() => _play('lose', 0.9);

  static void _play(String name, double volume) {
    if (!enabled && name.isNotEmpty) return;
    _ch.invokeMethod('play', {'name': name, 'volume': volume}).catchError((Object _) {});
  }
}
