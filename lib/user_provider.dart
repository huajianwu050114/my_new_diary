// file: lib/user_provider.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;

class UserProvider extends ChangeNotifier {
  // --- 状态变量 ---
  // 默认值，在用户信息加载前显示
  String _nickname = "旅人";
  // 头像将存储为云端URL，而不是本地路径
  String? _avatarUrl;

  // --- Getters ---
  String get nickname => _nickname;
  String? get avatarUrl => _avatarUrl;

  // --- 构造函数 ---
  UserProvider() {
    // 监听用户认证状态的变化
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        // 如果用户登录了，就加载他们的个人资料
        loadUser(user.uid);
      } else {
        // 如果用户退出了，就重置为默认值
        _resetToDefaults();
      }
    });
  }

  /// 从Firestore加载指定UID用户的个人资料
  Future<void> loadUser(String uid) async {
    try {
      // 获取指向用户文档的引用
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        // 如果文档存在，就从中读取数据
        final data = docSnapshot.data()!;
        _nickname = data['nickname'] ?? "旅人";
        _avatarUrl = data['avatarUrl'];
      } else {
        // 如果文档不存在（例如，用户是刚刚通过邮箱注册的），
        // 可以在这里创建一个带有默认值的文档
        await docRef.set({'nickname': '旅人', 'avatarUrl': null});
        _resetToDefaults();
      }
    } catch (e) {
      print("加载用户资料失败: $e");
      // 加载失败也使用默认值
      _resetToDefaults();
    }
    // 通知所有监听者UI已更新
    notifyListeners();
  }

  /// 更新用户个人资料（昵称和/或头像）到云端
  Future<void> updateUser(String newNickname, File? newAvatarFile) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // 安全检查

    // 显示更新状态
    _nickname = newNickname;
    notifyListeners();

    String? newAvatarUrl;

    // 1. 如果用户提供了新的头像文件，则上传它
    if (newAvatarFile != null) {
      try {
        final ref = FirebaseStorage.instance
            .ref('users/${user.uid}/avatars/avatar_${DateTime.now().millisecondsSinceEpoch}${p.basename(newAvatarFile.path)}');

        // 上传文件
        await ref.putFile(newAvatarFile);
        // 获取新头像的下载URL
        newAvatarUrl = await ref.getDownloadURL();
        _avatarUrl = newAvatarUrl;
      } catch (e) {
        print("上传新头像失败: $e");
        // 如果上传失败，可以选择是否中止更新或继续只更新昵称
      }
    }

    // 2. 准备要写入Firestore的数据
    final Map<String, dynamic> dataToUpdate = {
      'nickname': newNickname,
    };
    if (newAvatarUrl != null) {
      // 只有在成功上传新头像后，才更新URL字段
      dataToUpdate['avatarUrl'] = newAvatarUrl;
    }

    // 3. 将数据写入Firestore
    // 使用 .set(..., SetOptions(merge: true)) 是一个好习惯，
    // 它会在文档不存在时创建它，存在时则合并更新字段。
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set(dataToUpdate, SetOptions(merge: true));

    // 再次通知UI，确保头像是最新的
    notifyListeners();
  }

  /// 用户退出时，重置为默认信息
  void _resetToDefaults() {
    _nickname = "旅人";
    _avatarUrl = null;
    notifyListeners();
  }
}