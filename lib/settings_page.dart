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
import 'package:archive/archive_io.dart';
import 'dart:typed_data';
import 'package:my_new_diary/diary_model.dart';
import 'package:my_new_diary/migration_service.dart';
import 'theme_options.dart';
import 'themes.dart';
import 'theme_provider.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isExporting = false;
  double _progressValue = 0.0;
  String _progressText = '';

  bool _isMigrating = false;
  bool _migrationDone = false;
  String _migrationProgressText = '';

  bool _isReminderEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 22, minute: 0);
  bool _isWeatherAssistantEnabled = false;
  final String weatherTaskName = "daily-weather-report";
  final String weatherTestTaskName = "test-weather-report";

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkMigrationStatus();
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

  Future<void> _checkMigrationStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _migrationDone = prefs.getBool('migration_v2_done') ?? false;
    });
  }

  // VVV 4. 添加执行迁移的方法
  Future<void> _runMigration() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('数据迁移'),
        content: const Text('这将把您所有的旧文件日记导入到新数据库中。这是一个一次性操作，是否现在开始？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('开始迁移')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isMigrating = true;
      _migrationProgressText = '正在查找旧文件...';
    });

    try {
      final migrationService = MigrationService();
      final diaryService = context.read<DiaryService>();
      final oldEntries = await migrationService.getAllFileEntries();

      if (oldEntries.isEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有找到任何旧的日记文件。')));
      } else {
        for (int i = 0; i < oldEntries.length; i++) {
          final oldEntry = oldEntries[i];
          setState(() {
            _migrationProgressText = '正在迁移: ${i + 1} / ${oldEntries.length}';
          });
          await diaryService.addEntry(oldEntry.toNewDiaryEntry());
          await Future.delayed(const Duration(milliseconds: 10)); // 避免UI卡顿
        }
      }

      // 标记迁移已完成
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('migration_v2_done', true);
      setState(() => _migrationDone = true);

      if(mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('迁移完成'),
            content: Text('成功迁移 ${oldEntries.length} 篇日记到新数据库！'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('好的')),
            ],
          ),
        );
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('迁移失败: $e')));
    } finally {
      setState(() => _isMigrating = false);
    }
  }


  // 文件位置: lib/settings_page.dart -> _SettingsPageState class

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

    // VVVV  核心修改区域 VVVV
    final notificationService = NotificationService(); // 获取 NotificationService 实例

    // 1. 先请求普通通知权限
    final status = await Permission.notification.request();
    if (!mounted) return;

    if (status.isGranted) {
      // 2. 如果普通权限通过，再请求精确闹钟权限
      // 注意：这里的 requestExactAlarmsPermission 是 flutter_local_notifications 插件提供的
      await notificationService.requestExactAlarmsPermission();

      // 3. 开启功能并保存设置
      setState(() => _isReminderEnabled = true);
      _saveSettings(true, _reminderTime);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提醒已在 ${_reminderTime.format(context)} 开启'))
      );
    } else if (status.isPermanentlyDenied) {
      // ... (原有的永久拒绝逻辑保持不变)
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('需要通知权限'),
          content: const Text('您之前已拒绝通知权限，请在系统设置中手动为本应用开启。'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            TextButton(onPressed: () { openAppSettings(); Navigator.of(context).pop(); }, child: const Text('前往设置')),
          ],
        ),
      );
    } else {
      // ... (原有的普通拒绝逻辑保持不变)
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('开启每日提醒需要授予通知权限。'))
      );
    }
    // ^^^^ 修改结束 ^^^^
  }


  // 文件位置: lib/settings_page.dart -> _SettingsPageState class

  Future<void> _runImportFromZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.single.path == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未选择任何文件。')));
      return;
    }

    final diaryService = context.read<DiaryService>();
    setState(() {
      _isExporting = true;
      _progressValue = 0.0;
      _progressText = '正在解压备份文件...';
    });

    try {
      final path = result.files.single.path!;
      final bytes = await File(path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final jsonFile = archive.findFile('backup.json');
      if (jsonFile == null) throw Exception('备份文件中未找到 backup.json');

      final jsonString = utf8.decode(jsonFile.content as List<int>);
      final List<dynamic> entryMaps = jsonDecode(jsonString);

      int importCount = 0;
      for (int i = 0; i < entryMaps.length; i++) {
        final map = entryMaps[i] as Map<String, dynamic>;
        setState(() {
          _progressValue = (i + 1) / entryMaps.length;
          _progressText = '正在导入日记: ${i + 1} / ${entryMaps.length}';
        });

        // VVVV Bug修复 #3: 正确处理图片路径的恢复逻辑 VVVV

        // 1. 从map中解码出相对路径列表
        final relativeImagePaths = (jsonDecode(map['imagePaths']) as List).cast<String>();
        final newAbsoluteImagePaths = <String>[];

        // 2. 在压缩包中寻找图片并保存到本地，获取新的绝对路径
        for (final relativePath in relativeImagePaths) {
          final imageFile = archive.findFile(relativePath);
          if (imageFile != null) {
            final imageBytes = imageFile.content as Uint8List;
            final newPath = await diaryService.saveImageFromBytes(imageBytes);
            newAbsoluteImagePaths.add(newPath);
          }
        }

        // 3. 创建一个新的map，用新的绝对路径列表（并重新编码为JSON字符串）替换旧的相对路径
        final mapForImport = Map<String, dynamic>.from(map);
        mapForImport['imagePaths'] = jsonEncode(newAbsoluteImagePaths);

        // 4. 使用这个修正后的map来创建日记对象
        final newEntry = DiaryEntry.fromMap(mapForImport);
        await diaryService.addEntry(newEntry);
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
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    } finally {
      setState(() => _isExporting = false);
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

  Future<void> _runExport() async {
    setState(() {
      _isExporting = true;
      _progressValue = 0.0;
      _progressText = '正在准备...';
    });
    final diaryService = context.read<DiaryService>();
    final allEntries = await diaryService.getAllEntriesSorted();

    if (allEntries.isEmpty) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有任何日记可以导出。')));
      setState(() => _isExporting = false);
      return;
    }

    final exportService = ExportService(allEntries);
    final onProgress = (int current, int total) {
      setState(() {
        _progressValue = current / total;
        _progressText = '正在打包: $current / $total';
      });
    };

    final String? resultMessage = await exportService.exportToZip(onProgress: onProgress);

    setState(() => _isExporting = false);
    if (mounted) {
      if (resultMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resultMessage)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导出操作已取消或失败。')));
      }
    }
  }

  Duration _calculateInitialDelay(TimeOfDay targetTime) {
    final now = DateTime.now();
    DateTime firstRun = DateTime(now.year, now.month, now.day, targetTime.hour, targetTime.minute);
    if (firstRun.isBefore(now)) {
      firstRun = firstRun.add(const Duration(days: 1));
    }
    return firstRun.difference(now);
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
              if (!_migrationDone) // 仅在未完成迁移时显示
                ListTile(
                  leading: Icon(Icons.upgrade_rounded, color: Theme.of(context).colorScheme.primary),
                  title: const Text('迁移旧数据到数据库'),
                  subtitle: const Text('（重要）请在首次升级后执行此操作'),
                  onTap: _isMigrating ? null : _runMigration,
                ),
              if (!_migrationDone) const Divider(),

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

              const Divider(),
              ListTile(
                leading: const Icon(Icons.color_lens_outlined),
                title: const Text('主题与外观'),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (context) => const ThemeSelectionSheet(),
                  );
                },
              ),
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
                leading: const Icon(Icons.archive_outlined),
                title: const Text('备份为 ZIP'),
                subtitle: const Text('将所有日记和图片打包备份。'),
                onTap: _isExporting ? null : _runExport,
              ),
              ListTile(
                leading: const Icon(Icons.unarchive_outlined, color: Colors.green),
                title: const Text('从 ZIP 导入'),
                subtitle: const Text('从备份文件恢复日记数据。'),
                onTap: _isExporting ? null : _runImportFromZip,
              ),
            ],
          ),
          if (_isMigrating)
            Container(
              color: Colors.black.withOpacity(0.6),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        Text(_migrationProgressText),
                      ],
                    ),
                  ),
                ),
              ),
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
class ThemeSelectionSheet extends StatelessWidget {
  const ThemeSelectionSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, provider, child) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              // --- 主题模式选择 ---
              Text('主题模式', style: Theme.of(context).textTheme.titleLarge),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: Text('日间')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('夜间')),
                  ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                ],
                selected: {provider.themeMode},
                onSelectionChanged: (newSelection) {
                  provider.setThemeMode(newSelection.first);
                },
              ),
              const SizedBox(height: 24),

              // --- 浅色主题选择 ---
              Text('日间模式主题', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: provider.availableLightThemes.map((theme) {
                  final isSelected = provider.lightTheme.name == theme.name;
                  return GestureDetector(
                    onTap: () => provider.setLightTheme(theme),
                    child: Column(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: theme.seedColor,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 3)
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(theme.name, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // --- 深色主题选择 ---
              Text('夜间模式主题', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: provider.availableDarkThemes.map((theme) {
                  final isSelected = provider.darkTheme.name == theme.name;
                  return GestureDetector(
                    onTap: () => provider.setDarkTheme(theme),
                    child: Column(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: theme.seedColor,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 3)
                                : null,
                          ),
                          child: isSelected
                              ? Icon(Icons.check, color: Theme.of(context).colorScheme.onPrimary)
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(theme.name, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}