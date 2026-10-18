// Gera os ícones Android da app a partir do símbolo SVG do EDHere.
//
// Uso: flutter test tool/icons/render_icons_test.dart
//
// Escreve em android/app/src/main/res:
//  - mipmap-*/ic_launcher.png            (ícone clássico, fundo arredondado)
//  - mipmap-*/ic_launcher_foreground.png (camada da frente do ícone adaptativo)
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const _background = Color(0xFF0B111C);
const _res = 'android/app/src/main/res';
const _densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};

Future<void> _write(PictureInfo symbol, String path, int size,
    {required double symbolFraction, required bool withBackground}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final s = size.toDouble();
  if (withBackground) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.22)),
      Paint()..color = _background,
    );
  }
  final scale = s * symbolFraction / max(symbol.size.width, symbol.size.height);
  canvas.translate((s - symbol.size.width * scale) / 2, (s - symbol.size.height * scale) / 2);
  canvas.scale(scale);
  canvas.drawPicture(symbol.picture);
  final image = await rec.endRecording().toImage(size, size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  testWidgets('gera os ícones', (tester) async {
    await tester.runAsync(() async {
      final svg = File('assets/logo/edhere-logo-svg/edhere-simbolo-dark.svg').readAsStringSync();
      final symbol = await vg.loadPicture(SvgStringLoader(svg), null);
      for (final MapEntry(key: d, value: k) in _densities.entries) {
        await _write(symbol, '$_res/mipmap-$d/ic_launcher.png', (48 * k).round(),
            symbolFraction: 0.72, withBackground: true);
        // Área visível do ícone adaptativo: os 66 dp centrais de 108 dp.
        await _write(symbol, '$_res/mipmap-$d/ic_launcher_foreground.png', (108 * k).round(),
            symbolFraction: 0.5, withBackground: false);
      }
    });
  });
}
