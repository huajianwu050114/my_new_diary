// file: lib/themes.dart (这是一个新文件)

import 'package:flutter/material.dart';

// 定义一个枚举来表示不同的主题
enum AppTheme {
  dracula,
  nord,
  github,
}

// 将主题数据集中管理
final appThemes = {
  AppTheme.dracula: ThemeData(
    brightness: Brightness.dark,
    fontFamily: 'MiSans',
    scaffoldBackgroundColor: const Color(0xFF282a36), // Dracula 背景色
    primaryColor: const Color(0xFFbd93f9), // Dracula 紫色
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFbd93f9), // 紫色
      secondary: Color(0xFF50fa7b), // 绿色
      surface: Color(0xFF44475a), // Dracula 卡片/表面色
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: Color(0xFFf8f8f2), // Dracula 文字颜色
    ),
    cardColor: const Color(0xFF44475a),
    dividerColor: const Color(0xFF6272a4),
  ),

  AppTheme.nord: ThemeData(
    brightness: Brightness.dark,
    fontFamily: 'MiSans',
    scaffoldBackgroundColor: const Color(0xFF2E3440), // Nord 背景色
    primaryColor: const Color(0xFF88C0D0), // Nord 浅蓝色
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF88C0D0), // 浅蓝色
      secondary: Color(0xFF81A1C1), // 蓝灰色
      surface: Color(0xFF3B4252), // Nord 卡片/表面色
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: Color(0xFFECEFF4), // Nord 文字颜色
    ),
    cardColor: const Color(0xFF3B4252),
    dividerColor: const Color(0xFF4C566A),
  ),

  AppTheme.github: ThemeData(
    brightness: Brightness.dark,
    fontFamily: 'MiSans',
    scaffoldBackgroundColor: const Color(0xFF0D1117), // GitHub 背景色
    primaryColor: const Color(0xFF58A6FF), // GitHub 蓝色
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF58A6FF), // 蓝色
      secondary: Color(0xFF3FB950), // 绿色
      surface: Color(0xFF161B22), // GitHub 卡片/表面色
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Color(0xFFC9D1D9), // GitHub 文字颜色
    ),
    cardColor: const Color(0xFF161B22),
    dividerColor: const Color(0xFF21262D),
  ),
};