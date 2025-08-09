import 'package:flutter/material.dart';

// 这个类代表一个可选择的主题方案
class AppTheme {
  final String name;
  final Color seedColor;
  final Brightness brightness;

  const AppTheme({
    required this.name,
    required this.seedColor,
    required this.brightness,
  });
}