// file: lib/auth_gate.dart
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'home_page.dart';
import 'dart:io' show Platform;

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _isLocked = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // --- VVV 这里是核心修改 VVV ---
    // 检查当前平台是否是Windows
    if (Platform.isWindows) {
      // 如果是Windows，为了方便开发，我们直接解锁
      print("检测到Windows平台，为方便开发，已自动跳过应用锁。");
      setState(() {
        _isLocked = false;
      });
    } else {
      // 如果是其他平台（如Android, iOS），则正常启动认证
      _authenticate();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 在Windows上，这个逻辑也将被跳过，不会在恢复时锁定
    if (state == AppLifecycleState.resumed && !_isLocked && !Platform.isWindows) {
      setState(() {
        _isLocked = true;
      });
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    // 如果已经是解锁状态，则不重复认证
    if (!_isLocked) return;

    try {
      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: '请验证身份以继续访问日记',
        options: const AuthenticationOptions(
          biometricOnly: false,
        ),
      );
      if (mounted) {
        setState(() {
          _isLocked = !didAuthenticate;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLocked = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocked) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('日记已锁定', style: TextStyle(fontSize: 24)),
              const SizedBox(height: 20),
              // 在Windows上，额外显示一条提示信息
              if (Platform.isWindows)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  child: Text(
                    '检测到您正在Windows上运行。如果您的设备没有指纹或面容识别，此按钮可能无效。请重启应用以跳过锁定。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ElevatedButton.icon(
                icon: const Icon(Icons.lock_open),
                label: const Text('解锁'),
                onPressed: _authenticate,
              ),
            ],
          ),
        ),
      );
    }
    return const HomePage();
  }
}