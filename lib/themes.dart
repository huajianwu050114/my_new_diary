import 'package:flutter/material.dart';
import 'app_theme.dart'; // 导入我们的主题模型

class AppThemes {
  // 核心方法：根据传入的 AppTheme 对象生成完整的 ThemeData
  static ThemeData fromAppTheme(AppTheme appTheme) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: appTheme.seedColor,
      brightness: appTheme.brightness,
    );

    final baseTheme = ThemeData(
      useMaterial3: true,
      fontFamily: 'MiSans',
      colorScheme: colorScheme,
    );

    return baseTheme.copyWith(
      scaffoldBackgroundColor: colorScheme.background,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: appTheme.brightness == Brightness.light ? 2.0 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15.0),
          side: appTheme.brightness == Brightness.dark
              ? BorderSide(color: colorScheme.outline.withOpacity(0.5))
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
        ),
      ),
    );
  }
}