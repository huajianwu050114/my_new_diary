// file: lib/auth_gate.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'home_page.dart';
import 'login_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // StreamBuilder會持續監聽Firebase的認證狀態變化
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 狀態1：正在等待第一次的認證狀態...
        // 在App剛啟動，還在確認用戶是否登入時，顯示一個載入動畫。
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // 狀態2：用戶已登入 (snapshot.hasData 為 true)
        // authStateChanges() 這個流(stream)發出了一個非null的User對象。
        if (snapshot.hasData) {
          // 直接進入主頁
          return const HomePage();
        }

        // 狀態3：用戶未登入
        // authStateChanges() 這個流發出了一個 null。
        return const LoginPage();
      },
    );
  }
}