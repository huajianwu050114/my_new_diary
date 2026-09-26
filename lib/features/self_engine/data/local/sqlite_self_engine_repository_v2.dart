import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../diary/data/local/diary_entry_mapper_v2.dart';
import '../../domain/diary_source_fingerprint_v2.dart';
import '../../domain/entities/diary_revision_v2.dart';
import '../../domain/entities/self_engine_derived_result_v2.dart';
import '../../domain/entities/self_engine_job_v2.dart';
import '../../domain/repositories/self_engine_repository_v2.dart';
import '../../domain/self_engine_retry_policy_v2.dart';
import 'self_engine_outbox_writer_v2.dart';
import 'self_engine_schema_v2.dart';

class SqliteSelfEngineRepositoryV2 implements SelfEngineRepositoryV2 {
  SqliteSelfEngineRepositoryV2(
    this._database, {
    SelfEngineRetryPolicyV2 retryPolicy = const SelfEngineRetryPolicyV2(),
    String Function()? createId,
    SelfEngineOutboxWriterV2? outbox,
  }) : _retryPolicy = retryPolicy,
       _createId = createId ?? const Uuid().v4,
       _outbox = outbox ?? SelfEngineOutboxWriterV2();

  final Database _database;
  final SelfEngineRetryPolicyV2 _retryPolicy;
  final String Function() _createId;
  final SelfEngineOutboxWriterV2 _outbox;
  static const _diaryMapper = DiaryEntryMapperV2();

