// file: lib/main.dart

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

// VVV 1. 導入Firebase核心套件和自動生成的設定檔 VVV
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'diary_service.dart';
import 'home_page.dart';
import 'theme_provider.dart';
import 'user_provider.dart';
import 'favorites_provider.dart';
import 'auth_gate.dart';
import 'festival_service.dart';
import 'notification_service.dart';
import 'diary_home_page.dart';

void main() async {
  // 確保Flutter綁定已初始化
  WidgetsFlutterBinding.ensureInitialized();

  // VVV 2. 在運行App之前，異步初始化Firebase VVV
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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

// 明亮主題 (保持不變)
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

// 夜間主題 (保持不變)
final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  fontFamily: 'MiSans',
  useMaterial3: true,
  primarySwatch: Colors.blue,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4A90E2),
    brightness: Brightness.dark,
    primary: const Color(0xFF4A90E2),
    secondary: const Color(0xFF00796B),
  ),
  scaffoldBackgroundColor: const Color(0xFF121212),
  cardTheme: CardThemeData(
    color: const Color(0xFF1E1E1E),
    elevation: 2.0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
    clipBehavior: Clip.antiAlias,
    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
  ),
  textTheme: TextTheme(
    bodyMedium: TextStyle(fontSize: 16.0, color: Colors.white.withOpacity(0.87)),
    titleMedium: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.87)),
    bodySmall: TextStyle(fontSize: 12.0, color: Colors.white.withOpacity(0.6)),
  ),
  iconTheme: IconThemeData(color: Colors.white.withOpacity(0.87)),
  appBarTheme: AppBarTheme(
    backgroundColor: const Color(0xFF121212).withOpacity(0.8),
    elevation: 0,
    centerTitle: true,
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: const Color(0xFF4A90E2),
    ),
  ),
  dividerTheme: DividerThemeData(
    color: Colors.white.withOpacity(0.2),
  ),
);

// MyApp class (保持不變)
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: '我的日记',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeProvider.themeMode,
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}