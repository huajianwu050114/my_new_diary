// file: lib/settings_page.dart (最终修改版)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 导入我们需要的服务
import 'diary_service.dart';
import 'export_service_local.dart'; // 导入新的本地导出服务
import 'notification_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'stop_words_page.dart';
import 'theme_provider.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // 状态变量保持不变
  bool _isLoading = false;
  String _loadingText = '';
  bool _isReminderEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 22, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // --- 提醒功能的逻辑 (基本不变) ---
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
    if (!value) {
      setState(() => _isReminderEnabled = false);
      _saveSettings(false, _reminderTime);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('每日提醒已关闭')));
      return;
    }

    final status = await Permission.notification.request();
    if (!mounted) return;

    if (status.isGranted) {
      setState(() => _isReminderEnabled = true);
      _saveSettings(true, _reminderTime);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提醒已在 ${_reminderTime.format(context)} 开启')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('开启每日提醒需要授予通知权限。')));
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
    final TimeOfDay? pickedTime = await showTimePicker(context: context, initialTime: _reminderTime);
    if (pickedTime != null && pickedTime != _reminderTime) {
      setState(() => _reminderTime = pickedTime);
      if (_isReminderEnabled) {
        _saveSettings(true, pickedTime);
      }
    }
  }

  // --- 新增：本地导入导出逻辑 ---
  Future<void> _runLocalExport() async {
    setState(() {
      _isLoading = true;
      _loadingText = '正在准备备份文件...';
    });
    final exportService = ExportServiceLocal();
    try {
      await exportService.exportToZip(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _runLocalImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.single.path == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未选择任何文件。')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认导入'),
        content: const Text('导入备份将会覆盖所有当前的本地数据，此操作不可逆，确定要继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('确认', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirmed && mounted) {
      setState(() {
        _isLoading = true;
        _loadingText = '正在导入备份...';
      });
      final exportService = ExportServiceLocal();
      try {
        await exportService.importFromZip(context, result.files.single.path!);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导入成功！请重启App以加载新数据。')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    // 使用 Consumer 来获取 DiaryService 和 ThemeProvider 的当前状态
    return Consumer2<DiaryService, ThemeProvider>(
      builder: (context, diaryService, themeProvider, child) {
        // 检查用户是否已登录Firebase，只有登录后才能切换到云端模式
        final bool isLoggedIn = FirebaseAuth.instance.currentUser != null;

        return Scaffold(
          appBar: AppBar(
            title: const Text('设置与工具'),
          ),
          body: Stack(
            children: [
              ListView(
                children: [
                  // --- 1. 新增：数据模式切换 ---
                  ListTile(
                    leading: Icon(diaryService.currentMode == StorageMode.cloud ? Icons.cloud_queue : Icons.dns),
                    title: const Text('数据存储模式'),
                    subtitle: Text(diaryService.currentMode == StorageMode.cloud ? '云端同步 (Firebase)' : '纯本地存储'),
                    trailing: Switch(
                      value: diaryService.currentMode == StorageMode.cloud,
                      // 如果用户未登录，则禁用切换到云端模式的开关
                      onChanged: !isLoggedIn
                          ? null
                          : (isCloud) {
                        if (isCloud) {
                          diaryService.switchToCloudMode();
                        } else {
                          diaryService.switchToLocalMode();
                        }
                      },
                    ),
                  ),
                  if (!isLoggedIn)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 8.0),
                      child: Text('提示：登录后才能开启云端同步模式。', style: Theme.of(context).textTheme.bodySmall),
                    ),
                  const Divider(),

                  // --- 2. 新增：本地数据备份/恢复 ---
                  // 只有在本地模式下，才显示这些选项
                  if (diaryService.currentMode == StorageMode.local) ...[
                    ListTile(
                      leading: const Icon(Icons.upload_file_outlined),
                      title: const Text('导出本地数据'),
                      subtitle: const Text('将所有本地日记打包成 .zip 文件'),
                      onTap: _isLoading ? null : _runLocalExport,
                    ),
                    ListTile(
                      leading: const Icon(Icons.download_for_offline_outlined),
                      title: const Text('从本地备份导入'),
                      subtitle: const Text('从 .zip 文件恢复数据（将覆盖现有）'),
                      onTap: _isLoading ? null : _runLocalImport,
                    ),
                    const Divider(),
                  ],

                  // --- 3. 原有的功能保持不变 ---
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('每日写作提醒'),
                    subtitle: Text(_isReminderEnabled ? '已开启' : '已关闭'),
                    trailing: Switch(
                      value: _isReminderEnabled,
                      onChanged: _handleReminderSwitch,
                    ),
                  ),
                  if (_isReminderEnabled)
                    ListTile(
                      leading: const SizedBox(width: 56), // 用于对齐
                      title: const Text('提醒时间'),
                      subtitle: Text(_reminderTime.format(context)),
                      onTap: _pickTime,
                    ),
                  const Divider(),
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
                ],
              ),
              // 加载中的遮罩层
              if (_isLoading)
                Container(
                  color: Colors.black.withOpacity(0.5),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_loadingText, style: const TextStyle(color: Colors.white, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}