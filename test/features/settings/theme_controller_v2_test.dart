import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/settings/application/theme_controller_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('保存并恢复明暗模式与配色主题', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = ThemeControllerV2();

    await controller.setMode(ThemeMode.dark);
    await controller.setPalette(AppPaletteV2.moss);

    final restored = ThemeControllerV2();
    await restored.load();
    expect(restored.mode, ThemeMode.dark);
    expect(restored.palette, AppPaletteV2.moss);
  });

  test('未知或缺失的配色值安全回到暮紫', () async {
    SharedPreferences.setMockInitialValues({
      'v2_color_palette': 'removed-theme',
    });
    final controller = ThemeControllerV2();
    await controller.load();
    expect(controller.palette, AppPaletteV2.twilight);
  });
}
