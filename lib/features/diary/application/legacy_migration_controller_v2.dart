import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../data/migration/legacy_diary_migrator_v2.dart';

class LegacyMigrationControllerV2 extends ChangeNotifier {
  LegacyMigrationControllerV2(this._migrator);

  static const _completedAtKey = 'v2_migration_completed_at';
  static const _discoveredKey = 'v2_migration_discovered';
  static const _importedKey = 'v2_migration_imported';
  static const _skippedKey = 'v2_migration_skipped';
  static const _failedKey = 'v2_migration_failed';

  final LegacyDiaryMigratorV2 _migrator;
  MigrationRunV2? _lastRun;
  bool _running = false;

  MigrationRunV2? get lastRun => _lastRun;
  bool get running => _running;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final completedAt = DateTime.tryParse(
      preferences.getString(_completedAtKey) ?? '',
    );
    if (completedAt != null) {
      _lastRun = MigrationRunV2(
        completedAt: completedAt,
        report: MigrationReportV2(
          discovered: preferences.getInt(_discoveredKey) ?? 0,
          imported: preferences.getInt(_importedKey) ?? 0,
          skipped: preferences.getInt(_skippedKey) ?? 0,
          failed: preferences.getInt(_failedKey) ?? 0,
        ),
      );
    }
    notifyListeners();
  }

  Future<MigrationReportV2> run() async {
    if (_running) {
      return _lastRun?.report ?? const MigrationReportV2();
    }
    _running = true;
    notifyListeners();
    try {
      final documents = await getApplicationDocumentsDirectory();
      final report = await _migrator.migrate(
        sqlitePath: path.join(await getDatabasesPath(), 'diary.db'),
        jsonDirectory: Directory(path.join(documents.path, 'diaries')),
        legacyImageDirectories: [
          Directory(path.join(documents.path, 'diary_images')),
          Directory(path.join(documents.path, 'images')),
        ],
      );
      final run = MigrationRunV2(
        completedAt: DateTime.now().toUtc(),
        report: report,
      );
      _lastRun = run;
      await _save(run);
      return report;
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<void> _save(MigrationRunV2 run) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _completedAtKey,
      run.completedAt.toIso8601String(),
    );
    await preferences.setInt(_discoveredKey, run.report.discovered);
    await preferences.setInt(_importedKey, run.report.imported);
    await preferences.setInt(_skippedKey, run.report.skipped);
    await preferences.setInt(_failedKey, run.report.failed);
  }
}

class MigrationRunV2 {
  const MigrationRunV2({required this.completedAt, required this.report});

  final DateTime completedAt;
  final MigrationReportV2 report;
}
