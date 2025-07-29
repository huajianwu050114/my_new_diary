// file: lib/settings_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'diary_service.dart';
import 'export_service.dart';
import 'stop_words_page.dart'; // VVV 导入新页面 VVV
import 'package:file_picker/file_picker.dart';
import 'dart:convert'; // 导入 dart:convert
import 'dart:io'; // 导入 dart:io
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';




class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isExporting = false;
  double _progressValue = 0.0;
  String _progressText = '';

  bool _isReminderEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 22, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isReminderEnabled = prefs.getBool('reminder_enabled') ?? false;
      final hour = prefs.getInt('reminder_hour') ?? 22;
      final minute = prefs.getInt('reminder_minute') ?? 0;
      _reminderTime = TimeOfDay(hour: hour, minute: minute);
    });
  }

  Future<void> _handleReminderSwitch(bool value) async {
    // 如果是想关闭提醒，直接执行并返回
    if (!value) {
      setState(() => _isReminderEnabled = false);
      _saveSettings(false, _reminderTime);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('每日提醒已关闭')),
      );
      return;
    }

    // 如果是想开启提醒，则开始权限请求流程
    final status = await Permission.notification.request();

    if (!mounted) return; // 检查页面是否还存在

    if (status.isGranted) {
      // 1. 权限已授予：直接开启功能
      setState(() => _isReminderEnabled = true);
      _saveSettings(true, _reminderTime);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提醒已在 ${_reminderTime.format(context)} 开启'))
      );
    } else if (status.isPermanentlyDenied) {
      // 2. 权限被“永久拒绝”：弹出一个对话框，引导用户去设置
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('需要通知权限'),
          content: const Text('您之前已拒绝通知权限，请在系统设置中手动为本应用开启。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              // 点击后直接打开应用的设置页面
              onPressed: () {
                openAppSettings();
                Navigator.of(context).pop();
              },
              child: const Text('前往设置'),
            ),
          ],
        ),
      );
    } else {
      // 3. 其他拒绝情况（例如用户只拒绝了一次）：只显示一个提示
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('开启每日提醒需要授予通知权限。'))
      );
    }
  }


  Future<void> _runImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未选择任何文件。')));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导入失败，用户未登录。')));
      return;
    }

    setState(() {
      _isExporting = true;
      _progressValue = 0.0;
      _progressText = '正在准备导入...';
    });

    try {
      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();
      final List<dynamic> entryMaps = jsonDecode(jsonString);

      int importCount = 0;
      for (int i = 0; i < entryMaps.length; i++) {
        final map = entryMaps[i];

        setState(() {
          _progressValue = (i + 1) / entryMaps.length;
          _progressText = '正在处理: ${i + 1} / ${entryMaps.length}';
        });

        // 新的导入逻辑：
        // 1. 解码Base64图片
        // 2. 直接上传到Firebase Storage
        // 3. 用获取到的云端URL替换旧的图片数据
        final imagePayload = map['imagePaths'] as List? ?? [];
        final List<String> cloudImageUrls = [];

        for (final item in imagePayload) {
          // 简单检查一下是否是Base64数据
          if (item is String && !item.contains('/') && item.length > 256) {
            try {
              final imageBytes = base64Decode(item);
              // 直接上传二进制数据到Storage
              final ref = FirebaseStorage.instance.ref('users/${user.uid}/images/imported_${DateTime.now().millisecondsSinceEpoch}.jpg');
              await ref.putData(imageBytes);
              final downloadUrl = await ref.getDownloadURL();
              cloudImageUrls.add(downloadUrl);
            } catch (e) {
              print('解码或上传Base64图片失败: $e');
            }
          }
        }

        // 用新的云端URL列表更新map
        map['imagePaths'] = cloudImageUrls;

        // 4. 直接将处理好的map写入Firestore，绕开需要`File`对象的`addEntry`方法
        map['authorId'] = user.uid;
        map['date'] = Timestamp.fromDate(DateTime.parse(map['date']));
        map['creationTime'] = Timestamp.fromDate(DateTime.parse(map['creationTime']));

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('diaries')
            .add(map);

        importCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入完成！成功导入 $importCount 篇新日记。')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败，文件格式错误或已损坏: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _saveSettings(bool enabled, TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reminder_enabled', enabled);
    await prefs.setInt('reminder_hour', time.hour);
    await prefs.setInt('reminder_minute', time.minute);

    if (enabled) {
      await NotificationService().scheduleDailyReminder(time);
    } else {
      await NotificationService().cancelAllNotifications();
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
    );
    if (pickedTime != null && pickedTime != _reminderTime) {
      setState(() {
        _reminderTime = pickedTime;
      });
      if (_isReminderEnabled) {
        _saveSettings(true, pickedTime);
      }
    }
  }

  Future<void> _runExport(Future<String?> Function(ExportService) exportFunction) async {
    setState(() {
      _isExporting = true;
      _progressValue = 0.0; // 导出暂时简化，不显示具体进度
      _progressText = '正在准备导出...';
    });

    final diaryService = context.read<DiaryService>();

    // 从新的Stream方法获取一次数据用于导出
    final allEntries = await diaryService.getAllEntriesSortedStream().first;

    if (allEntries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有任何日记可以导出。')),
        );
      }
      setState(() => _isExporting = false);
      return;
    }

    final exportService = ExportService(allEntries);
    final String? resultMessage = await exportFunction(exportService);

    if (mounted) {
      setState(() => _isExporting = false);
      if (resultMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出操作成功！')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出操作已取消或失败。')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置与工具'),
      ),
      body: Stack(
        children: [
          ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('每日写作提醒'),
                subtitle: Text(_isReminderEnabled ? '已开启' : '已关闭'),
                trailing: Switch(
                  value: _isReminderEnabled,
                  onChanged: _handleReminderSwitch, // VVV 更新这一行 VVV
                ),
              ),
              if (_isReminderEnabled)
                ListTile(
                  leading: const SizedBox(),
                  title: const Text('提醒时间'),
                  subtitle: Text(_reminderTime.format(context)),
                  onTap: _pickTime,
                ),
              const Divider(),
              // VVV 在这里添加新列表项 VVV
              ListTile(
                leading: const Icon(Icons.block_flipped),
                title: const Text('词云停用词管理'),
                subtitle: const Text('自定义词云分析中需要忽略的词汇'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StopWordsPage()),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('导出为 PDF'),
                subtitle: const Text('将所有日记导出为一个可读的PDF文件。'),
                onTap: _isExporting ? null : () => _runExport((s) => s.exportToPdf()),
              ),
              ListTile(
                leading: const Icon(Icons.data_object),
                title: const Text('导出为 JSON'),
                subtitle: const Text('备份所有数据，用于恢复或迁移。'),
                onTap: _isExporting ? null : () => _runExport((s) => s.exportToJson()),
              ),
              ListTile(
                leading: const Icon(Icons.data_array, color: Colors.green),
                title: const Text('从 JSON 导入'),
                subtitle: const Text('从备份文件恢复日记数据。'),
                onTap: _isExporting ? null : _runImport, // VVV 绑定新的导入方法
              ),
            ],
          ),
          if (_isExporting)
            Container(
              color: Colors.black.withOpacity(0.6),
              child: Center(
                child: Card(
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('正在导出，请稍候...'),
                        const SizedBox(height: 20),
                        LinearProgressIndicator(
                          value: _progressValue,
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        const SizedBox(height: 12),
                        Text(_progressText, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}