import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../application/ports/diary_image_store_v2.dart';
import '../../domain/entities/diary_entry.dart';
import '../../domain/repositories/diary_repository_v2.dart';

class LegacyDiaryMigratorV2 {
  const LegacyDiaryMigratorV2({
    required this.repository,
    required this.imageStore,
    required this.databaseFactory,
  });

  final DiaryRepositoryV2 repository;
  final DiaryImageStoreV2 imageStore;
  final DatabaseFactory databaseFactory;

  Future<MigrationReportV2> migrate({
    required String sqlitePath,
    required Directory jsonDirectory,
    required List<Directory> legacyImageDirectories,
  }) async {
    var report = const MigrationReportV2();

    if (await File(sqlitePath).exists()) {
      report += await _migrateSqlite(sqlitePath, legacyImageDirectories);
    }
    if (await jsonDirectory.exists()) {
      report += await _migrateJson(jsonDirectory, legacyImageDirectories);
    }
    return report;
  }

  Future<MigrationReportV2> _migrateSqlite(
    String sqlitePath,
    List<Directory> imageDirectories,
  ) async {
    final database = await databaseFactory.openDatabase(
      sqlitePath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        ['diaries'],
      );
      if (tables.isEmpty) {
        return const MigrationReportV2();
      }

      var report = const MigrationReportV2();
      final rows = await database.query('diaries');
      for (final row in rows) {
        report += await _import(
          sourceId: 'sqlite:${row['diaryId']}',
          values: row,
          imageValues: _stringList(row['imagePaths']),
          imageDirectories: imageDirectories,
        );
      }
      return report;
    } finally {
      await database.close();
    }
  }

  Future<MigrationReportV2> _migrateJson(
    Directory directory,
    List<Directory> imageDirectories,
  ) async {
    var report = const MigrationReportV2();
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File ||
          path.extension(entity.path).toLowerCase() != '.json') {
        continue;
      }
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map<String, dynamic>) {
          report += const MigrationReportV2(discovered: 1, failed: 1);
          continue;
        }
        report += await _import(
          sourceId: 'json:${path.normalize(entity.absolute.path)}',
          values: decoded,
          imageValues: _stringList(
            decoded['imagePaths'] ?? decoded['imagePath'],
          ),
          imageDirectories: imageDirectories,
        );
      } catch (_) {
        report += const MigrationReportV2(discovered: 1, failed: 1);
      }
    }
    return report;
  }

  Future<MigrationReportV2> _import({
    required String sourceId,
    required Map<String, Object?> values,
    required List<String> imageValues,
    required List<Directory> imageDirectories,
  }) async {
    final id = const Uuid().v5(Namespace.url.value, sourceId);
    if (await repository.getById(id) != null) {
      return const MigrationReportV2(discovered: 1, skipped: 1);
    }

    final importedImageIds = <String>[];
    try {
      for (final value in imageValues) {
        final source = await _findImage(value, imageDirectories);
        if (source == null) {
          continue;
        }
        importedImageIds.add(
          await imageStore.save(
            bytes: await source.readAsBytes(),
            extension: path.extension(source.path),
          ),
        );
      }

      final entryDate = _date(values['date']);
      final createdAt = _date(values['creationTime'], fallback: entryDate);
      final isDeleted = values['isDeleted'] == true || values['isDeleted'] == 1;
      await repository.save(
        DiaryEntryV2(
          id: id,
          body: values['text'] as String? ?? '',
          entryDate: entryDate,
          createdAt: createdAt,
          updatedAt: createdAt,
          imageIds: importedImageIds,
          mood: values['mood'] as String?,
          tags: _stringList(values['tags']),
          location: _location(values),
          aiAnalyses: _stringList(values['aiAnalyses']),
          deletedAt: isDeleted ? createdAt : null,
        ),
      );
      return const MigrationReportV2(discovered: 1, imported: 1);
    } catch (_) {
      for (final imageId in importedImageIds) {
        await imageStore.delete(imageId);
      }
      return const MigrationReportV2(discovered: 1, failed: 1);
    }
  }

  Future<File?> _findImage(
    String value,
    List<Directory> imageDirectories,
  ) async {
    final direct = File(value);
    if (path.isAbsolute(value) && await direct.exists()) {
      return direct;
    }
    final name = path.basename(value);
    for (final directory in imageDirectories) {
      final candidate = File(path.join(directory.path, name));
      if (await candidate.exists()) {
        return candidate;
      }
    }
    return null;
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.whereType<String>().toList(growable: false);
        }
      } catch (_) {
        return [value];
      }
    }
    return const [];
  }

  DateTime _date(Object? value, {DateTime? fallback}) {
    if (value is String) {
      return DateTime.tryParse(value) ?? fallback ?? DateTime.now().toUtc();
    }
    return fallback ?? DateTime.now().toUtc();
  }

  DiaryLocation? _location(Map<String, Object?> values) {
    final latitude = values['latitude'];
    final longitude = values['longitude'];
    if (latitude is! num || longitude is! num) {
      return null;
    }
    return DiaryLocation(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      address: values['address'] as String?,
    );
  }
}

class MigrationReportV2 {
  const MigrationReportV2({
    this.discovered = 0,
    this.imported = 0,
    this.skipped = 0,
    this.failed = 0,
  });

  final int discovered;
  final int imported;
  final int skipped;
  final int failed;

  MigrationReportV2 operator +(MigrationReportV2 other) {
    return MigrationReportV2(
      discovered: discovered + other.discovered,
      imported: imported + other.imported,
      skipped: skipped + other.skipped,
      failed: failed + other.failed,
    );
  }
}
