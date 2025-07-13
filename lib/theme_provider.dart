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
    [Color(0xFF2E3192), Color(0xFF1BFFFF)],
    [Color(0xFF673AB7), Color(0xFF512DA8)],
    [Color(0xFF0D47A1), Color(0xFF1976D2)],
    [Color(0xFF4527A0), Color(0xFF7E57C2)],
    [Color(0xFF006064), Color(0xFF0097A7)],
    [Color(0xFF1A237E), Color(0xFF303F9F)],
    // Added colors from the previous festival list for more variety
    [Color(0xff09203f), Color(0xff537895)],
    [Color(0xff2c3e50), Color(0xff4ca1af)],
  ];

  // This single getter will now provide colors for ALL cards
  List<List<Color>> get cardGradientColors => isDarkMode ? _darkGradients : _lightGradients;

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