import 'dart:async';

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
import 'features/ai/data/ai_configuration_store_v2.dart';
import 'features/ai/data/gemini_rest_client_v2.dart';
import 'features/festival/data/public_holiday_service_v2.dart';
import 'features/festival/data/sqlite_festival_repository_v2.dart';
import 'features/export/application/backup_sqlite_snapshot_reader_v2.dart';
import 'features/settings/application/theme_controller_v2.dart';
import 'features/settings/application/app_lock_controller_v2.dart';
import 'features/life_guide/data/sqlite_life_fragment_repository_v2.dart';
import 'features/life_library/data/sqlite_life_document_repository_v2.dart';
import 'features/self_engine/application/self_engine_job_recovery_v2.dart';
import 'features/self_engine/application/configured_self_engine_availability_v2.dart';
import 'features/self_engine/application/memory_atom_job_processor_v2.dart';
import 'features/self_engine/application/memory_thread_link_job_processor_v2.dart';
import 'features/self_engine/application/ports/self_engine_runner_v2.dart';
import 'features/self_engine/application/self_engine_pipeline_runner_v2.dart';
import 'features/self_engine/application/self_engine_worker_v2.dart';
import 'features/self_engine/application/thread_link_worker_v2.dart';
import 'features/self_engine/data/ai/ai_memory_extractor_v2.dart';
import 'features/self_engine/data/ai/ai_memory_thread_linker_v2.dart';
import 'features/self_engine/data/local/sqlite_memory_thread_candidate_retriever_v2.dart';
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
  final selfEngineRepository = SqliteSelfEngineRepositoryV2(database);
  final aiConfigurationStore = AiConfigurationStoreV2();
  final aiClient = GeminiRestClientV2(configurationStore: aiConfigurationStore);
  final selfEngineAvailability = ConfiguredSelfEngineAvailabilityV2(
    aiConfigurationStore,
  );
  const selfEngineLeaseDuration = Duration(minutes: 5);
  final extractionWorker = SelfEngineWorkerV2(
    repository: selfEngineRepository,
    processor: MemoryAtomJobProcessorV2(
      repository: selfEngineRepository,
      extractor: AiMemoryExtractorV2(aiClient),
      leaseDuration: selfEngineLeaseDuration,
    ),
    availability: selfEngineAvailability,
    leaseDuration: selfEngineLeaseDuration,
  );
  final threadLinkWorker = ThreadLinkWorkerV2(
    repository: selfEngineRepository,
    processor: MemoryThreadLinkJobProcessorV2(
      repository: selfEngineRepository,
      candidateRetriever: SqliteMemoryThreadCandidateRetrieverV2(database),
      linker: AiMemoryThreadLinkerV2(aiClient),
      leaseDuration: selfEngineLeaseDuration,
    ),
    availability: selfEngineAvailability,
    leaseDuration: selfEngineLeaseDuration,
  );
  final selfEngineRunner = SelfEnginePipelineRunnerV2(
    extractionRunner: extractionWorker,
    threadLinkRunner: threadLinkWorker,
  );
  void scheduleSelfEngineWork() {
    unawaited(
      selfEngineRunner.runOnce().catchError((Object error) {
        debugPrint('Self Engine worker could not run: $error');
        return SelfEngineRunResultV2.ownershipLost;
      }),
    );
  }

  final repository = SqliteDiaryRepositoryV2(
    database,
    onSourceSaved: scheduleSelfEngineWork,
  );
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
  final selfEngineRecovery = SelfEngineJobRecoveryV2(selfEngineRepository);
  try {
    await selfEngineRecovery.afterColdStart();
    await selfEngineRecovery.reconcileLegacyDiaries();
    await selfEngineRecovery.reconcileThreadLinkJobs();
  } catch (error) {
    debugPrint('Self Engine job recovery could not run: $error');
  }
  scheduleSelfEngineWork();
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
      selfEngineRunner: selfEngineRunner,
      backupSnapshotReader: BackupSqliteSnapshotReaderV2(database),
      publicHolidayService: PublicHolidayServiceV2(),
      themeController: themeController,
      appLockController: appLockController,
      migrationController: migrationController,
    ),
  );
}
