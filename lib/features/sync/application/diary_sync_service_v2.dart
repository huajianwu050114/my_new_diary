import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../diary/application/ports/diary_image_store_v2.dart';
import '../../diary/domain/entities/diary_entry.dart';
import '../../diary/domain/repositories/diary_repository_v2.dart';
import '../data/diary_sync_codec_v2.dart';
import '../domain/diary_sync_record_v2.dart';
import '../domain/diary_sync_result_v2.dart';
import '../domain/sync_storage_v2.dart';

class DiarySyncServiceV2 {
  DiarySyncServiceV2({
    required DiaryRepositoryV2 repository,
    required DiaryImageStoreV2 imageStore,
    DiarySyncCodecV2 codec = const DiarySyncCodecV2(),
  }) : _repository = repository,
       _imageStore = imageStore,
       _codec = codec;

  final DiaryRepositoryV2 _repository;
  final DiaryImageStoreV2 _imageStore;
  final DiarySyncCodecV2 _codec;

  Future<DiarySyncResultV2> synchronize(SyncStorageV2 store) async {
    if (!await store.isAvailable()) {
      throw const SyncStorageUnavailableException();
    }
    final state = _MutableResult();
    final localEntries = await _repository
        .watchEntries(query: const DiaryQuery(includeDeleted: true))
        .first;
    final localById = {for (final entry in localEntries) entry.id: entry};
    final remoteById = <String, DiarySyncRecordV2>{};

    final files = await store.listEntryFiles();
    for (final filename in files) {
      if (filename.endsWith('.tmp')) continue;
      if (filename.contains('.sync-conflict-')) {
        state.warnings.add(
          DiarySyncIssueV2(
            subject: filename,
            message: 'Syncthing conflict file ignored.',
          ),
        );
        continue;
      }
      if (!filename.endsWith('.json')) continue;
      try {
        final bytes = await store.readEntry(filename);
        if (bytes == null) continue;
        final record = _codec.decode(utf8.decode(bytes));
        if (filename != '${record.id}.json') {
          throw const DiarySyncFormatException(
            'Filename does not match the diary ID.',
          );
        }
        remoteById[record.id] = record;
      } catch (error) {
        state.errors.add(
          DiarySyncIssueV2(
            subject: filename,
            message: error.runtimeType.toString(),
          ),
        );
      }
    }

    final ids = {...localById.keys, ...remoteById.keys}.toList()..sort();
    for (final id in ids) {
      try {
        final local = localById[id];
        final remote = remoteById[id];
        if (local == null && remote != null) {
          if (remote.purged) {
            state.skipped++;
            continue;
          }
          await _repository.save(remote.toEntry());
          state.imported++;
          await _reconcileImages(remote, store, state);
          continue;
        }
        if (local != null && remote == null) {
          await _exportRecord(DiarySyncRecordV2.fromEntry(local), store, state);
          state.exported++;
          continue;
        }
        if (local == null || remote == null) continue;

        final localRecord = DiarySyncRecordV2.fromEntry(local);
        final comparison = remote.updatedAt.compareTo(local.updatedAt);
        if (comparison > 0) {
          await _applyRemote(remote, local, state);
          await _reconcileImages(remote, store, state);
          state.updated++;
        } else if (comparison < 0) {
          await _exportRecord(localRecord, store, state);
          state.exported++;
        } else {
          final localJson = _codec.encode(localRecord);
          final remoteJson = _codec.encode(remote);
          if (localJson == remoteJson) {
            state.skipped++;
            await _reconcileImages(localRecord, store, state);
          } else if (_digest(remoteJson).compareTo(_digest(localJson)) > 0) {
            await _applyRemote(remote, local, state);
            await _reconcileImages(remote, store, state);
            state.updated++;
          } else {
            await _exportRecord(localRecord, store, state);
            state.exported++;
          }
        }
      } catch (error) {
        state.errors.add(
          DiarySyncIssueV2(subject: id, message: error.runtimeType.toString()),
        );
      }
    }
    return state.freeze();
  }

  Future<void> exportEntry(SyncStorageV2 store, String diaryId) async {
    final entry = await _repository.getById(diaryId);
    if (entry == null) return;
    final state = _MutableResult();
    await _exportRecord(DiarySyncRecordV2.fromEntry(entry), store, state);
  }

  Future<void> exportPurge(
    SyncStorageV2 store, {
    required String diaryId,
    required DateTime deletedAt,
  }) async {
    await store.writeEntryAtomic(
      '$diaryId.json',
      Uint8List.fromList(
        utf8.encode(
          _codec.encode(
            DiarySyncRecordV2.purged(id: diaryId, updatedAt: deletedAt),
          ),
        ),
      ),
    );
  }

  Future<void> _applyRemote(
    DiarySyncRecordV2 remote,
    DiaryEntryV2 local,
    _MutableResult state,
  ) async {
    if (remote.purged) {
      await _repository.deletePermanently(local.id);
    } else {
      await _repository.save(remote.toEntry());
    }
  }

  Future<void> _exportRecord(
    DiarySyncRecordV2 record,
    SyncStorageV2 store,
    _MutableResult state,
  ) async {
    await _reconcileImages(record, store, state);
    await store.writeEntryAtomic(
      '${record.id}.json',
      Uint8List.fromList(utf8.encode(_codec.encode(record))),
    );
  }

  Future<void> _reconcileImages(
    DiarySyncRecordV2 record,
    SyncStorageV2 store,
    _MutableResult state,
  ) async {
    if (record.purged) return;
    final importer = _imageStore is DiaryImageImportStoreV2
        ? _imageStore as DiaryImageImportStoreV2
        : null;
    for (final imageId in record.imageIds) {
      try {
        final localBytes = await _imageStore.read(imageId);
        final remoteBytes = await store.readImage(imageId);
        if (localBytes != null) {
          if (await store.writeImageAtomic(imageId, localBytes)) {
            state.imagesExported++;
          }
        } else if (remoteBytes != null && importer != null) {
          await importer.import(imageId: imageId, bytes: remoteBytes);
          state.imagesImported++;
        } else if (remoteBytes == null) {
          state.warnings.add(
            DiarySyncIssueV2(
              subject: imageId,
              message: 'Referenced image has not arrived yet.',
            ),
          );
        } else {
          state.errors.add(
            DiarySyncIssueV2(
              subject: imageId,
              message: 'Local image store cannot preserve imported IDs.',
            ),
          );
        }
      } catch (error) {
        state.errors.add(
          DiarySyncIssueV2(
            subject: imageId,
            message: error.runtimeType.toString(),
          ),
        );
      }
    }
  }

  String _digest(String value) => sha256.convert(utf8.encode(value)).toString();
}

class _MutableResult {
  int imported = 0;
  int exported = 0;
  int updated = 0;
  int skipped = 0;
  int imagesImported = 0;
  int imagesExported = 0;
  final warnings = <DiarySyncIssueV2>[];
  final errors = <DiarySyncIssueV2>[];

  DiarySyncResultV2 freeze() => DiarySyncResultV2(
    imported: imported,
    exported: exported,
    updated: updated,
    skipped: skipped,
    imagesImported: imagesImported,
    imagesExported: imagesExported,
    warnings: List.unmodifiable(warnings),
    errors: List.unmodifiable(errors),
  );
}
