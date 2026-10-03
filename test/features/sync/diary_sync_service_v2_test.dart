import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/diary/application/ports/diary_image_store_v2.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';
import 'package:my_new_diary/features/diary/domain/repositories/diary_repository_v2.dart';
import 'package:my_new_diary/features/sync/application/diary_sync_service_v2.dart';
import 'package:my_new_diary/features/sync/data/diary_sync_codec_v2.dart';
import 'package:my_new_diary/features/sync/data/file_diary_sync_store_v2.dart';
import 'package:my_new_diary/features/sync/domain/diary_sync_record_v2.dart';

void main() {
  const codec = DiarySyncCodecV2();
  final t1 = DateTime.utc(2026, 10, 2, 12);
  final t2 = DateTime.utc(2026, 10, 2, 13);
  late Directory root;
  late _MemoryRepository repository;
  late _MemoryImageStore images;
  late DiarySyncServiceV2 service;

  DiaryEntryV2 entry(
    String id,
    DateTime updatedAt, {
    String body = 'body',
    List<String> imageIds = const [],
    DateTime? deletedAt,
  }) {
    return DiaryEntryV2(
      id: id,
      body: body,
      entryDate: t1,
      createdAt: t1,
      updatedAt: updatedAt,
      imageIds: imageIds,
      deletedAt: deletedAt,
    );
  }

  Future<void> writeRemote(DiarySyncRecordV2 record) async {
    await FileDiarySyncStoreV2(root).writeEntryAtomic(
      '${record.id}.json',
      Uint8List.fromList(utf8.encode(codec.encode(record))),
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('diary-sync-');
    repository = _MemoryRepository();
    images = _MemoryImageStore();
    service = DiarySyncServiceV2(repository: repository, imageStore: images);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'first sync reconciles local-only, remote-only and remote-newer',
    () async {
      repository.entries['A'] = entry('A', t1);
      repository.entries['B'] = entry('B', t1, body: 'old');
      await writeRemote(
        DiarySyncRecordV2.fromEntry(entry('B', t2, body: 'new')),
      );
      await writeRemote(DiarySyncRecordV2.fromEntry(entry('C', t1)));

      final result = await service.synchronize(FileDiarySyncStoreV2(root));

      expect(result.exported, 1);
      expect(result.imported, 1);
      expect(result.updated, 1);
      expect(repository.entries['B']?.body, 'new');
      expect(repository.entries, contains('C'));
      final store = FileDiarySyncStoreV2(root);
      expect(
        await File(
          '${store.entriesDirectory.path}${Platform.pathSeparator}A.json',
        ).exists(),
        isTrue,
      );
    },
  );

  test('local newer wins and repeated scans are idempotent', () async {
    repository.entries['A'] = entry('A', t2, body: 'local');
    await writeRemote(
      DiarySyncRecordV2.fromEntry(entry('A', t1, body: 'remote')),
    );
    await service.synchronize(FileDiarySyncStoreV2(root));
    final savesAfterFirst = repository.saveCount;
    for (var index = 0; index < 10; index++) {
      final result = await service.synchronize(FileDiarySyncStoreV2(root));
      expect(result.updated, 0);
    }
    expect(repository.saveCount, savesAfterFirst);
    expect(repository.entries['A']?.updatedAt, t2);
  });

  test(
    'equal timestamps use deterministic content digest and converge',
    () async {
      repository.entries['A'] = entry('A', t1, body: 'left');
      await writeRemote(
        DiarySyncRecordV2.fromEntry(entry('A', t1, body: 'right')),
      );
      await service.synchronize(FileDiarySyncStoreV2(root));
      final afterFirst = repository.entries['A']!;
      final result = await service.synchronize(FileDiarySyncStoreV2(root));
      expect(result.updated, 0);
      expect(result.exported, 0);
      expect(result.skipped, 1);
      expect(repository.entries['A']?.body, afterFirst.body);
    },
  );

  test('bad JSON does not block other remote entries', () async {
    final store = FileDiarySyncStoreV2(root);
    await store.ensureReady();
    await File(
      '${store.entriesDirectory.path}${Platform.pathSeparator}bad.json',
    ).writeAsString('{');
    await writeRemote(DiarySyncRecordV2.fromEntry(entry('good', t1)));
    final result = await service.synchronize(FileDiarySyncStoreV2(root));
    expect(result.errors, hasLength(1));
    expect(repository.entries, contains('good'));
  });

  test('tombstone and restore propagate by updatedAt', () async {
    repository.entries['A'] = entry('A', t1);
    await writeRemote(
      DiarySyncRecordV2.fromEntry(entry('A', t2, deletedAt: t2)),
    );
    await service.synchronize(FileDiarySyncStoreV2(root));
    expect(repository.entries['A']?.deletedAt, t2);

    final restored = entry('A', t2.add(const Duration(hours: 1)));
    repository.entries['A'] = restored;
    await service.synchronize(FileDiarySyncStoreV2(root));
    final remote = codec.decode(
      await File(
        '${FileDiarySyncStoreV2(root).entriesDirectory.path}${Platform.pathSeparator}A.json',
      ).readAsString(),
    );
    expect(remote.deletedAt, isNull);
  });

  test(
    'permanent purge tombstone deletes local and prevents resurrection',
    () async {
      repository.entries['A'] = entry('A', t1);
      await writeRemote(DiarySyncRecordV2.purged(id: 'A', updatedAt: t2));
      await service.synchronize(FileDiarySyncStoreV2(root));
      expect(repository.entries, isNot(contains('A')));
      expect(repository.deleteCount, 1);
      await service.synchronize(FileDiarySyncStoreV2(root));
      expect(repository.entries, isNot(contains('A')));
    },
  );

  test(
    'images export/import, tolerate missing, and import late arrivals',
    () async {
      repository.entries['A'] = entry(
        'A',
        t1,
        imageIds: const ['one.jpg', 'two.jpg'],
      );
      images.values['one.jpg'] = Uint8List.fromList([1]);
      final first = await service.synchronize(FileDiarySyncStoreV2(root));
      expect(first.imagesExported, 1);
      expect(first.warnings, hasLength(1));

      final store = FileDiarySyncStoreV2(root);
      await store.writeImageAtomic('two.jpg', Uint8List.fromList([2]));
      final second = await service.synchronize(FileDiarySyncStoreV2(root));
      expect(second.imagesImported, 1);
      expect(images.values['two.jpg'], [2]);
    },
  );

  test(
    'removed reference disappears but orphan sync image is retained',
    () async {
      final store = FileDiarySyncStoreV2(root);
      await store.writeImageAtomic('orphan.jpg', Uint8List.fromList([9]));
      repository.entries['A'] = entry('A', t2, imageIds: const []);
      await writeRemote(
        DiarySyncRecordV2.fromEntry(
          entry('A', t1, imageIds: const ['orphan.jpg']),
        ),
      );
      await service.synchronize(FileDiarySyncStoreV2(root));
      expect(repository.entries['A']?.imageIds, isEmpty);
      expect(await store.readImage('orphan.jpg'), [9]);
    },
  );
}

class _MemoryRepository implements DiaryRepositoryV2 {
  final entries = <String, DiaryEntryV2>{};
  int saveCount = 0;
  int deleteCount = 0;

  @override
  Future<DiaryEntryV2?> getById(String id) async => entries[id];

  @override
  Stream<List<DiaryEntryV2>> watchEntries({
    DiaryQuery query = const DiaryQuery(),
  }) async* {
    yield entries.values
        .where((entry) => query.includeDeleted || !entry.isDeleted)
        .toList(growable: false);
  }

  @override
  Future<void> save(DiaryEntryV2 entry) async {
    saveCount++;
    entries[entry.id] = entry;
  }

  @override
  Future<void> restoreFromBackup(DiaryEntryV2 entry) => save(entry);

  @override
  Future<void> deletePermanently(String id) async {
    deleteCount++;
    entries.remove(id);
  }

  @override
  Future<void> moveToTrash(String id, {required DateTime deletedAt}) async {
    entries[id] = entries[id]!.copyWith(
      deletedAt: deletedAt,
      updatedAt: deletedAt,
    );
  }

  @override
  Future<void> restore(String id) async {
    entries[id] = entries[id]!.copyWith(
      restore: true,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> setFavorite(String id, {required bool isFavorite}) async {
    entries[id] = entries[id]!.copyWith(
      isFavorite: isFavorite,
      updatedAt: DateTime.now().toUtc(),
    );
  }
}

class _MemoryImageStore implements DiaryImageStoreV2, DiaryImageImportStoreV2 {
  final values = <String, Uint8List>{};

  @override
  Future<void> delete(String imageId) async => values.remove(imageId);

  @override
  Future<void> import({
    required String imageId,
    required Uint8List bytes,
  }) async {
    values[imageId] = bytes;
  }

  @override
  Future<Uint8List?> read(String imageId) async => values[imageId];

  @override
  Future<String> save({
    required Uint8List bytes,
    required String extension,
  }) async {
    final id = 'generated.$extension';
    values[id] = bytes;
    return id;
  }
}
