import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/diary/data/local/diary_database_v2.dart';
import 'package:my_new_diary/features/life_guide/data/sqlite_life_fragment_repository_v2.dart';
import 'package:my_new_diary/features/life_guide/domain/life_fragment_v2.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('保存并恢复经过确认的人生碎片', () async {
    final databaseOwner = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => inMemoryDatabasePath,
    );
    final repository = SqliteLifeFragmentRepositoryV2(
      await databaseOwner.open(),
    );
    final fragment = _fragment();

    await repository.save(fragment);
    final restored = await repository.getById(fragment.id);

    expect(restored?.title, '写给未来自己的提醒');
    expect(restored?.theme, '我的低谷经验');
    expect(restored?.sourceDiaryIds, ['diary-2026-07-20']);
    expect(restored?.isRope, isTrue);
    expect(restored?.status, LifeFragmentStatusV2.confirmed);
    await repository.dispose();
    await databaseOwner.close();
  });

  test('可以分别读取重要提醒和草稿', () async {
    final databaseOwner = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => inMemoryDatabasePath,
    );
    final repository = SqliteLifeFragmentRepositoryV2(
      await databaseOwner.open(),
    );
    await repository.save(_fragment());
    await repository.save(
      _fragment(id: 'draft-1').copyWith(
        title: '仍在思考的内容',
        isRope: false,
        status: LifeFragmentStatusV2.draft,
        updatedAt: DateTime.utc(2026, 7, 21),
      ),
    );

    final ropes = await repository.watchFragments(onlyRopes: true).first;
    final drafts = await repository
        .watchFragments(status: LifeFragmentStatusV2.draft)
        .first;

    expect(ropes.map((value) => value.title), ['写给未来自己的提醒']);
    expect(drafts.map((value) => value.title), ['仍在思考的内容']);
    await repository.dispose();
    await databaseOwner.close();
  });

  test('编辑前保存旧版本并允许读取修改历史', () async {
    final databaseOwner = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => inMemoryDatabasePath,
    );
    final repository = SqliteLifeFragmentRepositoryV2(
      await databaseOwner.open(),
    );
    final original = _fragment();
    await repository.save(original);
    final updated = original.copyWith(
      title: '修改后的标题',
      updatedAt: DateTime.utc(2026, 8, 19),
    );

    await repository.updateWithRevision(updated, previous: original);

    expect((await repository.getById(original.id))?.title, '修改后的标题');
    final history = await repository.getRevisions(original.id);
    expect(history, hasLength(1));
    expect(history.single.snapshot.title, original.title);
    await repository.dispose();
    await databaseOwner.close();
  });

  test('版本 3 数据库升级后保留日记并新增人生碎片表', () async {
    final directory = await Directory.systemTemp.createTemp(
      'life_guide_migration_',
    );
    final databasePath = path.join(directory.path, 'diary.db');
    final oldDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE diary_entries (
              id TEXT PRIMARY KEY NOT NULL,
              body TEXT NOT NULL,
              entry_date TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              image_ids TEXT NOT NULL DEFAULT '[]',
              mood TEXT,
              tags TEXT NOT NULL DEFAULT '[]',
              latitude REAL,
              longitude REAL,
              address TEXT,
              ai_analyses TEXT NOT NULL DEFAULT '[]',
              is_favorite INTEGER NOT NULL DEFAULT 0,
              deleted_at TEXT
            )
          ''');
        },
      ),
    );
    await oldDatabase.insert('diary_entries', {
      'id': 'existing-diary',
      'body': '升级前的日记',
      'entry_date': '2026-07-20T00:00:00.000Z',
      'created_at': '2026-07-20T00:00:00.000Z',
      'updated_at': '2026-07-20T00:00:00.000Z',
    });
    await oldDatabase.close();

    final databaseOwner = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => databasePath,
    );
    final upgraded = await databaseOwner.open();

    expect(await upgraded.query('diary_entries'), hasLength(1));
    expect(await upgraded.query('life_fragments'), isEmpty);
    expect(await upgraded.query('life_fragment_revisions'), isEmpty);
    await databaseOwner.close();
    await directory.delete(recursive: true);
  });
}

LifeFragmentV2 _fragment({String id = 'rope-1'}) {
  final now = DateTime.utc(2026, 7, 20, 22);
  return LifeFragmentV2(
    id: id,
    title: '写给未来自己的提醒',
    coreInsight: '我不是因为永远成功，所以相信自己。',
    context: '面对保研结果的不确定，我重新读到了高中时期的日记。',
    evidence: '我曾在低谷中写下永远心怀希望，并最终走过那段生活。',
    futureUse: '再次因为失败而怀疑自己时。',
    messageToFutureSelf: '过去的我没有辜负现在的我。',
    theme: '我的低谷经验',
    tags: const ['希望', '低谷'],
    sourceDiaryIds: const ['diary-2026-07-20'],
    isRope: true,
    status: LifeFragmentStatusV2.confirmed,
    createdAt: now,
    updatedAt: now,
  );
}
