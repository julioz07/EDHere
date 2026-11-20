import 'dart:io';

import 'package:edhoff/data/app_paths.dart';
import 'package:edhoff/data/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(Settings, SharedPreferences)> _settings(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  return (Settings(prefs, AppPaths.forTest(Directory.systemTemp.path)), prefs);
}

void main() {
  test('uiStyle por omissão é classic (quem atualiza da 2.2.2 vê o de hoje)', () async {
    final (s, _) = await _settings({'theme_mode': 'dark'});
    expect(s.uiStyle, UiStyle.classic);
  });

  test('uiStyle grava e notifica', () async {
    final (s, prefs) = await _settings({});
    var calls = 0;
    s.addListener(() => calls++);
    s.uiStyle = UiStyle.enchanted;
    expect(prefs.getString('ui_style'), 'enchanted');
    expect(s.uiStyle, UiStyle.enchanted);
    expect(calls, 1);
  });

  test('um valor desconhecido volta a classic', () async {
    final (s, _) = await _settings({'ui_style': 'neon'});
    expect(s.uiStyle, UiStyle.classic);
  });
}
