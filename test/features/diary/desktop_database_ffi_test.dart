import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/diary/data/local/diary_database_v2.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('desktop FFI opens the diary schema and executes a query', () async {
    sqfliteFfiInit();
    final databaseOwner = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => inMemoryDatabasePath,
    );

    final database = await databaseOwner.open();
    final rows = await database.rawQuery(
      'SELECT * FROM diary_entries ORDER BY entry_date DESC, created_at DESC',
    );

    expect(rows, isEmpty);
    await databaseOwner.close();
  });
}
