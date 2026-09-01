import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_new_diary/features/analysis/data/stop_words_store_v2.dart';
import 'package:my_new_diary/features/diary/application/ports/diary_image_store_v2.dart';
import 'package:my_new_diary/features/diary/data/local/diary_database_v2.dart';
import 'package:my_new_diary/features/diary/data/local/sqlite_diary_repository_v2.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';
import 'package:my_new_diary/features/export/application/diary_backup_service_v2.dart';
import 'package:my_new_diary/features/export/application/diary_pdf_service_v2.dart';
import 'package:my_new_diary/features/festival/data/sqlite_festival_repository_v2.dart';
import 'package:my_new_diary/features/festival/domain/festival_v2.dart';

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
    'round-trips diary metadata, images, festivals, and stop words',
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
      final imageId = await sourceImages.save(
        bytes: Uint8List.fromList([1, 2, 3]),
        extension: 'jpg',
      );
      final timestamp = DateTime.utc(2026, 7, 28);
      await sourceDiary.save(
        DiaryEntryV2(
          id: 'entry-1',
          body: 'Backup me',
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
      final stopWords = StopWordsStoreV2();
      await stopWords.save({'private'});

      final bytes = await DiaryBackupServiceV2(
        diaryRepository: sourceDiary,
        imageStore: sourceImages,
        festivalRepository: sourceFestival,
        stopWordsStore: stopWords,
      ).exportZip();

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
      final report = await DiaryBackupServiceV2(
        diaryRepository: targetDiary,
        imageStore: targetImages,
        festivalRepository: targetFestival,
        stopWordsStore: stopWords,
      ).importZip(bytes);

      final restored = await targetDiary.getById('entry-1');
      expect(report.importedEntries, 1);
      expect(report.importedFestivals, 1);
      expect(restored?.body, 'Backup me');
      expect(restored?.isFavorite, isTrue);
      expect(await targetImages.read(restored!.imageIds.single), [1, 2, 3]);
      expect(await targetFestival.watchCustomFestivals().first, hasLength(1));
      expect(await stopWords.load(), {'private'});

      await sourceDiary.dispose();
      await sourceFestival.dispose();
      await sourceDatabase.close();
      await targetDiary.dispose();
      await targetFestival.dispose();
      await targetDatabase.close();
    },
  );
}

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
