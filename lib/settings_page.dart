// file: lib/settings_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'diary_service.dart';
import 'export_service.dart';
import 'stop_words_page.dart'; // VVV 导入新页面 VVV

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

  Future<void> _runExport(Future<String?> Function(ExportService, ExportProgressCallback) exportFunction) async {
    setState(() {
      _isExporting = true;
      _progressValue = 0.0;
      _progressText = '正在准备...';
    });
    final diaryService = context.read<DiaryService>();
    final allEntries = await diaryService.getAllEntriesSorted();

    if (allEntries.isEmpty) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有任何日记可以导出。')),
        );
      }
      setState(() => _isExporting = false);
      return;
    }

    final exportService = ExportService(allEntries);
    final onProgress = (int current, int total) {
      setState(() {
        _progressValue = current / total;
        _progressText = '正在处理: $current / $total';
      });
    };

    final String? savedPath = await exportFunction(exportService, onProgress);

    setState(() {
      _isExporting = false;
    });
    if (mounted) {
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出成功！已保存至: $savedPath')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出操作已取消。')),
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
                  onChanged: (value) {
                    setState(() {
                      _isReminderEnabled = value;
                    });
                    _saveSettings(value, _reminderTime);
                  },
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
                onTap: _isExporting ? null : () => _runExport((s, cb) => s.exportToPdf(onProgress: cb)),
              ),
              ListTile(
                leading: const Icon(Icons.data_object),
                title: const Text('导出为 JSON'),
                subtitle: const Text('备份所有数据，用于恢复或迁移。'),
                onTap: _isExporting ? null : () => _runExport((s, cb) => s.exportToJson(onProgress: cb)),
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