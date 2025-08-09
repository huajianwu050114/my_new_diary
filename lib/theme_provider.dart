import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'theme_options.dart';

class ThemeProvider extends ChangeNotifier {
  AppTheme _lightTheme = ThemeOptions.lightThemes.first;
  AppTheme _darkTheme = ThemeOptions.darkThemes.first;
  ThemeMode _themeMode = ThemeMode.system;

  // 构造函数中加载用户设置
  ThemeProvider() {
    _loadThemeSettings();
  }

  // Getters
  AppTheme get lightTheme => _lightTheme;
  AppTheme get darkTheme => _darkTheme;
  ThemeMode get themeMode => _themeMode;
  List<AppTheme> get availableLightThemes => ThemeOptions.lightThemes;
  List<AppTheme> get availableDarkThemes => ThemeOptions.darkThemes;

  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    } else {
      return _themeMode == ThemeMode.dark;
    }
  }

  // 加载设置
  Future<void> _loadThemeSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // 加载浅色主题
    final lightThemeName = prefs.getString('light_theme_name') ?? availableLightThemes.first.name;
    _lightTheme = availableLightThemes.firstWhere((t) => t.name == lightThemeName, orElse: () => availableLightThemes.first);

    // 加载深色主题
    final darkThemeName = prefs.getString('dark_theme_name') ?? availableDarkThemes.first.name;
    _darkTheme = availableDarkThemes.firstWhere((t) => t.name == darkThemeName, orElse: () => availableDarkThemes.first);

    // 加载主题模式 (Light/Dark/System)
    final themeModeIndex = prefs.getInt('theme_mode') ?? ThemeMode.system.index;
    _themeMode = ThemeMode.values[themeModeIndex];

    notifyListeners();
  }

  // --- Setters ---
  void setLightTheme(AppTheme theme) async {
    if (theme.brightness == Brightness.light) {
      _lightTheme = theme;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('light_theme_name', theme.name);
      notifyListeners();
    }
  }

  void setDarkTheme(AppTheme theme) async {
    if (theme.brightness == Brightness.dark) {
      _darkTheme = theme;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dark_theme_name', theme.name);
      notifyListeners();
    }
  }

  void setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
    notifyListeners();
  }
}