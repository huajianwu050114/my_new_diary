import 'package:flutter/material.dart';

import '../features/diary/application/ports/diary_image_store_v2.dart';
import '../features/diary/application/legacy_migration_controller_v2.dart';
import '../features/diary/domain/repositories/diary_repository_v2.dart';
import '../features/diary/presentation/pages/diary_home_page_v2.dart';
import '../features/festival/data/public_holiday_service_v2.dart';
import '../features/festival/domain/festival_repository_v2.dart';
import '../features/settings/application/theme_controller_v2.dart';
import '../features/settings/application/app_lock_controller_v2.dart';
import '../features/settings/presentation/app_lock_gate_v2.dart';
import '../features/life_guide/domain/life_fragment_repository_v2.dart';
import '../features/life_library/domain/life_document_repository_v2.dart';

class DiaryAppV2 extends StatelessWidget {
  const DiaryAppV2({
    required this.repository,
    required this.imageStore,
    required this.festivalRepository,
    required this.publicHolidayService,
    required this.themeController,
    required this.appLockController,
    this.lifeFragmentRepository,
    this.lifeDocumentRepository,
    this.migrationController,
    super.key,
  });

  final DiaryRepositoryV2 repository;
  final DiaryImageStoreV2 imageStore;
  final FestivalRepositoryV2 festivalRepository;
  final PublicHolidayServiceV2 publicHolidayService;
  final ThemeControllerV2 themeController;
  final AppLockControllerV2 appLockController;
  final LifeFragmentRepositoryV2? lifeFragmentRepository;
  final LifeDocumentRepositoryV2? lifeDocumentRepository;
  final LegacyMigrationControllerV2? migrationController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => MaterialApp(
        title: '时光日记',
        debugShowCheckedModeBanner: false,
        themeMode: themeController.mode,
        theme: _theme(Brightness.light, themeController.palette),
        darkTheme: _theme(Brightness.dark, themeController.palette),
        home: AppLockGateV2(
          controller: appLockController,
          child: DiaryHomePageV2(
            repository: repository,
            imageStore: imageStore,
            festivalRepository: festivalRepository,
            publicHolidayService: publicHolidayService,
            themeController: themeController,
            appLockController: appLockController,
            lifeFragmentRepository: lifeFragmentRepository,
            lifeDocumentRepository: lifeDocumentRepository,
            migrationController: migrationController,
          ),
        ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness, AppPaletteV2 palette) {
    final colors = ColorScheme.fromSeed(
      seedColor: palette.seedColor,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colors,
      brightness: brightness,
      useMaterial3: true,
      fontFamily: 'MiSans',
      scaffoldBackgroundColor: brightness == Brightness.light
          ? palette.lightBackground
          : palette.darkBackground,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
