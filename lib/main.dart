/// file: lib/main.dart

import 'package:flutter/material.dart';
// import 'package:table_calendar/table_calendar.dart'; // 已移至 diary_home_page.dart
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';
// import 'add_diary_page.dart'; // 已移至 diary_home_page.dart
// import 'dart:io'; // 已移至 diary_home_page.dart
// import 'diary_view_page.dart'; // 已移至 diary_home_page.dart
// import 'package:flutter_slidable/flutter_slidable.dart'; // 已移至 diary_home_page.dart
import 'home_page.dart';
import 'theme_provider.dart';
import 'user_provider.dart';
import 'favorites_provider.dart';
import 'auth_gate.dart';
import 'festival_service.dart';
import 'notification_service.dart';
import 'diary_home_page.dart'; // <-- 新增的导入

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN', null);
  await NotificationService().init();
  runApp(
    // <-- 2. 使用 MultiProvider 来注册多个状态管理器
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => DiaryService()),
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => UserProvider()),
        ChangeNotifierProvider(create: (context) => FavoritesProvider()),
        ChangeNotifierProvider(create: (context) => FestivalProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

// --- 3. 定义两种主题 ---

// 明亮主题 (我们之前的配置)
final ThemeData lightTheme = ThemeData(
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
// 夜间主题
final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  primarySwatch: Colors.deepPurple,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.deepPurple,
    brightness: Brightness.dark, // 关键！设置为暗色
  ),
  useMaterial3: true,
  fontFamily: 'MiSans',
  scaffoldBackgroundColor: const Color(0xFF121212), // 深黑色背景
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.grey.shade900.withOpacity(0.5),
    elevation: 0,
    centerTitle: true,
  ),
  cardTheme: CardThemeData(
    color: const Color(0xFF1E1E1E), // 卡片颜色比背景稍亮
    elevation: 2.0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15.0),
    ),
    clipBehavior: Clip.antiAlias,
    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
  ),
  textTheme: TextTheme(
    bodyMedium: TextStyle(fontSize: 16.0, color: Colors.white.withOpacity(0.87)),
    titleMedium: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.87)),
    bodySmall: TextStyle(fontSize: 12.0, color: Colors.white.withOpacity(0.6)),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: Colors.purple.shade200,
    ),
  ),
);
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // <-- 4. 从 ThemeProvider 获取当前的主题模式
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: '我的日记',
      // 应用我们定义好的主题
      theme: lightTheme,
      darkTheme: darkTheme,
      // 关键！根据 themeProvider 的状态来决定使用哪个主题
      themeMode: themeProvider.themeMode,
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- DiaryHomePage 和 _DiaryHomePageState 类已从此文件移除 ---