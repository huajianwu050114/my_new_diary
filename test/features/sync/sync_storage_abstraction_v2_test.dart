import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/diary/application/ports/diary_image_store_v2.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';
import 'package:my_new_diary/features/diary/domain/repositories/diary_repository_v2.dart';
import 'package:my_new_diary/features/sync/application/diary_sync_service_v2.dart';
import 'package:my_new_diary/features/sync/data/android_saf_sync_storage_v2.dart';
import 'package:my_new_diary/features/sync/data/diary_sync_codec_v2.dart';
import 'package:my_new_diary/features/sync/domain/diary_sync_record_v2.dart';
import 'package:my_new_diary/features/sync/domain/sync_storage_v2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const codec = DiarySyncCodecV2();
  final now = DateTime.utc(2026, 10, 3);

  test('one sync service reconciles a path-free SAF-like storage', () async {
    final repository = _Repository();
    final storage = _MemorySyncStorage();
    final record = DiarySyncRecordV2(
      id: 'remote',
      body: '来自 SAF',
      entryDate: now,
      createdAt: now,
      updatedAt: now,
    );
    storage.entries['remote.json'] = Uint8List.fromList(
      utf8.encode(codec.encode(record)),
    );

    final result = await DiarySyncServiceV2(
      repository: repository,
      imageStore: _Images(),
    ).synchronize(storage);

    expect(result.imported, 1);
    expect(repository.entries['remote']?.body, '来自 SAF');
  });

  test(
    'unavailable persisted storage does not mutate local diary data',
    () async {
      final repository = _Repository()
        ..entries['local'] = DiaryEntryV2(
          id: 'local',
          body: 'safe',
          entryDate: now,
          createdAt: now,
          updatedAt: now,
        );
      final storage = _MemorySyncStorage()..available = false;

      await expectLater(
        DiarySyncServiceV2(
          repository: repository,
          imageStore: _Images(),
        ).synchronize(storage),
        throwsA(isA<SyncStorageUnavailableException>()),
      );
      expect(repository.saveCount, 0);
      expect(repository.entries['local']?.body, 'safe');
    },
  );

  test(
    'Android SAF backend passes content URI to channel, never to File',
    () async {
      const channel = MethodChannel('test/diary_sync_saf');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'isAvailable' => true,
              'listEntryFiles' => <String>['A.json'],
              'readEntry' => Uint8List.fromList(<int>[1, 2]),
              _ => false,
            };
          });
      const uri =
          'content://com.android.externalstorage.documents/tree/primary%3ADiary';
      final storage = AndroidSafSyncStorageV2(
        treeUri: uri,
        bridge: const AndroidSafBridgeV2(channel: channel),
      );

      expect(await storage.isAvailable(), isTrue);
      expect(await storage.listEntryFiles(), const ['A.json']);
      expect(await storage.readEntry('A.json'), <int>[1, 2]);
      expect(
        calls.every(
          (call) => (call.arguments as Map<Object?, Object?>)['treeUri'] == uri,
        ),
        isTrue,
      );
    },
  );

  test(
    'Android SAF backend rejects traversal before platform invocation',
    () async {
      const channel = MethodChannel('test/diary_sync_saf_traversal');
      var invocations = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            invocations++;
            return null;
          });
      final storage = AndroidSafSyncStorageV2(
        treeUri: 'content://provider/tree/root',
        bridge: const AndroidSafBridgeV2(channel: channel),
      );

      expect(() => storage.readEntry('../A.json'), throwsArgumentError);
      expect(
        () => storage.writeImageAtomic('file://secret', Uint8List(0)),
        throwsArgumentError,
      );
      expect(invocations, 0);
    },
  );
}

class _MemorySyncStorage implements SyncStorageV2 {
  bool available = true;
  final entries = <String, Uint8List>{};
  final images = <String, Uint8List>{};

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<String>> listEntryFiles() async => entries.keys.toList();

  @override
  Future<Uint8List?> readEntry(String fileName) async => entries[fileName];

  @override
  Future<Uint8List?> readImage(String imageId) async => images[imageId];

  @override
  Future<bool> writeEntryAtomic(String fileName, Uint8List bytes) async {
    entries[fileName] = bytes;
    return true;
  }

  @override
  Future<bool> writeImageAtomic(String imageId, Uint8List bytes) async {
    images[imageId] = bytes;
    return true;
  }
}

class _Repository implements DiaryRepositoryV2 {
  final entries = <String, DiaryEntryV2>{};
  int saveCount = 0;

  @override
  Future<DiaryEntryV2?> getById(String id) async => entries[id];

  @override
  Stream<List<DiaryEntryV2>> watchEntries({
    DiaryQuery query = const DiaryQuery(),
  }) async* {
    yield entries.values.toList();
  }

  @override
  Future<void> save(DiaryEntryV2 entry) async {
    saveCount++;
    entries[entry.id] = entry;
  }

  @override
  Future<void> restoreFromBackup(DiaryEntryV2 entry) => save(entry);

  @override
  Future<void> deletePermanently(String id) async => entries.remove(id);

  @override
  Future<void> moveToTrash(String id, {required DateTime deletedAt}) async {}

  @override
  Future<void> restore(String id) async {}

  @override
  Future<void> setFavorite(String id, {required bool isFavorite}) async {}
}

class _Images implements DiaryImageStoreV2, DiaryImageImportStoreV2 {
  @override
  Future<void> delete(String imageId) async {}

  @override
  Future<void> import({
    required String imageId,
    required Uint8List bytes,
  }) async {}

  @override
  Future<Uint8List?> read(String imageId) async => null;

  @override
  Future<String> save({
    required Uint8List bytes,
    required String extension,
  }) async => 'unused.$extension';
}
