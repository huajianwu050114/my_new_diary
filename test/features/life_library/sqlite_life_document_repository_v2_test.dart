import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/diary/data/local/diary_database_v2.dart';
import 'package:my_new_diary/features/life_library/data/sqlite_life_document_repository_v2.dart';
import 'package:my_new_diary/features/life_library/domain/life_document_v2.dart';
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
        space: LifeSpacesV2.habits,
        type: LifeDocumentTypeV2.template,
      ),
    );

    final cooking = await repository
        .watchDocuments(space: LifeSpacesV2.cooking)
        .first;

    expect(cooking, hasLength(1));
    expect(cooking.single.title, '周末采购');
    expect(cooking.single.markdown, contains('- [ ] 番茄'));
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
}

LifeDocumentV2 _document({
  String id = 'shopping-1',
  String space = LifeSpacesV2.cooking,
  String markdown = '# 周末采购\n\n- [ ] 番茄\n- [x] 牛腩',
  LifeDocumentTypeV2 type = LifeDocumentTypeV2.checklist,
}) {
  final now = DateTime.utc(2026, 8, 30, 12);
  return LifeDocumentV2(
    id: id,
    space: space,
    title: '周末采购',
    markdown: markdown,
    type: type,
    createdAt: now,
    updatedAt: now,
  );
}
