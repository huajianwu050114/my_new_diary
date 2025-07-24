// file: lib/login_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // 用於切換登入和註冊模式的狀態
  bool _isLoginMode = true;
  // 用於在執行非同步操作時顯示載入動畫
  bool _isLoading = false;
  // 用於顯示來自Firebase的錯誤訊息
  String _errorMessage = '';

  // 用於獲取輸入框內容的控制器
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 提交表單的核心邏輯
  Future<void> _submitForm() async {
    // 簡單的客戶端驗證
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = '信箱和密碼不能為空';
      });
      return;
    }

    // 開始提交，顯示載入動畫並清空舊的錯誤訊息
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      if (_isLoginMode) {
        // --- 登入邏輯 ---
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        ).timeout(const Duration(seconds: 15)); // <--- VVV 加上15秒超時 VVV
      } else {
        // --- 註冊邏輯 ---
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        ).timeout(const Duration(seconds: 15)); // <--- VVV 加上15秒超時 VVV
      }
      // 如果成功，AuthGate會自動處理頁面跳轉，所以這裡不需要做任何事
    } on FirebaseAuthException catch (e) {
      // 處理來自Firebase的特定錯誤
      switch (e.code) {
        case 'user-not-found':
          _errorMessage = '该邮箱未注册。';
          break;
        case 'wrong-password':
          _errorMessage = '密码错误。';
          break;
        case 'email-already-in-use':
          _errorMessage = '该邮箱已被注册。';
          break;
        case 'weak-password':
          _errorMessage = '密码强度太弱。';
          break;
        case 'invalid-email':
          _errorMessage = '邮箱格式不正确。';
          break;
        default:
          _errorMessage = '发生未知错误，请稍后再试。';
      }
      setState(() {}); // 更新UI以顯示錯誤訊息
    } on TimeoutException catch (_) { // <--- VVV 捕獲超時錯誤 VVV
      _errorMessage = '請求超時，請檢查你的網路連線或VPN。';
      if (mounted) setState(() {});
    } catch (e) {
      // 處理其他非Firebase的未知錯誤
      _errorMessage = '发生未知错误，请稍后再试。';
      setState(() {});
    } finally {
      // 無論成功或失敗，最後都結束載入狀態
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLoginMode ? '登录' : '注册'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 標題
            Text(
              _isLoginMode ? '欢迎回来' : '创建新账号',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),

            // 信箱輸入框
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '電子信箱',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 密碼輸入框
            TextField(
              controller: _passwordController,
              obscureText: true, // 隱藏密碼
              decoration: const InputDecoration(
                labelText: '密碼',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            // 錯誤訊息顯示
            if (_errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  _errorMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),

            // 提交按鈕
            ElevatedButton(
              onPressed: _isLoading ? null : _submitForm, // 載入時禁用按鈕
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : Text(_isLoginMode ? '登入' : '註冊'),
            ),
            const SizedBox(height: 16),

            // 切換模式按鈕
            TextButton(
              onPressed: () {
                setState(() {
                  _isLoginMode = !_isLoginMode;
                  _errorMessage = ''; // 切換模式時清空錯誤訊息
                });
              },
              child: Text(_isLoginMode ? '還沒有帳戶？立即註冊' : '已經有帳戶了？前往登入'),
            ),
          ],
        ),
      ),
    );
  }
}