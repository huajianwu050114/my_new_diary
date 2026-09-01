import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrivacySettingsStoreV2 {
  static const _reminderEnabledKey = 'v2_reminder_enabled';
  static const _reminderHourKey = 'v2_reminder_hour';
  static const _reminderMinuteKey = 'v2_reminder_minute';
  static const _appLockKey = 'v2_app_lock_enabled';

  Future<PrivacySettingsV2> load() async {
    final preferences = await SharedPreferences.getInstance();
    return PrivacySettingsV2(
      reminderEnabled: preferences.getBool(_reminderEnabledKey) ?? false,
      reminderTime: TimeOfDay(
        hour: preferences.getInt(_reminderHourKey) ?? 22,
        minute: preferences.getInt(_reminderMinuteKey) ?? 0,
      ),
      appLockEnabled: preferences.getBool(_appLockKey) ?? false,
    );
  }

  Future<void> saveReminder({
    required bool enabled,
    required TimeOfDay time,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_reminderEnabledKey, enabled);
    await preferences.setInt(_reminderHourKey, time.hour);
    await preferences.setInt(_reminderMinuteKey, time.minute);
  }

  Future<void> saveAppLock(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_appLockKey, enabled);
  }
}

class PrivacySettingsV2 {
  const PrivacySettingsV2({
    required this.reminderEnabled,
    required this.reminderTime,
    required this.appLockEnabled,
  });

  final bool reminderEnabled;
  final TimeOfDay reminderTime;
  final bool appLockEnabled;
}
