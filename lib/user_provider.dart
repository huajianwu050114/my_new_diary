// file: lib/user_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProvider extends ChangeNotifier {
  String _nickname = "游客007";
  String? _avatarPath;

  String get nickname => _nickname;
  String? get avatarPath => _avatarPath;

  UserProvider() {
    // 构造函数中加载保存的数据
    loadUser();
  }

  // 从本地存储加载数据
  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    _nickname = prefs.getString('nickname') ?? "游客007";
    _avatarPath = prefs.getString('avatarPath');
    notifyListeners();
  }

  // 更新并保存数据
  Future<void> updateUser(String newNickname, String? newAvatarPath) async {
    final prefs = await SharedPreferences.getInstance();

    _nickname = newNickname;
    await prefs.setString('nickname', newNickname);

    if (newAvatarPath != null) {
      _avatarPath = newAvatarPath;
      await prefs.setString('avatarPath', newAvatarPath);
    }

    notifyListeners();
  }
}