  @override
  Future<DiaryRevisionV2?> getLatestRevision(String diaryId) async {
    final rows = await _database.query(
      'diary_revisions',
      where: 'diary_id = ?',
      whereArgs: [diaryId],
      orderBy: 'revision_no DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _revisionFromRow(rows.single);
  }

  @override
  Future<List<DiaryRevisionV2>> getAllRevisions() async {
    final rows = await _database.query(
      'diary_revisions',
      orderBy: 'diary_id ASC, revision_no ASC',
    );
    return rows.map(_revisionFromRow).toList(growable: false);
  }

  @override
  Future<List<DiaryRevisionV2>> getRevisionsForDiary(String diaryId) async {
    final rows = await _database.query(
      'diary_revisions',
      where: 'diary_id = ?',
      whereArgs: [diaryId],
      orderBy: 'revision_no ASC',
    );
    return rows.map(_revisionFromRow).toList(growable: false);
  }

  @override
  Future<void> restoreRevision(DiaryRevisionV2 revision) {
    return _database.transaction((transaction) async {
      await _restoreRevision(transaction, revision);
    });
  }

  @override
  Future<void> restoreRevisionsForDiary(
    String diaryId,
    List<DiaryRevisionV2> revisions,
  ) {
    return _database.transaction((transaction) async {
      final ordered = [...revisions]
        ..sort((a, b) => a.revisionNo.compareTo(b.revisionNo));
      for (final revision in ordered) {
        if (revision.diaryId != diaryId) {
          throw StateError(
            'Revision ${revision.id} belongs to ${revision.diaryId}, not $diaryId.',
          );
        }
        await _restoreRevision(transaction, revision);
      }
    });
  }

  Future<void> _restoreRevision(
    DatabaseExecutor database,
    DiaryRevisionV2 revision,
  ) async {
    _validateRevisionFingerprint(revision);
    final byId = await database.query(
      'diary_revisions',
      where: 'id = ?',
      whereArgs: [revision.id],
      limit: 1,
    );
    if (byId.isNotEmpty) {
      if (!_sameRevision(_revisionFromRow(byId.single), revision)) {
        throw StateError('Revision ID ${revision.id} has conflicting content.');
      }
      await _ensureWork(database, revision);
      return;
    }
    final numberCollision = await database.query(
      'diary_revisions',
      columns: const ['id'],
      where: 'diary_id = ? AND revision_no = ?',
      whereArgs: [revision.diaryId, revision.revisionNo],
      limit: 1,
    );
    if (numberCollision.isNotEmpty) {
      throw StateError(
        'Revision number ${revision.revisionNo} for ${revision.diaryId} conflicts '
        'with ${numberCollision.single['id']}.',
      );
    }
    await database.insert('diary_revisions', _revisionToRow(revision));
    await _ensureWork(database, revision);
  }

  void _validateRevisionFingerprint(DiaryRevisionV2 revision) {
    if (revision.fingerprintVersion != DiarySourceFingerprintV2.version ||
        DiarySourceFingerprintV2.calculateRevision(revision) !=
            revision.sourceHash) {
      throw StateError('Revision ${revision.id} has an invalid source hash.');
    }
  }

  Future<void> _ensureWork(
    DatabaseExecutor database,
    DiaryRevisionV2 revision,
  ) async {
    const type = SelfEngineJobTypeV2.sourceChanged;
    const pipeline = SelfEngineSchemaV2.pipelineVersion;
    final computationId = _computationId(
      revision.sourceHash,
      revision.fingerprintVersion,
      pipeline,
      type.name,
    );
    await database.insert('self_engine_computations', {
      'id': computationId,
      'source_hash': revision.sourceHash,
      'fingerprint_version': revision.fingerprintVersion,
      'pipeline_version': pipeline,
      'job_type': type.name,
      'created_at': revision.createdAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final generation = await _generation(database);
    await database.insert('self_engine_jobs', {
      'id': '${revision.id}-p$pipeline-${type.name}',
      'revision_id': revision.id,
      'computation_id': computationId,
      'source_hash': revision.sourceHash,
      'fingerprint_version': revision.fingerprintVersion,
      'job_type': type.name,
      'status': SelfEngineJobStatusV2.pending.name,
      'attempt_count': 0,
      'pipeline_version': pipeline,
      'generation': generation,
      'created_at': revision.createdAt.toUtc().toIso8601String(),
      'updated_at': revision.createdAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final rows = await database.query(
      'self_engine_jobs',
      where: 'revision_id = ? AND pipeline_version = ? AND job_type = ?',
      whereArgs: [revision.id, pipeline, type.name],
      limit: 1,
    );
    if (rows.length != 1 ||
        rows.single['computation_id'] != computationId ||
        rows.single['source_hash'] != revision.sourceHash) {
      throw StateError(
        'Revision ${revision.id} has conflicting work identity.',
      );
    }
  }

  @override
  Future<List<SelfEngineJobV2>> getJobs({SelfEngineJobStatusV2? status}) async {
    final rows = await _database.rawQuery('''
      SELECT j.*, r.diary_id
      FROM self_engine_jobs j
      JOIN diary_revisions r ON r.id = j.revision_id
      ${status == null ? '' : 'WHERE j.status = ?'}
      ORDER BY j.created_at ASC
      ''', status == null ? null : [status.name]);
    return rows.map(_jobFromRow).toList(growable: false);
  }

  @override
  Future<SelfEngineJobV2?> claimNextJob({
    required DateTime now,
    Duration leaseDuration = const Duration(minutes: 5),
  }) async {
    if (leaseDuration <= Duration.zero) {
      throw ArgumentError.value(leaseDuration, 'leaseDuration');
    }
    await recoverExpiredLeases(now: now);
    return _database.transaction((transaction) async {
      final timestamp = now.toUtc().toIso8601String();
      final rows = await transaction.rawQuery(
        '''
        SELECT j.*, r.diary_id
        FROM self_engine_jobs j
        JOIN diary_revisions r ON r.id = j.revision_id
        WHERE j.attempt_count < ?
          AND (
            j.status = 'pending'
            OR (j.status = 'retryable' AND j.next_retry_at <= ?)
          )
        ORDER BY
          CASE WHEN j.status = 'pending' THEN 0 ELSE 1 END,
          COALESCE(j.next_retry_at, j.created_at),
          j.created_at
        LIMIT 1
        ''',
        [_retryPolicy.maxAttempts, timestamp],
      );
      if (rows.isEmpty) return null;
      final id = rows.single['id']! as String;
      final leaseId = _createId();
      final leaseExpiresAt = now.toUtc().add(leaseDuration).toIso8601String();
      final changed = await transaction.update(
        'self_engine_jobs',
        {
          'status': SelfEngineJobStatusV2.processing.name,
          'attempt_count': (rows.single['attempt_count']! as int) + 1,
          'updated_at': timestamp,
          'next_retry_at': null,
          'error': null,
          'lease_id': leaseId,
          'lease_expires_at': leaseExpiresAt,
        },
        where: '''
          id = ? AND attempt_count = ? AND (
            status = 'pending'
            OR (status = 'retryable' AND next_retry_at <= ?)
          )
        ''',
        whereArgs: [id, rows.single['attempt_count'], timestamp],
      );
      if (changed != 1) return null;
      final claimed = (await transaction.rawQuery(
        '''
        SELECT j.*, r.diary_id
        FROM self_engine_jobs j
        JOIN diary_revisions r ON r.id = j.revision_id
        WHERE j.id = ?
        ''',
        [id],
      )).single;
      return _jobFromRow(claimed);
    });
  }

  @override
  Future<bool> renewLease(
    String id, {
    required String leaseId,
    required DateTime now,
    Duration leaseDuration = const Duration(minutes: 5),
  }) async {
    if (leaseDuration <= Duration.zero) {
      throw ArgumentError.value(leaseDuration, 'leaseDuration');
    }
    final timestamp = now.toUtc().toIso8601String();
    final changed = await _database.update(
      'self_engine_jobs',
      {
        'updated_at': timestamp,
        'lease_expires_at': now.toUtc().add(leaseDuration).toIso8601String(),
      },
      where: '''
        id = ? AND status = 'processing' AND lease_id = ?
        AND lease_expires_at > ?
      ''',
      whereArgs: [id, leaseId, timestamp],
    );
    return changed == 1;
  }

  @override
  Future<bool> publishResult(
    String jobId, {
    required String leaseId,
    required DateTime publishedAt,
    required SelfEngineDerivedResultV2 result,
  }) {
    return _database.transaction((transaction) async {
      final timestamp = publishedAt.toUtc().toIso8601String();
      final rows = await transaction.rawQuery(
        '''
        SELECT j.*, s.generation AS current_generation
        FROM self_engine_jobs j
        JOIN diary_revisions r
          ON r.id = j.revision_id
         AND r.source_hash = j.source_hash
         AND r.fingerprint_version = j.fingerprint_version
        JOIN self_engine_computations c
          ON c.id = j.computation_id
         AND c.source_hash = j.source_hash
         AND c.fingerprint_version = j.fingerprint_version
         AND c.pipeline_version = j.pipeline_version
         AND c.job_type = j.job_type
        JOIN self_engine_state s ON s.id = 1
        WHERE j.id = ?
        ''',
        [jobId],
      );
      if (rows.isEmpty) {
        final jobExists = await transaction.query(
          'self_engine_jobs',
          columns: const ['id'],
          where: 'id = ?',
          whereArgs: [jobId],
          limit: 1,
        );
        if (jobExists.isNotEmpty) {
          throw StateError('Job $jobId has an invalid source identity.');
        }
        return false;
      }
      final job = rows.single;
      final generation = job['generation']! as int;
      final ownsLease =
          job['status'] == SelfEngineJobStatusV2.processing.name &&
          job['lease_id'] == leaseId &&
          DateTime.parse(
            job['lease_expires_at']! as String,
          ).isAfter(publishedAt.toUtc()) &&
          generation == job['current_generation'];
      if (!ownsLease) return false;

      _validatePublishedResult(job, result);
      for (final atom in result.atoms) {
        final values = <String, Object?>{
          'revision_id': atom.revisionId,
          'kind': atom.kind.name,
          'statement': atom.statement,
          'source_quote': atom.sourceQuote,
          'source_start': atom.sourceStart,
          'source_end': atom.sourceEnd,
          'observed_at': atom.observedAt?.toUtc().toIso8601String(),
          'scope': atom.scope.name,
          'pipeline_version': atom.pipelineVersion,
          'generation': atom.generation,
          'created_at': atom.createdAt.toUtc().toIso8601String(),
          'superseded_at': atom.supersededAt?.toUtc().toIso8601String(),
        };
        final changed = await transaction.update(
          'memory_atoms',
          values,
          where: 'id = ? AND revision_id = ? AND generation = ?',
          whereArgs: [atom.id, atom.revisionId, atom.generation],
        );
        if (changed == 0) {
          final collision = await transaction.query(
            'memory_atoms',
            columns: const ['id'],
            where: 'id = ?',
            whereArgs: [atom.id],
            limit: 1,
          );
          if (collision.isNotEmpty) {
            throw StateError(
              'Memory atom ${atom.id} has conflicting identity.',
            );
          }
          await transaction.insert('memory_atoms', {'id': atom.id, ...values});
        }
      }
      for (final thread in result.threads) {
        final values = <String, Object?>{
          'title': thread.title,
          'description': thread.description,
          'status': thread.status.name,
          'first_seen': thread.firstSeen.toUtc().toIso8601String(),
          'last_seen': thread.lastSeen.toUtc().toIso8601String(),
          'merged_into_id': thread.mergedIntoId,
          'pipeline_version': thread.pipelineVersion,
          'generation': thread.generation,
          'created_at': thread.createdAt.toUtc().toIso8601String(),
          'updated_at': thread.updatedAt.toUtc().toIso8601String(),
        };
        final changed = await transaction.update(
          'memory_threads',
          values,
          where: 'id = ? AND generation = ?',
          whereArgs: [thread.id, thread.generation],
        );
        if (changed == 0) {
          final collision = await transaction.query(
            'memory_threads',
            columns: const ['id'],
            where: 'id = ?',
            whereArgs: [thread.id],
            limit: 1,
          );
          if (collision.isNotEmpty) {
            throw StateError(
              'Memory thread ${thread.id} has conflicting identity.',
            );
          }
          await transaction.insert('memory_threads', {
            'id': thread.id,
            ...values,
          });
        }
      }
      for (final membership in result.memberships) {
        final sourceAtom = await transaction.query(
          'memory_atoms',
          columns: const ['id'],
          where: 'id = ? AND revision_id = ? AND generation = ?',
          whereArgs: [membership.atomId, job['revision_id'], generation],
          limit: 1,
        );
        if (sourceAtom.isEmpty) {
          throw StateError(
            'Thread membership atom ${membership.atomId} does not belong to '
            'revision ${job['revision_id']}.',
          );
        }
        final values = <String, Object?>{
          'relevance': membership.relevance,
          'origin': membership.origin.name,
          'generation': membership.generation,
          'created_at': membership.createdAt.toUtc().toIso8601String(),
          'removed_at': membership.removedAt?.toUtc().toIso8601String(),
        };
        final changed = await transaction.update(
          'thread_memberships',
          values,
          where: 'thread_id = ? AND atom_id = ? AND generation = ?',
          whereArgs: [
            membership.threadId,
            membership.atomId,
            membership.generation,
          ],
        );
        if (changed == 0) {
          final collision = await transaction.query(
            'thread_memberships',
            columns: const ['thread_id'],
            where: 'thread_id = ? AND atom_id = ?',
            whereArgs: [membership.threadId, membership.atomId],
            limit: 1,
          );
          if (collision.isNotEmpty) {
            throw StateError('Thread membership has conflicting identity.');
          }
          await transaction.insert('thread_memberships', {
            'thread_id': membership.threadId,
            'atom_id': membership.atomId,
            ...values,
          });
        }
      }

      final changed = await transaction.update(
        'self_engine_jobs',
        {
          'status': SelfEngineJobStatusV2.completed.name,
          'updated_at': timestamp,
          'next_retry_at': null,
          'error': null,
          'lease_id': null,
          'lease_expires_at': null,
        },
        where: '''
          id = ? AND status = 'processing' AND lease_id = ?
          AND lease_expires_at > ? AND generation = ?
          AND generation = (SELECT generation FROM self_engine_state WHERE id = 1)
        ''',
        whereArgs: [jobId, leaseId, timestamp, generation],
      );
      if (changed != 1) {
        throw StateError('Job $jobId lost publish ownership.');
      }
      return true;
    });
  }

  void _validatePublishedResult(
    Map<String, Object?> job,
    SelfEngineDerivedResultV2 result,
  ) {
    final revisionId = job['revision_id']! as String;
    final pipelineVersion = job['pipeline_version']! as int;
    final generation = job['generation']! as int;
    final atomIds = <String>{};
    for (final atom in result.atoms) {
      if (!atomIds.add(atom.id)) {
        throw StateError('Duplicate memory atom ${atom.id}.');
      }
      if (atom.revisionId != revisionId ||
          atom.pipelineVersion != pipelineVersion ||
          atom.generation != generation) {
        throw StateError(
          'Memory atom ${atom.id} has the wrong source identity.',
        );
      }
    }
    final threadIds = <String>{};
    for (final thread in result.threads) {
      if (!threadIds.add(thread.id)) {
        throw StateError('Duplicate memory thread ${thread.id}.');
      }
      if (thread.pipelineVersion != pipelineVersion ||
          thread.generation != generation) {
        throw StateError(
          'Memory thread ${thread.id} has the wrong computation identity.',
        );
      }
    }
    final membershipIds = <String>{};
    for (final membership in result.memberships) {
      if (!membershipIds.add(
        '${membership.threadId}\u0000${membership.atomId}',
      )) {
        throw StateError('Duplicate thread membership.');
      }
      if (membership.generation != generation) {
        throw StateError('Thread membership has the wrong generation.');
      }
    }
  }

  @override
  Future<bool> markJobFailed(
    String id, {
    required String leaseId,
    required DateTime failedAt,
    required String error,
  }) {
    return _database.transaction((transaction) async {
      final timestamp = failedAt.toUtc().toIso8601String();
      final rows = await transaction.query(
        'self_engine_jobs',
        columns: const ['attempt_count'],
        where: '''
          id = ? AND status = 'processing' AND lease_id = ?
          AND lease_expires_at > ?
        ''',
        whereArgs: [id, leaseId, timestamp],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final attempts = rows.single['attempt_count']! as int;
      final terminal = attempts >= _retryPolicy.maxAttempts;
      final changed = await transaction.update(
        'self_engine_jobs',
        {
          'status': terminal
              ? SelfEngineJobStatusV2.failed.name
              : SelfEngineJobStatusV2.retryable.name,
          'updated_at': timestamp,
          'next_retry_at': terminal
              ? null
              : failedAt
                    .toUtc()
                    .add(_retryPolicy.delayAfterAttempt(attempts))
                    .toIso8601String(),
          'error': error,
          'lease_id': null,
          'lease_expires_at': null,
        },
        where: '''
          id = ? AND status = 'processing' AND lease_id = ?
          AND lease_expires_at > ?
        ''',
        whereArgs: [id, leaseId, timestamp],
      );
      return changed == 1;
    });
  }

  @override
  Future<int> recoverExpiredLeases({required DateTime now}) {
    return _database.transaction((transaction) async {
      final timestamp = now.toUtc().toIso8601String();
      final rows = await transaction.query(
        'self_engine_jobs',
        columns: const ['id', 'attempt_count'],
        where: "status = 'processing' AND lease_expires_at <= ?",
        whereArgs: [timestamp],
      );
      var changed = 0;
      for (final row in rows) {
        final attempts = row['attempt_count']! as int;
        final terminal = attempts >= _retryPolicy.maxAttempts;
        changed += await transaction.update(
          'self_engine_jobs',
          {
            'status': terminal
                ? SelfEngineJobStatusV2.failed.name
                : SelfEngineJobStatusV2.retryable.name,
            'updated_at': timestamp,
            'next_retry_at': terminal
                ? null
                : now
                      .toUtc()
                      .add(_retryPolicy.delayAfterAttempt(attempts))
                      .toIso8601String(),
            'error': 'Processing lease expired.',
            'lease_id': null,
            'lease_expires_at': null,
          },
          where: "id = ? AND status = 'processing' AND lease_expires_at <= ?",
          whereArgs: [row['id'], timestamp],
        );
      }
      return changed;
    });
  }

  @override
  Future<void> clearAllDerivedDataForGlobalRebuild() {
    return _database.transaction((transaction) async {
      final generation = await _generation(transaction) + 1;
      await transaction.update('self_engine_state', {
        'generation': generation,
      }, where: 'id = 1');
      await transaction.delete('thread_memberships');
      await transaction.delete('memory_atoms');
      await transaction.delete('memory_threads');
      await _resetJobs(transaction, generation: generation);
    });
  }

  @override
  Future<void> rebuildDerivedDataForDiary(String diaryId) {
    return _database.transaction((transaction) async {
      final generation = await _generation(transaction);
      await transaction.delete(
        'memory_atoms',
        where: '''
          revision_id IN (
            SELECT id FROM diary_revisions WHERE diary_id = ?
          )
        ''',
        whereArgs: [diaryId],
      );
      await transaction.delete(
        'memory_threads',
        where: '''
          NOT EXISTS (
            SELECT 1 FROM thread_memberships m
            WHERE m.thread_id = memory_threads.id
          )
        ''',
      );
      await _resetJobs(transaction, generation: generation, diaryId: diaryId);
    });
  }

  Future<void> _resetJobs(
    DatabaseExecutor database, {
    required int generation,
    String? diaryId,
  }) async {
    await database.update(
      'self_engine_jobs',
      {
        'status': SelfEngineJobStatusV2.pending.name,
        'attempt_count': 0,
        'generation': generation,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'next_retry_at': null,
        'error': null,
        'lease_id': null,
        'lease_expires_at': null,
      },
      where: diaryId == null
          ? null
          : '''
              revision_id IN (
                SELECT id FROM diary_revisions WHERE diary_id = ?
              )
            ''',
      whereArgs: diaryId == null ? null : [diaryId],
    );
  }

  @override
  Future<int> backfillMissingRevisions({int limit = 50}) {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    return _database.transaction((transaction) async {
      final rows = await transaction.rawQuery(
        '''
        SELECT d.*
        FROM diary_entries d
        WHERE NOT EXISTS (
          SELECT 1 FROM diary_revisions r WHERE r.diary_id = d.id
        )
        ORDER BY d.created_at ASC, d.id ASC
        LIMIT ?
        ''',
        [limit],
      );
      for (final row in rows) {
        await _outbox.recordSourceChange(
          transaction,
          _diaryMapper.fromRow(row),
        );
      }
      return rows.length;
    });
  }

  Future<int> _generation(DatabaseExecutor database) async {
    final rows = await database.query(
      'self_engine_state',
      columns: const ['generation'],
      where: 'id = 1',
      limit: 1,
    );
    if (rows.length != 1) {
      throw StateError('Self Engine generation state is missing.');
    }
    return rows.single['generation']! as int;
  }

  String _computationId(
    String hash,
    int fingerprintVersion,
    int pipelineVersion,
    String jobType,
  ) => 'fp$fingerprintVersion-p$pipelineVersion-$jobType-$hash';

  DiaryRevisionV2 _revisionFromRow(Map<String, Object?> row) {
    final tagsValue = jsonDecode(row['tags']! as String);
    return DiaryRevisionV2(
      id: row['id']! as String,
      diaryId: row['diary_id']! as String,
      revisionNo: row['revision_no']! as int,
      body: row['body']! as String,
      contentDelta: row['content_delta'] as String?,
      sourceHash: row['source_hash']! as String,
      fingerprintVersion: row['fingerprint_version']! as int,
      entryDate: DateTime.parse(row['entry_date']! as String),
      mood: row['mood'] as String?,
      tags: tagsValue is List
          ? tagsValue.whereType<String>().toList(growable: false)
          : const [],
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      address: row['address'] as String?,
      createdAt: DateTime.parse(row['created_at']! as String),
    );
  }

  Map<String, Object?> _revisionToRow(DiaryRevisionV2 value) => {
    'id': value.id,
    'diary_id': value.diaryId,
    'revision_no': value.revisionNo,
    'body': value.body,
    'content_delta': value.contentDelta,
    'source_hash': value.sourceHash,
    'fingerprint_version': value.fingerprintVersion,
    'entry_date': value.entryDate.toUtc().toIso8601String(),
    'mood': value.mood,
    'tags': jsonEncode(value.tags),
    'latitude': value.latitude,
    'longitude': value.longitude,
    'address': value.address,
    'created_at': value.createdAt.toUtc().toIso8601String(),
  };

  bool _sameRevision(DiaryRevisionV2 left, DiaryRevisionV2 right) =>
      left.id == right.id &&
      left.diaryId == right.diaryId &&
      left.revisionNo == right.revisionNo &&
      left.body == right.body &&
      left.contentDelta == right.contentDelta &&
      left.sourceHash == right.sourceHash &&
      left.fingerprintVersion == right.fingerprintVersion &&
      left.entryDate.toUtc() == right.entryDate.toUtc() &&
      left.mood == right.mood &&
      _sameStrings(left.tags, right.tags) &&
      left.latitude == right.latitude &&
      left.longitude == right.longitude &&
      left.address == right.address &&
      left.createdAt.toUtc() == right.createdAt.toUtc();

  bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  SelfEngineJobV2 _jobFromRow(Map<String, Object?> row) => SelfEngineJobV2(
    id: row['id']! as String,
    diaryId: row['diary_id']! as String,
    revisionId: row['revision_id']! as String,
    computationId: row['computation_id']! as String,
    sourceHash: row['source_hash']! as String,
    fingerprintVersion: row['fingerprint_version']! as int,
    type: SelfEngineJobTypeV2.values.firstWhere(
      (value) => value.name == row['job_type'],
    ),
    status: SelfEngineJobStatusV2.values.firstWhere(
      (value) => value.name == row['status'],
    ),
    attemptCount: row['attempt_count']! as int,
    pipelineVersion: row['pipeline_version']! as int,
    generation: row['generation']! as int,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    nextRetryAt: _date(row['next_retry_at']),
    error: row['error'] as String?,
    leaseId: row['lease_id'] as String?,
    leaseExpiresAt: _date(row['lease_expires_at']),
  );

  DateTime? _date(Object? value) =>
      value is String && value.isNotEmpty ? DateTime.parse(value) : null;
}
