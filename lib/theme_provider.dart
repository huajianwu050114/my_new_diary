// file: lib/theme_provider.dart

import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  // We will now have only ONE set of gradients for light mode
  final List<List<Color>> _lightGradients = const [
    [Color(0xffff9a9e), Color(0xfffad0c4)],
    [Color(0xffa18cd1), Color(0xfffbc2eb)],
    [Color(0xff84fab0), Color(0xff8fd3f4)],
    [Color(0xfffccb90), Color(0xffd57eeb)],
    [Color(0xffa6c0fe), Color(0xfff68084)],
    [Color(0xfff6d365), Color(0xfffda085)],
    // Added colors from the previous festival list for more variety
    [Color(0xff667eea), Color(0xff764ba2)],
    [Color(0xff89f7fe), Color(0xff66a6ff)],
  ];

  // And ONE set for dark mode
  final List<List<Color>> _darkGradients = const [
    // 深海蓝 -> 星云紫
    [Color(0xFF0D47A1), Color(0xFF4527A0)],
    // 墨绿 -> 森林青
    [Color(0xFF004D40), Color(0xFF00796B)],
    // 石板灰 -> 月光银
    [Color(0xFF37474F), Color(0xFF546E7A)],
    // 午夜蓝 -> 黎明灰
    [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
    // 玫瑰紫 -> 晚霞粉
    [Color(0xFF880E4F), Color(0xFFC2185B)],
    // 炭黑 -> 深空灰
    [Color(0xFF212121), Color(0xFF424242)],
  ];

  List<List<Color>> get cardGradientColors => isDarkMode ? _darkGradients : _lightGradients;

  // This single getter will now provide colors for ALL cards


  // We no longer need a separate festivalGradientColors getter

  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    } else {
      return _themeMode == ThemeMode.dark;
    }
  }

  void toggleTheme(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}