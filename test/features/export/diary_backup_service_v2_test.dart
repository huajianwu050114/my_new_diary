import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_new_diary/features/analysis/data/stop_words_store_v2.dart';
import 'package:my_new_diary/features/ai/data/ai_memory_store_v2.dart';
import 'package:my_new_diary/features/ai/domain/ai_memory_v2.dart';
import 'package:my_new_diary/features/diary/application/ports/diary_image_store_v2.dart';
import 'package:my_new_diary/features/diary/data/local/diary_database_v2.dart';
import 'package:my_new_diary/features/diary/data/local/sqlite_diary_repository_v2.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';
import 'package:my_new_diary/features/export/application/diary_backup_service_v2.dart';
import 'package:my_new_diary/features/export/application/backup_sqlite_snapshot_reader_v2.dart';
import 'package:my_new_diary/features/export/application/diary_pdf_service_v2.dart';
import 'package:my_new_diary/features/festival/data/sqlite_festival_repository_v2.dart';
import 'package:my_new_diary/features/festival/domain/festival_v2.dart';
import 'package:my_new_diary/features/life_library/data/sqlite_life_document_repository_v2.dart';
import 'package:my_new_diary/features/life_library/domain/life_document_v2.dart';
import 'package:my_new_diary/features/life_library/domain/life_space_v2.dart';
import 'package:my_new_diary/features/life_guide/data/sqlite_life_fragment_repository_v2.dart';
import 'package:my_new_diary/features/life_guide/domain/life_fragment_v2.dart';
import 'package:my_new_diary/features/self_engine/data/local/sqlite_self_engine_repository_v2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('creates a PDF with the bundled Chinese font', () async {
    final timestamp = DateTime.utc(2026, 7, 28);
    final bytes = await DiaryPdfServiceV2(imageStore: _MemoryImageStore())
        .create([
          DiaryEntryV2(
            id: 'entry-1',
            body: '一篇可以导出的日记',
            entryDate: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        ]);

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test(
    'round-trips raw and user-confirmed data without derived Self data',
    () async {
      SharedPreferences.setMockInitialValues({});
      final sourceDatabase = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => inMemoryDatabasePath,
      );
      final sourceDiary = SqliteDiaryRepositoryV2(await sourceDatabase.open());
      final sourceFestival = SqliteFestivalRepositoryV2(
        await sourceDatabase.open(),
      );
      final sourceImages = _MemoryImageStore();
      final sourceLife = SqliteLifeDocumentRepositoryV2(
        await sourceDatabase.open(),
      );
      final sourceGuide = SqliteLifeFragmentRepositoryV2(
        await sourceDatabase.open(),
      );
      final sourceSelf = SqliteSelfEngineRepositoryV2(
        await sourceDatabase.open(),
      );
      final imageId = await sourceImages.save(
        bytes: Uint8List.fromList([1, 2, 3]),
        extension: 'jpg',
      );
      final timestamp = DateTime.utc(2026, 7, 28);
      await sourceDiary.save(
        DiaryEntryV2(
          id: 'entry-1',
          body: 'Backup me',
          contentDelta: '[{"insert":"Backup me\\n"}]',
          entryDate: timestamp,
          createdAt: timestamp,
          updatedAt: timestamp,
          imageIds: [imageId],
          tags: const ['backup'],
          isFavorite: true,
        ),
      );
      await sourceFestival.save(
        CustomFestivalV2(
          id: 'festival-1',
          name: 'Anniversary',
          month: 7,
          day: 28,
          createdAt: timestamp,
        ),
      );
      await sourceLife.saveSpace(
        LifeSpaceV2(
          id: 'reading-space',
          name: '我的阅读',
          iconCodePoint: 0xe865,
          colorValue: 0xff7e57c2,
          sortOrder: 1,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      await sourceLife.save(
        LifeDocumentV2(
          id: 'reading-list',
          space: 'reading-space',
          title: '阅读清单',
          markdown: '# 阅读清单\n\n- [ ] 第一本书',
          type: LifeDocumentTypeV2.checklist,
          tags: const ['阅读'],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      await sourceLife.save(
        LifeDocumentV2(
          id: 'deleted-note',
          space: 'reading-space',
          title: '已删除但仍应备份',
          markdown: '等待用户决定是否永久删除',
          type: LifeDocumentTypeV2.note,
          createdAt: timestamp,
          updatedAt: timestamp,
          deletedAt: timestamp,
        ),
      );
      final originalFragment = _lifeFragment(timestamp);
      await sourceGuide.save(originalFragment);
      await sourceGuide.updateWithRevision(
        originalFragment.copyWith(
          title: '更新后的认识',
          updatedAt: timestamp.add(const Duration(days: 1)),
        ),
        previous: originalFragment,
      );
      final stopWords = StopWordsStoreV2();
      await stopWords.save({'private'});
      final aiMemories = AiMemoryStoreV2();
      await aiMemories.save(
        AiMemoryV2(id: 'memory-1', text: '我更喜欢先被倾听。', createdAt: timestamp),
      );

      final bytes = await DiaryBackupServiceV2(
        diaryRepository: sourceDiary,
        imageStore: sourceImages,
        festivalRepository: sourceFestival,
        stopWordsStore: stopWords,
        lifeDocumentRepository: sourceLife,
        lifeFragmentRepository: sourceGuide,
        selfEngineRepository: sourceSelf,
        aiMemoryStore: aiMemories,
        snapshotReader: BackupSqliteSnapshotReaderV2(
          await sourceDatabase.open(),
        ),
      ).exportZip();

      await sourceDiary.dispose();
      await sourceFestival.dispose();
      await sourceLife.dispose();
      await sourceGuide.dispose();
      await sourceDatabase.close();

      SharedPreferences.setMockInitialValues({});
      final targetDatabase = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => inMemoryDatabasePath,
      );
      final targetDiary = SqliteDiaryRepositoryV2(await targetDatabase.open());
      final targetFestival = SqliteFestivalRepositoryV2(
        await targetDatabase.open(),
      );
      final targetImages = _MemoryImageStore();
      final targetLife = SqliteLifeDocumentRepositoryV2(
        await targetDatabase.open(),
      );
      final targetGuide = SqliteLifeFragmentRepositoryV2(
        await targetDatabase.open(),
      );
      final targetSelf = SqliteSelfEngineRepositoryV2(
        await targetDatabase.open(),
      );
      final report = await DiaryBackupServiceV2(
        diaryRepository: targetDiary,
        imageStore: targetImages,
        festivalRepository: targetFestival,
        stopWordsStore: stopWords,
        lifeDocumentRepository: targetLife,
        lifeFragmentRepository: targetGuide,
        selfEngineRepository: targetSelf,
        aiMemoryStore: aiMemories,
        snapshotReader: BackupSqliteSnapshotReaderV2(
          await targetDatabase.open(),
        ),
      ).importZip(bytes);

      final restored = await targetDiary.getById('entry-1');
      expect(report.importedEntries, 1);
      expect(report.importedFestivals, 1);
      expect(restored?.body, 'Backup me');
      expect(restored?.contentDelta, '[{"insert":"Backup me\\n"}]');
      expect(restored?.isFavorite, isTrue);
      expect(await targetImages.read(restored!.imageIds.single), [1, 2, 3]);
      expect(await targetFestival.watchCustomFestivals().first, hasLength(1));
      expect(await stopWords.load(), {'private'});
      expect(report.importedLifeSpaces, 2);
      expect(report.importedLifeDocuments, 2);
      expect(report.importedDiaryRevisions, 1);
      expect(report.importedLifeFragments, 1);
      expect(report.importedLifeFragmentRevisions, 1);
      expect(report.importedAiMemories, 1);
      expect((await targetLife.getSpaceById('reading-space'))?.name, '我的阅读');
      expect(
        (await targetLife.getById('reading-list'))?.markdown,
        contains('第一本书'),
      );
      expect((await targetLife.getById('reading-list'))?.tags, ['阅读']);
      expect((await targetLife.getById('deleted-note'))?.deletedAt, isNotNull);
      expect((await targetSelf.getAllRevisions()), hasLength(1));
      expect((await targetSelf.getJobs()), hasLength(1));
      expect((await targetGuide.getById('fragment-1'))?.title, '更新后的认识');
      expect(await targetGuide.getRevisions('fragment-1'), hasLength(1));
      expect((await aiMemories.load()).single.text, '我更喜欢先被倾听。');

      await targetDiary.dispose();
      await targetFestival.dispose();
      await targetLife.dispose();
      await targetGuide.dispose();
      await targetDatabase.close();
    },
  );
}

LifeFragmentV2 _lifeFragment(DateTime timestamp) => LifeFragmentV2(
  id: 'fragment-1',
  title: '最初的认识',
  coreInsight: '允许自己慢一点。',
  context: '一段真实经历。',
  evidence: '日记中的原话。',
  futureUse: '再次着急时。',
  messageToFutureSelf: '先照顾好自己。',
  theme: '生活节奏',
  sourceDiaryIds: const ['entry-1'],
  status: LifeFragmentStatusV2.confirmed,
  createdAt: timestamp,
  updatedAt: timestamp,
);

class _MemoryImageStore implements DiaryImageStoreV2 {
  final _values = <String, Uint8List>{};

  @override
  Future<void> delete(String imageId) async {
    _values.remove(imageId);
  }

  @override
  Future<Uint8List?> read(String imageId) async => _values[imageId];

  @override
  Future<String> save({
    required Uint8List bytes,
    required String extension,
  }) async {
    final id = 'image-${_values.length + 1}.$extension';
    _values[id] = bytes;
    return id;
  }
}
