// file: lib/edit_profile_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'user_provider.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late TextEditingController _nameController;
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    // 初始化时，仅用当前用户信息填充文本输入框
    final userProvider = context.read<UserProvider>();
    _nameController = TextEditingController(text: userProvider.nickname);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 使用 image_picker 从相册选择新头像
  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  /// 保存个人资料，调用 UserProvider 的更新方法
  void _saveProfile() {
    // 调用 UserProvider 的更新方法，直接传递新的昵称和新的 File 对象
    context.read<UserProvider>().updateUser(
      _nameController.text.trim(),
      _imageFile,
    );
    // 保存后返回上一页
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // 在 build 方法中使用 watch 来获取 provider，这样当头像URL变化时UI可以自动更新
    final userProvider = context.watch<UserProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑个人资料'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt_outlined),
            tooltip: '保存',
            onPressed: _saveProfile,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 60,
                // --- 核心逻辑 ---
                // 这个 backgroundImage 会智能地处理三种情况：
                backgroundImage: _imageFile != null
                    ? FileImage(_imageFile!) // 1. 如果用户新选择了一张本地图片，优先显示它
                    : (userProvider.avatarUrl != null
                    ? NetworkImage(userProvider.avatarUrl!) // 2. 否则，如果云端有头像URL，就显示网络图片
                    : null), // 3. 如果都没有，则不显示背景图片
                child: (_imageFile == null && userProvider.avatarUrl == null)
                    ? const Icon(Icons.add_a_photo, // 只有在既没有本地预览图也没有云端图时，才显示图标
                    size: 50)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '昵称',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
        ],
      ),
    );
  }
}