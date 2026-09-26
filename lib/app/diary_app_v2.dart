import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../features/diary/application/ports/diary_image_store_v2.dart';
import '../features/diary/application/legacy_migration_controller_v2.dart';
import '../features/diary/domain/repositories/diary_repository_v2.dart';
import '../features/diary/presentation/pages/diary_home_page_v2.dart';
import '../features/festival/data/public_holiday_service_v2.dart';
import '../features/festival/domain/festival_repository_v2.dart';
import '../features/export/application/backup_sqlite_snapshot_reader_v2.dart';
import '../features/settings/application/theme_controller_v2.dart';
import '../features/settings/application/app_lock_controller_v2.dart';
import '../features/settings/presentation/app_lock_gate_v2.dart';
import '../features/life_guide/domain/life_fragment_repository_v2.dart';
import '../features/life_library/domain/life_document_repository_v2.dart';
import '../features/self_engine/application/self_engine_job_recovery_v2.dart';
import '../features/self_engine/domain/repositories/self_engine_repository_v2.dart';
import '../features/self_engine/presentation/self_engine_recovery_scope_v2.dart';

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
    this.selfEngineRepository,
    this.selfEngineRecovery,
    this.backupSnapshotReader,
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
  final SelfEngineRepositoryV2? selfEngineRepository;
  final SelfEngineJobRecoveryV2? selfEngineRecovery;
  final BackupSqliteSnapshotReaderV2? backupSnapshotReader;
  final LegacyMigrationControllerV2? migrationController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        final home = AppLockGateV2(
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
            selfEngineRepository: selfEngineRepository,
            backupSnapshotReader: backupSnapshotReader,
            migrationController: migrationController,
          ),
        );
        return MaterialApp(
          title: '时光日记',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: FlutterQuillLocalizations.supportedLocales,
          themeMode: themeController.mode,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          home: selfEngineRecovery == null
              ? home
              : SelfEngineRecoveryScopeV2(
                  recovery: selfEngineRecovery!,
                  child: home,
                ),
        );
      },
    );
  }

  ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colors =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF202020),
          brightness: brightness,
        ).copyWith(
          primary: isDark ? const Color(0xFFF2F2F2) : const Color(0xFF171717),
          onPrimary: isDark ? const Color(0xFF171717) : Colors.white,
          secondary: isDark ? const Color(0xFFB8B8B8) : const Color(0xFF5F5F5F),
          onSecondary: isDark ? const Color(0xFF171717) : Colors.white,
          surface: isDark ? const Color(0xFF101010) : const Color(0xFFFCFCFB),
          surfaceContainerLowest: isDark
              ? const Color(0xFF101010)
              : const Color(0xFFFCFCFB),
          surfaceContainerLow: isDark
              ? const Color(0xFF151515)
              : const Color(0xFFF7F7F5),
          surfaceContainer: isDark
              ? const Color(0xFF1B1B1B)
              : const Color(0xFFF1F1EF),
          surfaceContainerHigh: isDark
              ? const Color(0xFF222222)
              : const Color(0xFFEAEAE7),
          outline: isDark ? const Color(0xFF777777) : const Color(0xFF777777),
          outlineVariant: isDark
              ? const Color(0xFF2C2C2C)
              : const Color(0xFFE3E3E0),
        );
    final baseTextTheme = ThemeData(
      brightness: brightness,
      fontFamily: 'MiSans',
    ).textTheme;
    return ThemeData(
      colorScheme: colors,
      brightness: brightness,
      useMaterial3: true,
      fontFamily: 'MiSans',
      scaffoldBackgroundColor: colors.surface,
      canvasColor: colors.surface,
      splashFactory: InkSparkle.splashFactory,
      textTheme: baseTextTheme.copyWith(
        displaySmall: baseTextTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -1.2,
          height: 1.12,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.7,
          height: 1.2,
        ),
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.35,
          height: 1.25,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(height: 1.7),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(height: 1.65),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
          height: 1.5,
        ),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: colors.onSurface,
          fontFamily: 'MiSans',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: colors.onSurface, size: 22),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.onSurface, width: 1),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 0.6,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        iconColor: colors.onSurfaceVariant,
        minLeadingWidth: 28,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.onSurface,
          minimumSize: const Size(44, 44),
          shape: const CircleBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.onSurface,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.onSurface,
          side: BorderSide(color: colors.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: colors.surfaceContainerHigh,
        disabledColor: Colors.transparent,
        side: BorderSide(color: colors.outlineVariant, width: 0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(color: colors.onSurface, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const CircleBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        elevation: 0,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? colors.onSurface : colors.onSurfaceVariant,
            size: 23,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? colors.onSurface : colors.onSurfaceVariant,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
    );
  }
}
