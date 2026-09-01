import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppPaletteV2 {
  twilight(
    label: '暮紫',
    description: '安静柔和',
    seedColor: Color(0xFF6750A4),
    lightBackground: Color(0xFFF8F7FA),
    darkBackground: Color(0xFF121212),
  ),
  mistBlue(
    label: '雾蓝',
    description: '清澈克制',
    seedColor: Color(0xFF45637D),
    lightBackground: Color(0xFFF5F8FA),
    darkBackground: Color(0xFF101417),
  ),
  moss(
    label: '青苔',
    description: '自然沉静',
    seedColor: Color(0xFF526A57),
    lightBackground: Color(0xFFF5F8F4),
    darkBackground: Color(0xFF111512),
  ),
  apricot(
    label: '暖杏',
    description: '温暖明亮',
    seedColor: Color(0xFF9A5E3A),
    lightBackground: Color(0xFFFFF8F3),
    darkBackground: Color(0xFF181310),
  ),
  oldRose(
    label: '旧玫瑰',
    description: '温柔复古',
    seedColor: Color(0xFF8B5965),
    lightBackground: Color(0xFFFCF6F7),
    darkBackground: Color(0xFF171113),
  ),
  ink(
    label: '墨色',
    description: '简洁中性',
    seedColor: Color(0xFF545B62),
    lightBackground: Color(0xFFF7F7F6),
    darkBackground: Color(0xFF101112),
  );

  const AppPaletteV2({
    required this.label,
    required this.description,
    required this.seedColor,
    required this.lightBackground,
    required this.darkBackground,
  });

  final String label;
  final String description;
  final Color seedColor;
  final Color lightBackground;
  final Color darkBackground;
}

class ThemeControllerV2 extends ChangeNotifier {
  static const _preferenceKey = 'v2_theme_mode';
  static const _palettePreferenceKey = 'v2_color_palette';

  ThemeMode _mode = ThemeMode.system;
  AppPaletteV2 _palette = AppPaletteV2.twilight;

  ThemeMode get mode => _mode;
  AppPaletteV2 get palette => _palette;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _mode = switch (preferences.getString(_preferenceKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final paletteName = preferences.getString(_palettePreferenceKey);
    _palette = AppPaletteV2.values.firstWhere(
      (palette) => palette.name == paletteName,
      orElse: () => AppPaletteV2.twilight,
    );
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) {
      return;
    }
    _mode = mode;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, mode.name);
  }

  Future<void> setPalette(AppPaletteV2 palette) async {
    if (_palette == palette) return;
    _palette = palette;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_palettePreferenceKey, palette.name);
  }
}
