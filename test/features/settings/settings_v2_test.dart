import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_new_diary/features/settings/application/theme_controller_v2.dart';
import 'package:my_new_diary/features/settings/data/local_profile_store_v2.dart';
import 'package:my_new_diary/features/settings/data/privacy_settings_store_v2.dart';

void main() {
  test('theme choice is restored from local preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ThemeControllerV2();
    await first.setMode(ThemeMode.dark);

    final restored = ThemeControllerV2();
    await restored.load();

    expect(restored.mode, ThemeMode.dark);
  });

  test('nickname and avatar stay in local profile storage', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp(
      'diary_v2_profile_test_',
    );
    final store = LocalProfileStoreV2(profileDirectory: () async => directory);

    await store.saveNickname('Writer');
    await store.saveAvatar(Uint8List.fromList([1, 2, 3]));
    final profile = await store.load();

    expect(profile.nickname, 'Writer');
    expect(profile.avatarBytes, [1, 2, 3]);

    await store.removeAvatar();
    expect((await store.load()).avatarBytes, isNull);
    await directory.delete(recursive: true);
  });

  test('reminder time and app lock choice persist locally', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrivacySettingsStoreV2();

    await store.saveReminder(
      enabled: true,
      time: const TimeOfDay(hour: 21, minute: 35),
    );
    await store.saveAppLock(true);
    final restored = await store.load();

    expect(restored.reminderEnabled, isTrue);
    expect(restored.reminderTime, const TimeOfDay(hour: 21, minute: 35));
    expect(restored.appLockEnabled, isTrue);
  });
}
