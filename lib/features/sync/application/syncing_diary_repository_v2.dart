import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../diary/domain/entities/diary_entry.dart';
import '../../diary/domain/repositories/diary_repository_v2.dart';
import '../data/sync_directory_provider_v2.dart';
import '../domain/sync_storage_v2.dart';
import 'diary_sync_service_v2.dart';

class SyncingDiaryRepositoryV2 implements DiaryRepositoryV2 {
  SyncingDiaryRepositoryV2({
    required DiaryRepositoryV2 local,
    required DiarySyncServiceV2 syncService,
    required SyncDirectoryProviderV2 directoryProvider,
  }) : _local = local,
       _syncService = syncService,
       _directoryProvider = directoryProvider;

  final DiaryRepositoryV2 _local;
  final DiarySyncServiceV2 _syncService;
  final SyncDirectoryProviderV2 _directoryProvider;

  @override
  Future<DiaryEntryV2?> getById(String id) => _local.getById(id);

  @override
  Stream<List<DiaryEntryV2>> watchEntries({
    DiaryQuery query = const DiaryQuery(),
  }) => _local.watchEntries(query: query);

  @override
  Future<void> save(DiaryEntryV2 entry) async {
    await _local.save(entry);
    await _bestEffortExport(entry.id);
  }

  @override
  Future<void> restoreFromBackup(DiaryEntryV2 entry) async {
    await _local.restoreFromBackup(entry);
    await _bestEffortExport(entry.id);
  }

  @override
  Future<void> moveToTrash(String id, {required DateTime deletedAt}) async {
    await _local.moveToTrash(id, deletedAt: deletedAt);
    await _bestEffortExport(id);
  }

  @override
  Future<void> restore(String id) async {
    await _local.restore(id);
    await _bestEffortExport(id);
  }

  @override
  Future<void> setFavorite(String id, {required bool isFavorite}) async {
    await _local.setFavorite(id, isFavorite: isFavorite);
    await _bestEffortExport(id);
  }

  @override
  Future<void> deletePermanently(String id) async {
    final now = DateTime.now().toUtc();
    await _local.deletePermanently(id);
    await _bestEffort((storage) {
      return _syncService.exportPurge(storage, diaryId: id, deletedAt: now);
    }, id);
  }

  Future<void> _bestEffortExport(String id) {
    return _bestEffort((storage) => _syncService.exportEntry(storage, id), id);
  }

  Future<void> _bestEffort(
    Future<void> Function(SyncStorageV2 storage) action,
    String diaryId,
  ) async {
    try {
      final location = (await _directoryProvider.load()).location;
      if (location != null) {
        await action(_directoryProvider.storageFor(location));
      }
    } catch (error) {
      debugPrint(
        'Diary sync export failed for $diaryId (${error.runtimeType}).',
      );
    }
  }
}
