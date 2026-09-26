import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_new_diary/features/analysis/data/stop_words_store_v2.dart';
import 'package:my_new_diary/features/ai/data/ai_memory_store_v2.dart';
import 'package:my_new_diary/features/diary/application/ports/diary_image_store_v2.dart';
import 'package:my_new_diary/features/diary/data/local/diary_database_v2.dart';
import 'package:my_new_diary/features/diary/data/local/sqlite_diary_repository_v2.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';
import 'package:my_new_diary/features/diary/domain/repositories/diary_repository_v2.dart';
import 'package:my_new_diary/features/export/application/backup_restore_journal_v2.dart';
import 'package:my_new_diary/features/export/application/backup_sqlite_snapshot_reader_v2.dart';
import 'package:my_new_diary/features/export/application/diary_backup_service_v2.dart';
import 'package:my_new_diary/features/festival/data/sqlite_festival_repository_v2.dart';
import 'package:my_new_diary/features/festival/domain/festival_repository_v2.dart';
import 'package:my_new_diary/features/festival/domain/festival_v2.dart';
import 'package:my_new_diary/features/life_guide/data/sqlite_life_fragment_repository_v2.dart';
import 'package:my_new_diary/features/life_guide/domain/life_fragment_v2.dart';
import 'package:my_new_diary/features/life_library/data/sqlite_life_document_repository_v2.dart';
import 'package:my_new_diary/features/life_library/domain/life_document_v2.dart';
import 'package:my_new_diary/features/self_engine/data/local/sqlite_self_engine_repository_v2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('missing image rejects backup before destination mutation', () async {
    final backup = await _simpleBackup();
    final withoutImage = _rewriteArchive(backup, removeImages: true);
    SharedPreferences.setMockInitialValues({});
    final target = await _Harness.create();
    try {
      await expectLater(
        target.service.importZip(withoutImage),
        throwsFormatException,
      );
      expect(
        await target.diary
            .watchEntries(query: const DiaryQuery(includeDeleted: true))
            .first,
        isEmpty,
      );
      expect(await BackupRestoreJournalV2().load(), isNull);
    } finally {
      await target.dispose();
    }
  });

  test('image save failure leaves a resumable journal and no diary', () async {
    final backup = await _simpleBackup();
    SharedPreferences.setMockInitialValues({});
    final images = _FaultImageStore()..failNextSave = true;
    final target = await _Harness.create(images: images);
    try {
      await expectLater(target.service.importZip(backup), throwsStateError);
      expect(await target.diary.getById('entry-1'), isNull);
      expect(await BackupRestoreJournalV2().load(), isNotNull);

      await target.service.importZip(backup);
      expect(await target.diary.getById('entry-1'), isNotNull);
      expect(await BackupRestoreJournalV2().load(), isNull);
    } finally {
      await target.dispose();
    }
  });

  test('old image delete failure cannot damage a fresh restore', () async {
    final backup = await _simpleBackup();
    SharedPreferences.setMockInitialValues({});
    final images = _FaultImageStore()..failDelete = true;
    final target = await _Harness.create(images: images);
    try {
      await target.service.importZip(backup);
      final restored = await target.diary.getById('entry-1');
      expect(restored, isNotNull);
      expect(await images.read(restored!.imageIds.single), [1, 2, 3]);
      expect(images.deleteCalls, 0);
    } finally {
      await target.dispose();
    }
  });

  test(
    'non-empty destination is rejected without overwriting user data',
    () async {
      final backup = await _simpleBackup(includeGuide: true);
      SharedPreferences.setMockInitialValues({});
      final target = await _Harness.create();
      final timestamp = DateTime.utc(2026, 1, 1);
      final local = _entry(body: 'Local newer text', imageIds: const []);
      final fragment = _fragment(timestamp, title: 'Local guide');
      try {
        await target.diary.save(local);
        await target.guide.save(fragment);
        await target.guide.updateWithRevision(
          _fragment(timestamp, title: 'Local guide edited'),
          previous: fragment,
        );
        final revisionsBefore = await target.guide.getRevisions(fragment.id);

        await expectLater(
          target.service.importZip(backup),
          throwsA(isA<BackupRestoreConflictV2>()),
        );
        expect(
          (await target.diary.getById(local.id))?.body,
          'Local newer text',
        );
        expect(
          await target.guide.getRevisions(fragment.id),
          hasLength(revisionsBefore.length),
        );
      } finally {
        await target.dispose();
      }
    },
  );

  test(
    'Life Guide update path does not cascade-delete local revisions',
    () async {
      final target = await _Harness.create();
      final timestamp = DateTime.utc(2026, 1, 1);
      final original = _fragment(timestamp, title: 'Original');
      try {
        await target.guide.save(original);
        await target.guide.updateWithRevision(
          _fragment(timestamp, title: 'Edited'),
          previous: original,
        );
        expect(await target.guide.getRevisions(original.id), hasLength(1));

        await target.guide.save(
          _fragment(timestamp, title: 'Restored current'),
        );
        expect(await target.guide.getRevisions(original.id), hasLength(1));
      } finally {
        await target.dispose();
      }
    },
  );

  test('partial restore can retry safely with the same backup', () async {
    final backup = await _simpleBackup(includeFestival: true);
    SharedPreferences.setMockInitialValues({});
    final target = await _Harness.create();
    final failingFestival = _FailOnceFestivalRepository(target.festival);
    final service = target.serviceWith(festivalRepository: failingFestival);
    try {
      await expectLater(service.importZip(backup), throwsStateError);
      expect(await target.diary.getById('entry-1'), isNotNull);
      expect(await BackupRestoreJournalV2().load(), isNotNull);

      final report = await service.importZip(backup);
      expect(report.importedEntries, 1);
      expect(report.importedFestivals, 1);
      expect(await target.self.getAllRevisions(), hasLength(1));
      expect(await target.self.getJobs(), hasLength(1));
      expect(await BackupRestoreJournalV2().load(), isNull);
    } finally {
      await target.dispose();
    }
  });

  test(
    'resume rejects unrelated data created during partial restore',
    () async {
      final backup = await _simpleBackup(includeFestival: true);
      SharedPreferences.setMockInitialValues({});
      final target = await _Harness.create();
      final service = target.serviceWith(
        festivalRepository: _FailOnceFestivalRepository(target.festival),
      );
      try {
        await expectLater(service.importZip(backup), throwsStateError);
        await target.diary.save(
          DiaryEntryV2(
            id: 'unrelated',
            body: 'Created while restore was incomplete',
            entryDate: DateTime.utc(2026, 1, 3),
            createdAt: DateTime.utc(2026, 1, 3),
            updatedAt: DateTime.utc(2026, 1, 3),
          ),
        );

        await expectLater(
          service.importZip(backup),
          throwsA(isA<BackupRestoreConflictV2>()),
        );
        expect(await target.diary.getById('entry-1'), isNotNull);
        expect(await target.diary.getById('unrelated'), isNotNull);
        expect(await BackupRestoreJournalV2().load(), isNotNull);
      } finally {
        await target.dispose();
      }
    },
  );

  test('tampered revision hash is rejected before restore starts', () async {
    final backup = await _simpleBackup();
    final tampered = _rewriteArchive(
      backup,
      mutateManifest: (manifest) {
        final revisions = manifest['diaryRevisions']! as List;
        (revisions.single as Map<String, dynamic>)['sourceHash'] = 'bad-hash';
      },
    );
    SharedPreferences.setMockInitialValues({});
    final target = await _Harness.create();
    try {
      await expectLater(
        target.service.importZip(tampered),
        throwsFormatException,
      );
      expect(await target.diary.getById('entry-1'), isNull);
      expect(await BackupRestoreJournalV2().load(), isNull);
    } finally {
      await target.dispose();
    }
  });

  test('malformed manifest is rejected before image staging', () async {
    final backup = await _simpleBackup(includeFestival: true);
    final malformed = _rewriteArchive(
      backup,
      mutateManifest: (manifest) {
        final festivals = manifest['festivals']! as List;
        (festivals.single as Map<String, dynamic>)['createdAt'] = 'not-a-date';
      },
    );
    SharedPreferences.setMockInitialValues({});
    final images = _FaultImageStore();
    final target = await _Harness.create(images: images);
    try {
      await expectLater(
        target.service.importZip(malformed),
        throwsFormatException,
      );
      expect(images.saveCalls, 0);
      expect(await target.diary.getById('entry-1'), isNull);
      expect(await BackupRestoreJournalV2().load(), isNull);
    } finally {
      await target.dispose();
    }
  });

  test('v1 backup restores and backfills a baseline revision', () async {
    final backup = await _simpleBackup();
    final v1 = _rewriteArchive(
      backup,
      mutateManifest: (manifest) {
        manifest['version'] = 1;
        manifest.remove('fingerprintVersion');
        manifest.remove('diaryRevisions');
        manifest.remove('lifeFragments');
        manifest.remove('lifeFragmentRevisions');
        manifest.remove('aiMemories');
      },
    );
    SharedPreferences.setMockInitialValues({});
    final target = await _Harness.create();
    try {
      await target.service.importZip(v1);
      expect(await target.diary.getById('entry-1'), isNotNull);
      expect(await target.self.getAllRevisions(), hasLength(1));
      expect(await target.self.getJobs(), hasLength(1));
    } finally {
      await target.dispose();
    }
  });

  test('v2 export fails closed for an unbackfilled legacy diary', () async {
    final source = await _Harness.create();
    final now = DateTime.utc(2026, 1, 2).toIso8601String();
    try {
      await source.db.insert('diary_entries', {
        'id': 'legacy-without-revision',
        'body': 'Legacy source',
        'entry_date': now,
        'created_at': now,
        'updated_at': now,
      });

      await expectLater(source.service.exportZip(), throwsFormatException);
    } finally {
      await source.dispose();
    }
  });

  test('export rejects an invalid SQLite ownership graph', () async {
    final source = await _Harness.create();
    final now = DateTime.utc(2026, 1, 2);
    try {
      await source.db.insert('life_documents', {
        'id': 'orphan-document',
        'space': 'missing-space',
        'title': 'Orphan',
        'markdown': 'Must not be exported',
        'document_type': LifeDocumentTypeV2.note.name,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      await expectLater(source.service.exportZip(), throwsFormatException);
    } finally {
      await source.dispose();
    }
  });

  test(
    'concurrent A to B save cannot tear the SQLite export snapshot',
    () async {
      final source = await _Harness.create();
      late Future<void> saveB;
      try {
        await source.diary.save(_entry(body: 'A'));
        final reader = BackupSqliteSnapshotReaderV2(
          source.db,
          afterDiaryRead: () async {
            saveB = source.diary.save(_entry(body: 'B'));
            await Future<void>.delayed(const Duration(milliseconds: 20));
          },
        );

        final backup = await source
            .serviceWith(snapshotReader: reader)
            .exportZip();
        await saveB;
        final manifest = _manifest(backup);
        expect((manifest['entries']! as List).single['body'], 'A');
        final revisions = manifest['diaryRevisions']! as List;
        expect(revisions, hasLength(1));
        expect((revisions.single as Map<String, dynamic>)['body'], 'A');
        expect((await source.diary.getById('entry-1'))?.body, 'B');
      } finally {
        await source.dispose();
      }
    },
  );

  test('derived runtime tables are excluded from a v2 archive', () async {
    final source = await _Harness.create();
    try {
      await source.diary.save(_entry());
      final revision = (await source.self.getAllRevisions()).single;
      final now = DateTime.utc(2026, 1, 2).toIso8601String();
      await source.db.insert('memory_atoms', {
        'id': 'derived-atom',
        'revision_id': revision.id,
        'kind': 'event',
        'statement': 'Derived',
        'source_quote': 'Backup source',
        'scope': 'state',
        'pipeline_version': 1,
        'generation': 1,
        'created_at': now,
      });
      await source.db.insert('memory_threads', {
        'id': 'derived-thread',
        'title': 'Derived',
        'description': '',
        'status': 'active',
        'first_seen': now,
        'last_seen': now,
        'pipeline_version': 1,
        'generation': 1,
        'created_at': now,
        'updated_at': now,
      });
      await source.db.insert('thread_memberships', {
        'thread_id': 'derived-thread',
        'atom_id': 'derived-atom',
        'relevance': 1.0,
        'origin': 'automatic',
        'generation': 1,
        'created_at': now,
      });
      expect(await source.db.query('self_engine_computations'), isNotEmpty);
      expect(await source.db.query('self_engine_jobs'), isNotEmpty);

      final manifest = _manifest(await source.service.exportZip());
      expect(manifest, isNot(contains('memoryAtoms')));
      expect(manifest, isNot(contains('memoryThreads')));
      expect(manifest, isNot(contains('threadMemberships')));
      expect(manifest, isNot(contains('selfEngineComputations')));
      expect(manifest, isNot(contains('selfEngineJobs')));
    } finally {
      await source.dispose();
    }
  });
}

Future<Uint8List> _simpleBackup({
  bool includeFestival = false,
  bool includeGuide = false,
}) async {
  final source = await _Harness.create();
  try {
    final imageId = await source.images.save(
      bytes: Uint8List.fromList([1, 2, 3]),
      extension: 'jpg',
    );
    await source.diary.save(_entry(imageIds: [imageId]));
    if (includeFestival) {
      await source.festival.save(
        CustomFestivalV2(
          id: 'festival-1',
          name: 'Safe restore',
          month: 1,
          day: 2,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
    }
    if (includeGuide) {
      await source.guide.save(_fragment(DateTime.utc(2026, 1, 1)));
    }
    return await source.service.exportZip();
  } finally {
    await source.dispose();
  }
}

Uint8List _rewriteArchive(
  Uint8List bytes, {
  bool removeImages = false,
  void Function(Map<String, dynamic> manifest)? mutateManifest,
}) {
  final source = ZipDecoder().decodeBytes(bytes);
  final output = Archive();
  for (final file in source.files) {
    if (removeImages && file.name.startsWith('images/')) continue;
    if (file.name == 'manifest.json') {
      final manifest = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(file.content as List<int>)) as Map,
      );
      mutateManifest?.call(manifest);
      final data = utf8.encode(jsonEncode(manifest));
      output.addFile(ArchiveFile(file.name, data.length, data));
    } else {
      output.addFile(ArchiveFile(file.name, file.size, file.content));
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(output));
}

Map<String, dynamic> _manifest(Uint8List bytes) {
  final file = ZipDecoder().decodeBytes(bytes).findFile('manifest.json')!;
  return Map<String, dynamic>.from(
    jsonDecode(utf8.decode(file.content as List<int>)) as Map,
  );
}

DiaryEntryV2 _entry({
  String body = 'Backup source',
  List<String> imageIds = const [],
}) {
  final timestamp = DateTime.utc(2026, 1, 2);
  return DiaryEntryV2(
    id: 'entry-1',
    body: body,
    entryDate: timestamp,
    createdAt: timestamp,
    updatedAt: timestamp,
    imageIds: imageIds,
  );
}

LifeFragmentV2 _fragment(DateTime timestamp, {String title = 'Guide'}) =>
    LifeFragmentV2(
      id: 'fragment-1',
      title: title,
      coreInsight: 'Insight',
      context: 'Context',
      evidence: 'Evidence',
      futureUse: 'Future',
      messageToFutureSelf: 'Message',
      theme: 'Theme',
      status: LifeFragmentStatusV2.confirmed,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

class _Harness {
  _Harness({
    required this.database,
    required this.db,
    required this.diary,
    required this.festival,
    required this.life,
    required this.guide,
    required this.self,
    required this.images,
  });

  static Future<_Harness> create({_FaultImageStore? images}) async {
    final database = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => inMemoryDatabasePath,
    );
    final db = await database.open();
    return _Harness(
      database: database,
      db: db,
      diary: SqliteDiaryRepositoryV2(db),
      festival: SqliteFestivalRepositoryV2(db),
      life: SqliteLifeDocumentRepositoryV2(db),
      guide: SqliteLifeFragmentRepositoryV2(db),
      self: SqliteSelfEngineRepositoryV2(db),
      images: images ?? _FaultImageStore(),
    );
  }

  final DiaryDatabaseV2 database;
  final Database db;
  final SqliteDiaryRepositoryV2 diary;
  final SqliteFestivalRepositoryV2 festival;
  final SqliteLifeDocumentRepositoryV2 life;
  final SqliteLifeFragmentRepositoryV2 guide;
  final SqliteSelfEngineRepositoryV2 self;
  final _FaultImageStore images;

  DiaryBackupServiceV2 get service => serviceWith();

  DiaryBackupServiceV2 serviceWith({
    FestivalRepositoryV2? festivalRepository,
    BackupSqliteSnapshotReaderV2? snapshotReader,
  }) => DiaryBackupServiceV2(
    diaryRepository: diary,
    imageStore: images,
    festivalRepository: festivalRepository ?? festival,
    stopWordsStore: StopWordsStoreV2(),
    lifeDocumentRepository: life,
    lifeFragmentRepository: guide,
    selfEngineRepository: self,
    aiMemoryStore: AiMemoryStoreV2(),
    snapshotReader: snapshotReader ?? BackupSqliteSnapshotReaderV2(db),
  );

  Future<void> dispose() async {
    await diary.dispose();
    await festival.dispose();
    await life.dispose();
    await guide.dispose();
    await database.close();
  }
}

class _FaultImageStore implements DiaryImageStoreV2 {
  final Map<String, Uint8List> values = {};
  bool failNextSave = false;
  bool failDelete = false;
  int saveCalls = 0;
  int deleteCalls = 0;

  @override
  Future<void> delete(String imageId) async {
    deleteCalls++;
    if (failDelete) throw StateError('delete failed');
    values.remove(imageId);
  }

  @override
  Future<Uint8List?> read(String imageId) async => values[imageId];

  @override
  Future<String> save({
    required Uint8List bytes,
    required String extension,
  }) async {
    saveCalls++;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('save failed');
    }
    final id = 'image-${values.length + 1}.$extension';
    values[id] = bytes;
    return id;
  }
}

class _FailOnceFestivalRepository implements FestivalRepositoryV2 {
  _FailOnceFestivalRepository(this.delegate);

  final FestivalRepositoryV2 delegate;
  bool shouldFail = true;

  @override
  Future<void> delete(String id) => delegate.delete(id);

  @override
  Future<void> save(CustomFestivalV2 festival) {
    if (shouldFail) {
      shouldFail = false;
      throw StateError('festival restore failed');
    }
    return delegate.save(festival);
  }

  @override
  Stream<List<CustomFestivalV2>> watchCustomFestivals() =>
      delegate.watchCustomFestivals();
}
