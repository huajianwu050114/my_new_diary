// file: lib/themes.dart

import 'package:flutter/material.dart';

class AppThemes {
  // --- 日间模式 (暂时保持不变) ---
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.deepPurple,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.purple.shade100,
      brightness: Brightness.light,
    ),
    useMaterial3: true,
    fontFamily: 'MiSans',
    scaffoldBackgroundColor: const Color(0xFFF8F7FA),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.purple.shade50.withOpacity(0.5),
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      elevation: 2.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15.0),
      ),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    ),
    textTheme: TextTheme(
      bodyMedium: const TextStyle(fontSize: 16.0, color: Colors.black87),
      titleMedium: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
      bodySmall: TextStyle(fontSize: 12.0, color: Colors.grey[600]),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.deepPurple,
      ),
    ),
  );

  // --- VVV 全新设计的夜间模式 VVV ---
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    fontFamily: 'MiSans',
    useMaterial3: true,

    // 核心颜色：使用更深的“近黑”色调
    scaffoldBackgroundColor: const Color(0xFF0D1117), // 深空黑背景
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF58A6FF), // 静谧蓝作为主色调
      brightness: Brightness.dark,
      primary: const Color(0xFF58A6FF),
      secondary: const Color(0xFF8B949E), // 中性灰色作为次要颜色
      surface: const Color(0xFF161B22), // 炭灰色用于表面
      onSurface: const Color(0xFFC9D1D9), // 柔和白文字
    ),

    // 卡片主题：使用比背景稍亮的纯色
    cardTheme: CardThemeData(
      color: const Color(0xFF161B22), // 炭灰色卡片
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15.0),
        side: const BorderSide(color: Color(0xFF30363D), width: 1), // 添加一个微妙的边框增加质感
      ),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    ),

    // 其他组件样式
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF161B22), // 使用卡片/表面颜色
      elevation: 0,
      centerTitle: true,
    ),
    textTheme: TextTheme(
      bodyMedium: TextStyle(fontSize: 16.0, color: Colors.white.withOpacity(0.87)),
      titleMedium: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.87)),
      bodySmall: TextStyle(fontSize: 12.0, color: Colors.white.withOpacity(0.6)),
    ),
    dividerTheme: DividerThemeData(
      color: const Color(0xFF30363D),
    ),
  );
}