// file: libs/notification_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:io';

class NotificationService {
  // 使用单例模式，确保App中只有一个通知服务实例
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 1. 初始化插件的平台特定设置
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings settings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _notificationsPlugin.initialize(settings);

    // 2. 初始化时区数据库
    tz.initializeTimeZones();
  }

  Future<void> showTestNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'daily_diary_reminder_channel', // 必须和定时提醒使用同一个 channel ID
      '日记提醒',
      channelDescription: '每日提醒用户写日记的通道',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

    // 使用 show 方法立即发送一个通知
    await _notificationsPlugin.show(
      1, // 使用一个和定时通知不同的ID，比如 1
      '这是一条测试通知',
      '如果你能看到这条消息，说明App的通知功能本身是正常的。',
      notificationDetails,
    );
  }

  Future<void> requestExactAlarmsPermission() async {
    // 仅在 Android 平台上执行
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
      _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestExactAlarmsPermission();
      }
    }
  }

  // 3. 核心方法：设置每日提醒
  Future<void> scheduleDailyReminder(TimeOfDay time) async {
    // 获取当前时区
    final String timeZoneName = tz.local.name;
    final tz.Location location = tz.getLocation(timeZoneName);

    // 计算下一次提醒的时间
    final now = tz.TZDateTime.now(location);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
        location, now.year, now.month, now.day, time.hour, time.minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    // 4. 配置通知的详细信息
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'daily_diary_reminder_channel', // Channel ID
      '日记提醒', // Channel Name
      channelDescription: '每日提醒用户写日记的通道',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails);

    // 5. 使用 `zonedSchedule` 来安排一个基于时区的、每日重复的通知
    await _notificationsPlugin.zonedSchedule(
      0, // 通知ID
      '写日记时间到！',
      '今天有什么新鲜事想记下来吗？',
      scheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // 关键：让它每天在这个时间重复
    );
  }

  Future<void> showWeatherNotification(String title, String body) async {
    // 使用一个不同的 Channel ID 和名称，以便用户可以单独控制
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'weather_report_channel',
      '生活助手播报',
      channelDescription: '每日播报天气和关怀提醒',
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''), // 允许通知内容换行显示
    );
    const NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

    // 使用一个不同的通知ID（比如 1），避免覆盖每日提醒的ID (0)
    await _notificationsPlugin.show(
      1,
      title,
      body,
      notificationDetails,
    );
  }



  // 6. 取消所有已安排的通知
  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }
}