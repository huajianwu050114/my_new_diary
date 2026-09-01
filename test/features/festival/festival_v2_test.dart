import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:my_new_diary/features/diary/data/local/diary_database_v2.dart';
import 'package:my_new_diary/features/festival/data/public_holiday_service_v2.dart';
import 'package:my_new_diary/features/festival/data/sqlite_festival_repository_v2.dart';
import 'package:my_new_diary/features/festival/domain/festival_v2.dart';

void main() {
  sqfliteFfiInit();

  test(
    'custom festivals persist and calculate their next occurrence',
    () async {
      final databaseOwner = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => inMemoryDatabasePath,
      );
      final repository = SqliteFestivalRepositoryV2(await databaseOwner.open());
      final festival = CustomFestivalV2(
        id: 'festival-1',
        name: 'Anniversary',
        month: 2,
        day: 14,
        createdAt: DateTime.utc(2026),
      );

      await repository.save(festival);
      final stored = await repository.watchCustomFestivals().first;

      expect(stored.single.name, 'Anniversary');
      expect(
        stored.single.nextOccurrence(DateTime(2026, 3, 1)),
        DateTime(2027, 2, 14),
      );

      await repository.delete(festival.id);
      expect(await repository.watchCustomFestivals().first, isEmpty);
      await repository.dispose();
      await databaseOwner.close();
    },
  );

  test('public holidays are cached for offline reuse', () async {
    SharedPreferences.setMockInitialValues({});
    final online = PublicHolidayServiceV2(
      client: MockClient(
        (_) async => http.Response(
          '[{"date":"2026-10-01","localName":"National Day",'
          '"name":"National Day"}]',
          200,
        ),
      ),
    );

    final first = await online.loadYear(2026);
    final offline = PublicHolidayServiceV2(
      client: MockClient((_) async => throw Exception('offline')),
    );
    final cached = await offline.loadYear(2026);

    expect(first.single.name, 'National Day');
    expect(cached.single.date, DateTime(2026, 10, 1));
  });
}
