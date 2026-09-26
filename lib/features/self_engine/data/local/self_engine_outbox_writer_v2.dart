import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../diary/domain/entities/diary_entry.dart';
import '../../domain/diary_source_fingerprint_v2.dart';
import 'self_engine_schema_v2.dart';

class SelfEngineOutboxWriterV2 {
  SelfEngineOutboxWriterV2({
    DateTime Function()? clock,
    String Function()? createId,
  }) : _clock = clock ?? DateTime.now,
       _createId = createId ?? const Uuid().v4;

  final DateTime Function() _clock;
  final String Function() _createId;

  Future<bool> recordSourceChange(
    DatabaseExecutor database,
    DiaryEntryV2 entry,
  ) async {
    final sourceHash = DiarySourceFingerprintV2.calculate(entry);
    final latest = await database.query(
      'diary_revisions',
      columns: const ['source_hash', 'revision_no'],
      where: 'diary_id = ?',
      whereArgs: [entry.id],
      orderBy: 'revision_no DESC',
      limit: 1,
    );
    if (latest.isNotEmpty && latest.single['source_hash'] == sourceHash) {
      return false;
    }

    final revisionId = _createId();
    final revisionNo = latest.isEmpty
        ? 1
        : (latest.single['revision_no']! as int) + 1;
    final now = _clock().toUtc().toIso8601String();
    const fingerprintVersion = DiarySourceFingerprintV2.version;
    await database.insert('diary_revisions', {
      'id': revisionId,
      'diary_id': entry.id,
      'revision_no': revisionNo,
      'body': entry.body,
      'content_delta': entry.contentDelta,
      'source_hash': sourceHash,
      'fingerprint_version': fingerprintVersion,
      'entry_date': entry.entryDate.toUtc().toIso8601String(),
      'mood': entry.mood,
      'tags': jsonEncode(entry.tags),
      'latitude': entry.location?.latitude,
      'longitude': entry.location?.longitude,
      'address': entry.location?.address,
      'created_at': now,
    });
    const jobType = 'sourceChanged';
    const pipelineVersion = SelfEngineSchemaV2.pipelineVersion;
    final computationId =
        'fp$fingerprintVersion-p$pipelineVersion-$jobType-$sourceHash';
    await database.insert('self_engine_computations', {
      'id': computationId,
      'source_hash': sourceHash,
      'fingerprint_version': fingerprintVersion,
      'pipeline_version': pipelineVersion,
      'job_type': jobType,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final state = await database.query(
      'self_engine_state',
      columns: const ['generation'],
      where: 'id = 1',
      limit: 1,
    );
    if (state.length != 1) {
      throw StateError('Self Engine generation state is missing.');
    }
    await database.insert('self_engine_jobs', {
      'id': _createId(),
      'revision_id': revisionId,
      'computation_id': computationId,
      'source_hash': sourceHash,
      'fingerprint_version': fingerprintVersion,
      'job_type': jobType,
      'status': 'pending',
      'attempt_count': 0,
      'pipeline_version': pipelineVersion,
      'generation': state.single['generation']! as int,
      'created_at': now,
      'updated_at': now,
    });
    return true;
  }
}
