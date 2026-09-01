import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/settings/application/reminder_service_v2.dart';

void main() {
  test('Android 13+ 在通知未开启时申请运行时权限', () {
    expect(
      reminderPermissionActionV2(androidSdk: 33, notificationsEnabled: false),
      ReminderPermissionActionV2.requestRuntimePermission,
    );
  });

  test('Android 12 及以下通知关闭时引导系统设置', () {
    expect(
      reminderPermissionActionV2(androidSdk: 31, notificationsEnabled: false),
      ReminderPermissionActionV2.openSystemSettings,
    );
  });

  test('通知已经开启时直接登记提醒', () {
    expect(
      reminderPermissionActionV2(androidSdk: 31, notificationsEnabled: true),
      ReminderPermissionActionV2.proceed,
    );
  });
}
