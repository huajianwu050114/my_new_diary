import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../ai/presentation/ai_settings_page_v2.dart';
import '../../diary/application/legacy_migration_controller_v2.dart';
import '../../diary/presentation/pages/legacy_migration_page_v2.dart';
import '../../sync/application/diary_sync_controller_v2.dart';
import '../application/theme_controller_v2.dart';
import '../application/app_lock_controller_v2.dart';
import '../application/reminder_service_v2.dart';
import '../data/local_profile_store_v2.dart';
import '../data/privacy_settings_store_v2.dart';

class SettingsPageV2 extends StatefulWidget {
  const SettingsPageV2({
    required this.themeController,
    required this.profileStore,
    required this.privacySettingsStore,
    required this.reminderService,
    required this.appLockController,
    this.migrationController,
    this.syncController,
    super.key,
  });

  final ThemeControllerV2 themeController;
  final LocalProfileStoreV2 profileStore;
  final PrivacySettingsStoreV2 privacySettingsStore;
  final ReminderServiceV2 reminderService;
  final AppLockControllerV2 appLockController;
  final LegacyMigrationControllerV2? migrationController;
  final DiarySyncControllerV2? syncController;

  @override
  State<SettingsPageV2> createState() => _SettingsPageV2State();
}

class _SettingsPageV2State extends State<SettingsPageV2> {
  LocalProfileV2? _profile;
  PrivacySettingsV2? _privacySettings;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadPrivacySettings();
  }

  Future<void> _loadPrivacySettings() async {
    final settings = await widget.privacySettingsStore.load();
    if (mounted) {
      setState(() => _privacySettings = settings);
    }
  }

  Future<void> _loadProfile() async {
    final profile = await widget.profileStore.load();
    if (mounted) {
      setState(() => _profile = profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        _Avatar(bytes: profile.avatarBytes),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.nickname,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              const Text('资料仅保存在当前设备'),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '编辑资料',
                          onPressed: _editProfile,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('外观', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                AnimatedBuilder(
                  animation: widget.themeController,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        child: Column(
                          children: ThemeMode.values
                              .map((mode) {
                                return RadioListTile<ThemeMode>(
                                  value: mode,
                                  groupValue: widget.themeController.mode,
                                  title: Text(_themeName(mode)),
                                  secondary: Icon(_themeIcon(mode)),
                                  onChanged: (value) {
                                    if (value != null) {
                                      widget.themeController.setMode(value);
                                    }
                                  },
                                );
                              })
                              .toList(growable: false),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('提醒与隐私', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.notifications_outlined),
                        title: const Text('每日写日记提醒'),
                        subtitle: Text(
                          _privacySettings == null
                              ? '正在读取…'
                              : _privacySettings!.reminderTime.format(context),
                        ),
                        value: _privacySettings?.reminderEnabled ?? false,
                        onChanged: _privacySettings == null
                            ? null
                            : _setReminderEnabled,
                      ),
                      ListTile(
                        leading: const Icon(Icons.schedule),
                        title: const Text('提醒时间'),
                        enabled: _privacySettings?.reminderEnabled == true,
                        onTap: _privacySettings?.reminderEnabled == true
                            ? _pickReminderTime
                            : null,
                      ),
                      AnimatedBuilder(
                        animation: widget.appLockController,
                        builder: (context, _) => SwitchListTile(
                          secondary: const Icon(Icons.fingerprint),
                          title: const Text('应用锁'),
                          subtitle: const Text('使用生物识别或系统凭据解锁'),
                          value: widget.appLockController.enabled,
                          onChanged: _setAppLock,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('智能功能', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('AI 总结与伴聊'),
                    subtitle: const Text('配置服务商、API Key 和模型'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AiSettingsPageV2(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (widget.syncController != null) ...[
                  Text('设备同步', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _SyncSettingsCard(controller: widget.syncController!),
                  const SizedBox(height: 24),
                ],
                Text('关于数据', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.cloud_off_outlined),
                        title: Text('本地优先'),
                        subtitle: Text('v2 不需要登录，日记和个人资料默认不会上传。'),
                      ),
                      if (widget.migrationController != null)
                        ListTile(
                          leading: const Icon(Icons.move_to_inbox_outlined),
                          title: const Text('旧版数据迁移'),
                          subtitle: AnimatedBuilder(
                            animation: widget.migrationController!,
                            builder: (context, _) => Text(
                              _migrationStatus(widget.migrationController!),
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LegacyMigrationPageV2(
                                controller: widget.migrationController!,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  String _migrationStatus(LegacyMigrationControllerV2 controller) {
    if (controller.running) return '正在扫描旧版数据…';
    final report = controller.lastRun?.report;
    if (report == null) return '尚未扫描';
    return '最近发现 ${report.discovered} 项，导入 ${report.imported} 项，'
        '失败 ${report.failed} 项';
  }

  Future<void> _setReminderEnabled(bool enabled) async {
    final current = _privacySettings!;
    if (enabled) {
      final result = await widget.reminderService.scheduleDaily(
        current.reminderTime,
      );
      if (result != ReminderScheduleResultV2.scheduled) {
        await _handleReminderFailure(result);
        return;
      }
    } else {
      await widget.reminderService.cancelDaily();
    }
    await widget.privacySettingsStore.saveReminder(
      enabled: enabled,
      time: current.reminderTime,
    );
    await _loadPrivacySettings();
  }

  Future<void> _pickReminderTime() async {
    final current = _privacySettings!;
    final picked = await showTimePicker(
      context: context,
      initialTime: current.reminderTime,
    );
    if (picked == null) {
      return;
    }
    final result = await widget.reminderService.scheduleDaily(picked);
    if (result != ReminderScheduleResultV2.scheduled) {
      await _handleReminderFailure(result);
      return;
    }
    await widget.privacySettingsStore.saveReminder(enabled: true, time: picked);
    await _loadPrivacySettings();
  }

  Future<void> _handleReminderFailure(ReminderScheduleResultV2 result) async {
    if (!mounted) return;
    if (result == ReminderScheduleResultV2.unavailable) {
      _message('提醒登记失败，请稍后重试');
      return;
    }
    final description = result == ReminderScheduleResultV2.permissionDenied
        ? '通知权限尚未授予。你可以前往系统设置，为时光日记 V2 开启通知。'
        : '系统当前关闭了时光日记 V2 的通知。开启后返回，再重新打开每日提醒。';
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要开启通知'),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('去系统设置'),
          ),
        ],
      ),
    );
    if (openSettings == true) {
      final opened = await widget.reminderService.openNotificationSettings();
      if (!opened && mounted) _message('无法自动打开设置，请在系统设置中找到应用通知');
    }
  }

  Future<void> _setAppLock(bool enabled) async {
    final success = await widget.appLockController.setEnabled(enabled);
    if (!success) {
      _message('当前设备未配置可用的生物识别或系统凭据');
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _editProfile() async {
    final controller = TextEditingController(text: _profile!.nickname);
    Uint8List? selectedAvatar = _profile!.avatarBytes;
    var removeAvatar = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('编辑资料'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final image = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 88,
                  );
                  if (image != null) {
                    final bytes = await image.readAsBytes();
                    setDialogState(() {
                      selectedAvatar = bytes;
                      removeAvatar = false;
                    });
                  }
                },
                child: _Avatar(bytes: selectedAvatar),
              ),
              if (selectedAvatar != null)
                TextButton(
                  onPressed: () => setDialogState(() {
                    selectedAvatar = null;
                    removeAvatar = true;
                  }),
                  child: const Text('移除头像'),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: '昵称'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final nickname = controller.text.trim();
      if (nickname.isNotEmpty) {
        await widget.profileStore.saveNickname(nickname);
      }
      if (removeAvatar) {
        await widget.profileStore.removeAvatar();
      } else if (selectedAvatar != null &&
          selectedAvatar != _profile!.avatarBytes) {
        await widget.profileStore.saveAvatar(selectedAvatar!);
      }
      await _loadProfile();
    }
    controller.dispose();
  }

  String _themeName(ThemeMode mode) => switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };

  IconData _themeIcon(ThemeMode mode) => switch (mode) {
    ThemeMode.system => Icons.brightness_auto_outlined,
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
  };
}

class _SyncSettingsCard extends StatelessWidget {
  const _SyncSettingsCard({required this.controller});

  final DiarySyncControllerV2 controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final settings = controller.settings;
        final result = controller.lastResult;
        final lastSync = settings.lastSuccessfulSync;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '此功能通过你自行安装的 Syncthing 在设备间同步日记文件。'
                  'App 本身不会上传到云服务器。',
                ),
                const SizedBox(height: 12),
                Text(
                  settings.enabled
                      ? '同步文件夹：\n${settings.displayName}'
                      : 'Syncthing 文件夹\n当前：未设置',
                ),
                if (controller.requiresReauthorization) ...[
                  const SizedBox(height: 8),
                  Text(
                    '同步文件夹需要重新授权',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (lastSync != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '上次同步：${DateFormat('yyyy-MM-dd HH:mm').format(lastSync)}',
                  ),
                ],
                if (result != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '结果：导入 ${result.imported}，导出 ${result.exported}，'
                    '更新 ${result.updated}，图片 ${result.imageCount}，'
                    '错误 ${result.errors.length}',
                  ),
                ],
                if (controller.lastError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '同步失败：${controller.lastError.runtimeType}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: controller.running
                          ? null
                          : () => _selectFolder(context),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('选择文件夹'),
                    ),
                    FilledButton.icon(
                      onPressed: !settings.enabled || controller.running
                          ? null
                          : () => _sync(context),
                      icon: controller.running
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(controller.running ? '同步中…' : '立即同步'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _selectFolder(BuildContext context) async {
    try {
      await controller.selectFolder();
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _sync(BuildContext context) async {
    try {
      await controller.synchronize();
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('同步失败：${error.runtimeType}')));
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 34,
      backgroundImage: bytes == null ? null : MemoryImage(bytes!),
      child: bytes == null ? const Icon(Icons.person_outline, size: 32) : null,
    );
  }
}
