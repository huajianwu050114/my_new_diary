// file: lib/main.dart

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

// VVV 1. 導入Firebase核心套件和自動生成的設定檔 VVV
//import 'package:firebase_core/firebase_core.dart';
//import 'firebase_options.dart.bak';

import 'diary_service.dart';
import 'home_page.dart';
import 'theme_provider.dart';
import 'user_provider.dart';
import 'favorites_provider.dart';
//import 'auth_gate.dart.bak';
import 'festival_service.dart';
import 'notification_service.dart';
import 'diary_home_page.dart';
import 'themes.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  // 確保Flutter綁定已初始化
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // 初始化 FFI
    sqfliteFfiInit();
    // 将数据库工厂设置为 FFI 工厂
    databaseFactory = databaseFactoryFfi;
  }

  // VVV 2. 在運行App之前，異步初始化Firebase VVV
  //await Firebase.initializeApp(
  //  options: DefaultFirebaseOptions.currentPlatform,
  //);

  // 你其他的初始化程式碼
  await initializeDateFormatting('zh_CN', null);
  await NotificationService().init();

  // 3. 只有在所有初始化都完成後，才運行App
  runApp(
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



// MyApp class (保持不變)
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: '我的日记',
      // VVV 3. 使用新文件中的主题 VVV
      theme: AppThemes.fromAppTheme(themeProvider.lightTheme),
      darkTheme: AppThemes.fromAppTheme(themeProvider.darkTheme),
      themeMode: themeProvider.themeMode,
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}