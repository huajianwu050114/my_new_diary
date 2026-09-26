import 'package:sqflite/sqflite.dart';

import '../../domain/entities/self_engine_job_v2.dart';
import '../../domain/self_engine_pipeline_v2.dart';

abstract final class ThreadLinkWorkV2 {
  static String jobId(String revisionId, int generation) =>
      'thread-link-g$generation-p${SelfEnginePipelineV2.threadPipelineVersion}-$revisionId';

  static Future<void> enqueueRevision(
    DatabaseExecutor database, {
    required String revisionId,
    required SelfEngineJobOriginV2 origin,
    required int generation,
    required DateTime now,
    bool reset = false,
  }) async {
    final timestamp = now.toUtc().toIso8601String();
    final id = jobId(revisionId, generation);
    await database.insert('thread_link_jobs', {
      'id': id,
      'revision_id': revisionId,
      'origin': origin.name,
      'status': SelfEngineJobStatusV2.pending.name,
      'attempt_count': 0,
      'pipeline_version': SelfEnginePipelineV2.threadPipelineVersion,
      'generation': generation,
      'created_at': timestamp,
      'updated_at': timestamp,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (!reset) return;
    await database.update(
      'thread_link_jobs',
      {
        'origin': origin.name,
        'status': SelfEngineJobStatusV2.pending.name,
        'attempt_count': 0,
        'updated_at': timestamp,
        'next_retry_at': null,
        'error': null,
        'lease_id': null,
        'lease_expires_at': null,
      },
      where: 'id = ? AND generation = ?',
      whereArgs: [id, generation],
    );
  }

  /// Deletes every Thread whose derived text may depend on [diaryId], then
  /// requeues surviving active evidence. This intentionally prefers a clean
  /// rebuild over attempting to edit AI-authored title/description text.
  static Future<void> invalidateThreadsUsingDiary(
    DatabaseExecutor database, {
    required String diaryId,
    required int generation,
    required DateTime now,
  }) async {
    final affected = await database.rawQuery(
      '''
      SELECT m.thread_id
      FROM thread_memberships m
      JOIN memory_atoms a ON a.id = m.atom_id AND a.generation = m.generation
      JOIN diary_revisions r ON r.id = a.revision_id
      WHERE r.diary_id = ?
        AND m.generation = ?
        AND m.removed_at IS NULL
      UNION
      SELECT source.thread_id
      FROM thread_derivation_atoms source
      JOIN memory_atoms a
        ON a.id = source.atom_id AND a.generation = source.generation
      JOIN diary_revisions r ON r.id = a.revision_id
      WHERE r.diary_id = ?
        AND source.generation = ?
      ''',
      [diaryId, generation, diaryId, generation],
    );
    if (affected.isEmpty) return;
    final threadIds = affected
        .map((row) => row['thread_id']! as String)
        .toList(growable: false);
    final placeholders = List.filled(threadIds.length, '?').join(',');
    final surviving = await database.rawQuery(
      '''
      SELECT DISTINCT a.revision_id, j.origin
      FROM thread_memberships m
      JOIN memory_atoms a ON a.id = m.atom_id AND a.generation = m.generation
      JOIN diary_revisions r ON r.id = a.revision_id
      JOIN diary_entries d ON d.id = r.diary_id
      JOIN self_engine_jobs j
        ON j.revision_id = r.id
       AND j.pipeline_version = a.pipeline_version
      WHERE m.thread_id IN ($placeholders)
        AND r.diary_id != ?
        AND m.generation = ?
        AND m.removed_at IS NULL
        AND a.superseded_at IS NULL
        AND d.deleted_at IS NULL
        AND r.revision_no = (
          SELECT MAX(latest.revision_no)
          FROM diary_revisions latest
          WHERE latest.diary_id = r.diary_id
        )
      ''',
      [...threadIds, diaryId, generation],
    );
    await database.delete(
      'memory_threads',
      where: 'id IN ($placeholders)',
      whereArgs: threadIds,
    );
    for (final row in surviving) {
      await enqueueRevision(
        database,
        revisionId: row['revision_id']! as String,
        origin: SelfEngineJobOriginV2.values.byName(row['origin']! as String),
        generation: generation,
        now: now,
        reset: true,
      );
    }
  }
}
