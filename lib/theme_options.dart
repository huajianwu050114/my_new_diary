import 'package:flutter/material.dart';
import 'app_theme.dart';

// 这个类包含了我们预设的所有主题
class ThemeOptions {
  // --- 可选的浅色主题列表 ---
  static final List<AppTheme> lightThemes = [
    const AppTheme(name: '柔和紫', seedColor: Color(0xFFB5A8E3), brightness: Brightness.light),
    const AppTheme(name: '森系绿', seedColor: Color(0xFF92C79E), brightness: Brightness.light),
    const AppTheme(name: '日落橘', seedColor: Color(0xFFF7B7A3), brightness: Brightness.light),
    const AppTheme(name: '海洋蓝', seedColor: Color(0xFFA0C4FF), brightness: Brightness.light),
    const AppTheme(name: '樱花粉', seedColor: Color(0xFFFFC4D6), brightness: Brightness.light),
  ];

  // --- 可选的深色主题列表 ---
  static final List<AppTheme> darkThemes = [
    const AppTheme(name: '静谧蓝', seedColor: Color(0xFF58A6FF), brightness: Brightness.dark),
    const AppTheme(name: '石墨灰', seedColor: Color(0xFF8B949E), brightness: Brightness.dark),
    const AppTheme(name: '赛博绿', seedColor: Color(0xFF39D39F), brightness: Brightness.dark),
    const AppTheme(name: '恶魔紫', seedColor: Color(0xFFBF85DB), brightness: Brightness.dark),
  ];
}