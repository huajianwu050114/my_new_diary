import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_new_diary/features/diary/data/local/diary_database_v2.dart';
import 'package:my_new_diary/features/diary/data/local/sqlite_diary_repository_v2.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';
import 'package:my_new_diary/features/diary/domain/repositories/diary_repository_v2.dart';

void main() {
  sqfliteFfiInit();

  late DiaryDatabaseV2 databaseOwner;
  late SqliteDiaryRepositoryV2 repository;

  setUp(() async {
    databaseOwner = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => inMemoryDatabasePath,
    );
    repository = SqliteDiaryRepositoryV2(await databaseOwner.open());
  });

  tearDown(() async {
    await repository.dispose();
    await databaseOwner.close();
  });

  test(
    'saves and reads an entry without storage types in the entity',
    () async {
      final entry = _entry();

      await repository.save(entry);
      final stored = await repository.getById(entry.id);

      expect(stored?.body, entry.body);
      expect(stored?.tags, entry.tags);
      expect(stored?.location?.latitude, entry.location?.latitude);
      expect(stored?.imageIds, entry.imageIds);
    },
  );

  test('watchEntries emits again after an entry changes', () async {
    final emissions = repository.watchEntries().take(2).toList();

    await Future<void>.delayed(Duration.zero);
    await repository.save(_entry());

    final values = await emissions;
    expect(values.first, isEmpty);
    expect(values.last.single.id, 'entry-1');
  });

  test(
    'trash, restore, and permanent deletion are distinct operations',
    () async {
      final entry = _entry();
      await repository.save(entry);

      await repository.moveToTrash(
        entry.id,
        deletedAt: DateTime.utc(2026, 1, 3),
      );
      expect(await repository.watchEntries().first, isEmpty);
      expect(
        await repository
            .watchEntries(query: const DiaryQuery(onlyDeleted: true))
            .first,
        hasLength(1),
      );

      await repository.restore(entry.id);
      expect(await repository.watchEntries().first, hasLength(1));

      await repository.deletePermanently(entry.id);
      expect(await repository.getById(entry.id), isNull);
    },
  );

  test('filters by text, tags, and date range', () async {
    await repository.save(_entry());
    await repository.save(
      _entry(
        id: 'entry-2',
        body: 'A rainy afternoon',
        entryDate: DateTime.utc(2026, 2, 1),
        tags: const ['weather'],
      ),
    );

    final results = await repository
        .watchEntries(
          query: DiaryQuery(
            text: 'quiet',
            tags: const ['daily'],
            from: DateTime.utc(2026, 1, 1),
            to: DateTime.utc(2026, 2, 1),
          ),
        )
        .first;

    expect(results.map((entry) => entry.id), ['entry-1']);
  });

  test('favorites are persisted and can be queried', () async {
    await repository.save(_entry());

    await repository.setFavorite('entry-1', isFavorite: true);

    final stored = await repository.getById('entry-1');
    final favorites = await repository
        .watchEntries(query: const DiaryQuery(onlyFavorites: true))
        .first;
    expect(stored?.isFavorite, isTrue);
    expect(favorites.map((entry) => entry.id), ['entry-1']);

    await repository.setFavorite('entry-1', isFavorite: false);
    expect(
      await repository
          .watchEntries(query: const DiaryQuery(onlyFavorites: true))
          .first,
      isEmpty,
    );
  });
}

DiaryEntryV2 _entry({
  String id = 'entry-1',
  String body = 'A quiet morning',
  DateTime? entryDate,
  List<String> tags = const ['daily', 'calm'],
}) {
  final timestamp = DateTime.utc(2026, 1, 2, 8);
  return DiaryEntryV2(
    id: id,
    body: body,
    entryDate: entryDate ?? DateTime.utc(2026, 1, 2),
    createdAt: timestamp,
    updatedAt: timestamp,
    imageIds: const ['image-1'],
    mood: 'calm',
    tags: tags,
    location: const DiaryLocation(
      latitude: 22.3193,
      longitude: 114.1694,
      address: 'Hong Kong',
    ),
  );
}
