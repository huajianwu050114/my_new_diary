import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/sync/data/android_saf_sync_storage_v2.dart';
import 'package:my_new_diary/features/sync/data/sync_directory_provider_v2.dart';
import 'package:my_new_diary/features/sync/domain/sync_location_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'Android picker persists tree URI kind and friendly display name',
    () async {
      const channel = MethodChannel('test/saf_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'pickTree') {
              return <String, Object?>{
                'treeUri': 'content://provider/tree/DiarySync',
                'displayName': 'Syncthing / DiarySync',
              };
            }
            if (call.method == 'isAvailable') return true;
            return null;
          });
      final provider = SyncDirectoryProviderV2(
        androidBridge: const AndroidSafBridgeV2(channel: channel),
        platform: () => TargetPlatform.android,
      );

      final picked = await provider.pickLocation();
      expect(picked?.kind, SyncLocationKindV2.androidSafTree);
      expect(picked?.value, startsWith('content://'));
      await provider.select(picked!);

      final afterColdStart = await SyncDirectoryProviderV2(
        androidBridge: const AndroidSafBridgeV2(channel: channel),
        platform: () => TargetPlatform.android,
      ).load();
      expect(afterColdStart.location?.kind, SyncLocationKindV2.androidSafTree);
      expect(afterColdStart.displayName, 'Syncthing / DiarySync');
      expect(
        await provider.storageFor(afterColdStart.location!).isAvailable(),
        isTrue,
      );
    },
  );

  test(
    'legacy filesystem setting remains readable without becoming SAF URI',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'diary_sync_selected_path_v2': r'D:\DiarySync',
      });
      final settings = await SyncDirectoryProviderV2(
        platform: () => TargetPlatform.windows,
      ).load();
      expect(settings.location?.kind, SyncLocationKindV2.filesystem);
      expect(settings.location?.value, r'D:\DiarySync');
    },
  );
}
