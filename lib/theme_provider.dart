// file: lib/theme_provider.dart

import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  // 在这里直接定义两套颜色列表
  final List<List<Color>> _lightGradients = const [
    [Color(0xffff9a9e), Color(0xfffad0c4)],
    [Color(0xffa18cd1), Color(0xfffbc2eb)],
    [Color(0xff84fab0), Color(0xff8fd3f4)],
    [Color(0xfffccb90), Color(0xffd57eeb)],
    [Color(0xffa6c0fe), Color(0xfff68084)],
    [Color(0xfff6d365), Color(0xfffda085)],
  ];

  final List<List<Color>> _darkGradients = const [
    [Color(0xFF2E3192), Color(0xFF1BFFFF)],
    [Color(0xFF673AB7), Color(0xFF512DA8)],
    [Color(0xFF0D47A1), Color(0xFF1976D2)],
    [Color(0xFF4527A0), Color(0xFF7E57C2)],
    [Color(0xFF006064), Color(0xFF0097A7)],
    [Color(0xFF1A237E), Color(0xFF303F9F)],
  ];

  // 提供一个 getter，根据当前模式返回正确的颜色列表
  List<List<Color>> get cardGradientColors => isDarkMode ? _darkGradients : _lightGradients;

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