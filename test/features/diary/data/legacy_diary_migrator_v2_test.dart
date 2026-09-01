import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_new_diary/features/diary/data/local/diary_database_v2.dart';
import 'package:my_new_diary/features/diary/data/local/local_diary_image_store_v2.dart';
import 'package:my_new_diary/features/diary/data/local/sqlite_diary_repository_v2.dart';
import 'package:my_new_diary/features/diary/data/migration/legacy_diary_migrator_v2.dart';

void main() {
  sqfliteFfiInit();

  late Directory temporaryDirectory;
  late DiaryDatabaseV2 databaseOwner;
  late SqliteDiaryRepositoryV2 repository;
  late LocalDiaryImageStoreV2 imageStore;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'diary_v2_migration_test_',
    );
    databaseOwner = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => inMemoryDatabasePath,
    );
    repository = SqliteDiaryRepositoryV2(await databaseOwner.open());
    imageStore = LocalDiaryImageStoreV2(
      rootDirectory: () async =>
          Directory(path.join(temporaryDirectory.path, 'v2_images')),
    );
  });

  tearDown(() async {
    await repository.dispose();
    await databaseOwner.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('imports legacy JSON once and copies its images', () async {
    final diaries = Directory(path.join(temporaryDirectory.path, 'diaries'));
    final legacyImages = Directory(
      path.join(temporaryDirectory.path, 'images'),
    );
    await diaries.create();
    await legacyImages.create();
    await File(
      path.join(legacyImages.path, 'photo.jpg'),
    ).writeAsBytes(Uint8List.fromList([1, 2, 3]));
    await File(path.join(diaries.path, '2026-07-28.json')).writeAsString('''
      {
        "text": "Imported diary",
        "date": "2026-07-28T00:00:00.000",
        "creationTime": "2026-07-28T08:00:00.000",
        "mood": "calm",
        "tags": ["legacy"],
        "imagePaths": ["photo.jpg"]
      }
    ''');

    final migrator = LegacyDiaryMigratorV2(
      repository: repository,
      imageStore: imageStore,
      databaseFactory: databaseFactoryFfi,
    );
    final first = await migrator.migrate(
      sqlitePath: path.join(temporaryDirectory.path, 'missing.db'),
      jsonDirectory: diaries,
      legacyImageDirectories: [legacyImages],
    );
    final second = await migrator.migrate(
      sqlitePath: path.join(temporaryDirectory.path, 'missing.db'),
      jsonDirectory: diaries,
      legacyImageDirectories: [legacyImages],
    );

    final entries = await repository.watchEntries().first;
    expect(first.imported, 1);
    expect(second.skipped, 1);
    expect(entries, hasLength(1));
    expect(entries.single.body, 'Imported diary');
    expect(entries.single.tags, ['legacy']);
    expect(
      await imageStore.read(entries.single.imageIds.single),
      Uint8List.fromList([1, 2, 3]),
    );
  });

  test('imports the legacy SQLite diary table', () async {
    final legacyPath = path.join(temporaryDirectory.path, 'diary.db');
    final legacyDatabase = await databaseFactoryFfi.openDatabase(legacyPath);
    await legacyDatabase.execute('''
      CREATE TABLE diaries (
        diaryId TEXT PRIMARY KEY,
        text TEXT,
        date TEXT,
        creationTime TEXT,
        mood TEXT,
        tags TEXT,
        imagePaths TEXT,
        aiAnalyses TEXT,
        isDeleted INTEGER,
        latitude REAL,
        longitude REAL,
        address TEXT
      )
    ''');
    await legacyDatabase.insert('diaries', {
      'diaryId': 'old-entry-1',
      'text': 'SQLite diary',
      'date': '2025-05-01T00:00:00.000',
      'creationTime': '2025-05-01T09:30:00.000',
      'tags': '["sqlite"]',
      'imagePaths': '[]',
      'aiAnalyses': '[]',
      'isDeleted': 0,
    });
    await legacyDatabase.close();

    final migrator = LegacyDiaryMigratorV2(
      repository: repository,
      imageStore: imageStore,
      databaseFactory: databaseFactoryFfi,
    );
    final report = await migrator.migrate(
      sqlitePath: legacyPath,
      jsonDirectory: Directory(
        path.join(temporaryDirectory.path, 'missing_json'),
      ),
      legacyImageDirectories: const [],
    );

    final entries = await repository.watchEntries().first;
    expect(report.imported, 1);
    expect(entries.single.body, 'SQLite diary');
    expect(entries.single.tags, ['sqlite']);
  });
}
