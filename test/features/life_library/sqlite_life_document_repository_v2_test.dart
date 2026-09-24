import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/diary/data/local/diary_database_v2.dart';
import 'package:my_new_diary/features/life_library/data/sqlite_life_document_repository_v2.dart';
import 'package:my_new_diary/features/life_library/domain/life_document_v2.dart';
import 'package:my_new_diary/features/life_library/domain/life_space_v2.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late DiaryDatabaseV2 databaseOwner;
  late SqliteLifeDocumentRepositoryV2 repository;

  setUp(() async {
    databaseOwner = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => inMemoryDatabasePath,
    );
    repository = SqliteLifeDocumentRepositoryV2(await databaseOwner.open());
  });

  tearDown(() async {
    await repository.dispose();
    await databaseOwner.close();
  });

  test('保存、读取并按生活分区筛选 Markdown 文档', () async {
    await repository.save(_document());
    await repository.save(
      _document(
        id: 'workout-1',
        space: 'workout-space',
        type: LifeDocumentTypeV2.template,
      ),
    );

    final cooking = await repository
        .watchDocuments(space: 'cooking-space')
        .first;

    expect(cooking, hasLength(1));
    expect(cooking.single.title, '周末采购');
    expect(cooking.single.markdown, contains('- [ ] 番茄'));
    expect(cooking.single.tags, ['采购']);
  });

  test('清单完成数从标准 Markdown 任务语法计算', () {
    final document = _document(markdown: '- [ ] 番茄\n- [x] 牛腩\n* [X] 土豆\n普通内容');

    expect(document.checklistTotal, 3);
    expect(document.checklistCompleted, 2);
  });

  test('删除采用软删除且默认列表不再显示', () async {
    final document = _document();
    await repository.save(document);

    await repository.delete(document.id);

    expect(await repository.watchDocuments().first, isEmpty);
    expect((await repository.getById(document.id))?.deletedAt, isNotNull);
  });

  test('可以创建任意生活空间并保存文档', () async {
    final now = DateTime.utc(2026, 9, 2);
    await repository.saveSpace(
      LifeSpaceV2(
        id: 'travel-space',
        name: '旅行准备',
        iconCodePoint: 0xe55f,
        colorValue: 0xff5c6bc0,
        sortOrder: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.save(_document(id: 'trip-1', space: 'travel-space'));

    final spaces = await repository.watchSpaces().first;
    expect(spaces.map((item) => item.name), contains('旅行准备'));
    expect(
      await repository.watchDocuments(space: 'travel-space').first,
      hasLength(1),
    );
  });

  test('删除空间时将其中的文档移入收件箱', () async {
    final now = DateTime.utc(2026, 9, 2);
    await repository.saveSpace(
      LifeSpaceV2(
        id: 'temporary-space',
        name: '临时空间',
        iconCodePoint: 0xe2c8,
        colorValue: 0xff607d8b,
        sortOrder: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.save(_document(space: 'temporary-space'));

    await repository.deleteSpace('temporary-space');

    expect(await repository.getSpaceById('temporary-space'), isNull);
    expect(
      (await repository.getById('shopping-1'))?.space,
      LifeSpaceDefaultsV2.inboxId,
    );
  });
}

LifeDocumentV2 _document({
  String id = 'shopping-1',
  String space = 'cooking-space',
  String markdown = '# 周末采购\n\n- [ ] 番茄\n- [x] 牛腩',
  LifeDocumentTypeV2 type = LifeDocumentTypeV2.checklist,
  List<String> tags = const ['采购'],
}) {
  final now = DateTime.utc(2026, 8, 30, 12);
  return LifeDocumentV2(
    id: id,
    space: space,
    title: '周末采购',
    markdown: markdown,
    type: type,
    tags: tags,
    createdAt: now,
    updatedAt: now,
  );
}
