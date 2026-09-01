import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

enum ReminderScheduleResultV2 {
  scheduled,
  notificationsDisabled,
  permissionDenied,
  unavailable,
}

enum ReminderPermissionActionV2 {
  proceed,
  requestRuntimePermission,
  openSystemSettings,
}

ReminderPermissionActionV2 reminderPermissionActionV2({
  required int? androidSdk,
  required bool notificationsEnabled,
}) {
  if (notificationsEnabled) return ReminderPermissionActionV2.proceed;
  if (androidSdk != null && androidSdk >= 33) {
    return ReminderPermissionActionV2.requestRuntimePermission;
  }
  return ReminderPermissionActionV2.openSystemSettings;
}

abstract interface class ReminderPlatformV2 {
  Future<int?> androidSdkInt();

  Future<bool> openNotificationSettings();
}

class MethodChannelReminderPlatformV2 implements ReminderPlatformV2 {
  const MethodChannelReminderPlatformV2();

  static const _channel = MethodChannel(
    'com.huajianwu.shiguangdiary.v2/device_settings',
  );

  @override
  Future<int?> androidSdkInt() => _channel.invokeMethod<int>('androidSdkInt');

  @override
  Future<bool> openNotificationSettings() async =>
      await _channel.invokeMethod<bool>('openNotificationSettings') ?? false;
}

class ReminderServiceV2 {
  ReminderServiceV2({
    FlutterLocalNotificationsPlugin? plugin,
    ReminderPlatformV2 platform = const MethodChannelReminderPlatformV2(),
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _platform = platform;

  final FlutterLocalNotificationsPlugin _plugin;
  final ReminderPlatformV2 _platform;
  bool _initialized = false;

  Future<bool> initialize() async {
    try {
      timezone_data.initializeTimeZones();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
      );
      _initialized = await _plugin.initialize(settings) ?? false;
      return _initialized;
    } on Exception {
      _initialized = false;
      return false;
    }
  }

  Future<ReminderScheduleResultV2> scheduleDaily(TimeOfDay time) async {
    if (!_initialized && !await initialize()) {
      return ReminderScheduleResultV2.unavailable;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final enabledBefore = await android.areNotificationsEnabled() ?? false;
      if (!enabledBefore) {
        final sdk = await _safeAndroidSdkInt();
        final action = reminderPermissionActionV2(
          androidSdk: sdk,
          notificationsEnabled: enabledBefore,
        );
        if (action == ReminderPermissionActionV2.requestRuntimePermission) {
          final granted = await android.requestNotificationsPermission();
          if (granted != true) {
            return ReminderScheduleResultV2.permissionDenied;
          }
        } else {
          return ReminderScheduleResultV2.notificationsDisabled;
        }
      }
      final enabledAfter = await android.areNotificationsEnabled() ?? false;
      if (!enabledAfter) {
        return ReminderScheduleResultV2.notificationsDisabled;
      }
    }

    try {
      final now = DateTime.now();
      var localTarget = DateTime(
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      );
      if (!localTarget.isAfter(now)) {
        localTarget = localTarget.add(const Duration(days: 1));
      }
      final target = timezone.TZDateTime.from(
        localTarget.toUtc(),
        timezone.UTC,
      );
      await _plugin.zonedSchedule(
        1001,
        '写日记时间到',
        '今天有什么值得记下来的事？',
        target,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'v2_daily_diary_reminder',
            '日记提醒',
            channelDescription: '每天提醒写日记',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return ReminderScheduleResultV2.scheduled;
    } on Exception {
      return ReminderScheduleResultV2.unavailable;
    }
  }

  Future<int?> _safeAndroidSdkInt() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _platform.androidSdkInt();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> openNotificationSettings() async {
    try {
      return await _platform.openNotificationSettings();
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> cancelDaily() => _plugin.cancel(1001);
}
