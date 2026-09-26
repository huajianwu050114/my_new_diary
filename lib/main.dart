import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app/diary_app_v2.dart';
import 'features/diary/data/local/diary_database_v2.dart';
import 'features/diary/data/local/local_diary_image_store_v2.dart';
import 'features/diary/data/local/sqlite_diary_repository_v2.dart';
import 'features/diary/data/migration/legacy_diary_migrator_v2.dart';
import 'features/diary/application/legacy_migration_controller_v2.dart';
import 'features/festival/data/public_holiday_service_v2.dart';
import 'features/festival/data/sqlite_festival_repository_v2.dart';
import 'features/export/application/backup_sqlite_snapshot_reader_v2.dart';
import 'features/settings/application/theme_controller_v2.dart';
import 'features/settings/application/app_lock_controller_v2.dart';
import 'features/life_guide/data/sqlite_life_fragment_repository_v2.dart';
import 'features/life_library/data/sqlite_life_document_repository_v2.dart';
import 'features/self_engine/application/self_engine_job_recovery_v2.dart';
import 'features/self_engine/data/local/sqlite_self_engine_repository_v2.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final databaseOwner = DiaryDatabaseV2();
  final database = await databaseOwner.open();
  final repository = SqliteDiaryRepositoryV2(database);
  final imageStore = LocalDiaryImageStoreV2();

  final migrationController = LegacyMigrationControllerV2(
    LegacyDiaryMigratorV2(
      repository: repository,
      imageStore: imageStore,
      databaseFactory: databaseFactory,
    ),
  );
  await migrationController.load();
  try {
    await migrationController.run();
  } catch (error) {
    debugPrint('Legacy diary migration could not run: $error');
  }

  final festivalRepository = SqliteFestivalRepositoryV2(database);
  final lifeFragmentRepository = SqliteLifeFragmentRepositoryV2(database);
  final lifeDocumentRepository = SqliteLifeDocumentRepositoryV2(database);
  final selfEngineRepository = SqliteSelfEngineRepositoryV2(database);
  final selfEngineRecovery = SelfEngineJobRecoveryV2(selfEngineRepository);
  try {
    await selfEngineRecovery.afterColdStart();
    await selfEngineRecovery.reconcileLegacyDiaries();
  } catch (error) {
    debugPrint('Self Engine job recovery could not run: $error');
  }
  final themeController = ThemeControllerV2();
  await themeController.load();
  final appLockController = AppLockControllerV2();
  await appLockController.load();
  runApp(
    DiaryAppV2(
      repository: repository,
      imageStore: imageStore,
      festivalRepository: festivalRepository,
      lifeFragmentRepository: lifeFragmentRepository,
      lifeDocumentRepository: lifeDocumentRepository,
      selfEngineRepository: selfEngineRepository,
      selfEngineRecovery: selfEngineRecovery,
      backupSnapshotReader: BackupSqliteSnapshotReaderV2(database),
      publicHolidayService: PublicHolidayServiceV2(),
      themeController: themeController,
      appLockController: appLockController,
      migrationController: migrationController,
    ),
  );
}
