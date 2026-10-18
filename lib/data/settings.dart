import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_paths.dart';
import 'providers.dart';

/// Fundos da área de jogo que vêm com a app.
class TableBackground {
  const TableBackground(this.id, this.label, this.asset);
  final String id;
  final String label;
  final String asset;

  static const _dir = 'assets/Fundos para area de jogo/edhere-fundos';
  static const builtIn = [
    TableBackground('eter', 'Éter', '$_dir/01-eter-oficial.webp'),
    TableBackground('feltro', 'Feltro azul', '$_dir/03-feltro-azul.webp'),
    TableBackground('ardosia', 'Ardósia', '$_dir/04-ardosia.webp'),
    TableBackground('nebulosa', 'Nebulosa', '$_dir/05-nebulosa.webp'),
    TableBackground('arcano', 'Círculo arcano', '$_dir/06-circulo-arcano.webp'),
  ];
}

/// Logótipos e verso de carta.
abstract final class Brand {
  static const _logo = 'assets/logo/edhere-logo-svg';
  static String horizontal(Brightness b) =>
      '$_logo/edhere-logo-horizontal-${b == Brightness.dark ? 'dark' : 'light'}.svg';
  static String vertical(Brightness b) =>
      '$_logo/edhere-logo-vertical-${b == Brightness.dark ? 'dark' : 'light'}.svg';
  static String symbol(Brightness b) =>
      '$_logo/edhere-simbolo-${b == Brightness.dark ? 'dark' : 'light'}.svg';
  static const cardBack = 'assets/Verso de carta/edhere-verso/edhere-verso-carta-488.webp';
}

/// Preferências do utilizador, guardadas no dispositivo.
class Settings extends ChangeNotifier {
  Settings(this._prefs, this._paths);

  final SharedPreferences _prefs;
  final AppPaths _paths;

  static const _kTheme = 'theme_mode';
  static const _kBg = 'table_background';
  static const _kDim = 'table_background_dim';
  static const _kCardScale = 'table_card_scale';
  static const _kAutoDraw = 'auto_draw';
  static const _kDoubleTap = 'double_tap_to_tap';
  static const _kSortHand = 'sort_hand';
  static const _kKeepOn = 'keep_screen_on';
  static const _kConfirmLeave = 'confirm_leave';

  ThemeMode get themeMode => switch (_prefs.getString(_kTheme)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
  set themeMode(ThemeMode m) => _set(_kTheme, m.name);

  /// `none`, `asset:<id>` ou `file` (imagem escolhida da galeria).
  String get background => _prefs.getString(_kBg) ?? 'asset:eter';
  set background(String v) => _set(_kBg, v);

  /// Quanto se escurece o fundo para as cartas se lerem bem (0 a 0,8).
  double get backgroundDim => _prefs.getDouble(_kDim) ?? 0.35;
  set backgroundDim(double v) => _setDouble(_kDim, v);

  /// Tamanho das cartas no campo (1 = normal).
  double get cardScale => _prefs.getDouble(_kCardScale) ?? 1.0;
  set cardScale(double v) => _setDouble(_kCardScale, v);

  bool get autoDraw => _prefs.getBool(_kAutoDraw) ?? false;
  set autoDraw(bool v) => _setBool(_kAutoDraw, v);

  bool get doubleTapToTap => _prefs.getBool(_kDoubleTap) ?? true;
  set doubleTapToTap(bool v) => _setBool(_kDoubleTap, v);

  bool get sortHand => _prefs.getBool(_kSortHand) ?? true;
  set sortHand(bool v) => _setBool(_kSortHand, v);

  bool get keepScreenOn => _prefs.getBool(_kKeepOn) ?? true;
  set keepScreenOn(bool v) => _setBool(_kKeepOn, v);

  bool get confirmLeave => _prefs.getBool(_kConfirmLeave) ?? true;
  set confirmLeave(bool v) => _setBool(_kConfirmLeave, v);

  /// Caminho da imagem de fundo escolhida da galeria.
  String get customBackgroundPath => '${_paths.root}${Platform.pathSeparator}fundo-personalizado';

  /// Imagem a desenhar por trás da mesa, ou null para nenhuma.
  ImageProvider? get backgroundImage {
    final bg = background;
    if (bg == 'none') return null;
    if (bg == 'file') {
      final f = File(customBackgroundPath);
      return f.existsSync() ? FileImage(f) : null;
    }
    final id = bg.startsWith('asset:') ? bg.substring(6) : bg;
    final match = TableBackground.builtIn.where((b) => b.id == id);
    return match.isEmpty ? null : AssetImage(match.first.asset);
  }

  /// Copia uma imagem da galeria para a pasta da app e usa-a como fundo.
  Future<void> useCustomBackground(String sourcePath) async {
    final target = File(customBackgroundPath);
    await File(sourcePath).copy(target.path);
    // A imagem anterior com o mesmo caminho pode estar em cache.
    PaintingBinding.instance.imageCache.evict(FileImage(target));
    imageCacheVersion++;
    _set(_kBg, 'file');
  }

  /// Muda quando a imagem personalizada é trocada (para forçar o redesenho).
  int imageCacheVersion = 0;

  void _set(String k, String v) {
    _prefs.setString(k, v);
    notifyListeners();
  }

  void _setBool(String k, bool v) {
    _prefs.setBool(k, v);
    notifyListeners();
  }

  void _setDouble(String k, double v) {
    _prefs.setDouble(k, v);
    notifyListeners();
  }
}

final settingsProvider = ChangeNotifierProvider<Settings>(
    (ref) => Settings(ref.watch(prefsProvider), ref.watch(pathsProvider)));
