import 'package:sqflite/sqflite.dart';

import '../../domain/entities/self_engine_job_v2.dart';
import '../../domain/self_engine_pipeline_v2.dart';

abstract final class ThesisWorkV2 {
  static const minimumSpanDays = 7;

  static String jobId(String threadId, String revisionId, int generation) =>
      'thesis-g$generation-p${SelfEnginePipelineV2.thesisPipelineVersion}-$threadId-$revisionId';

  static Future<bool> enqueueIfEligible(
    DatabaseExecutor database, {
    required String threadId,
    required String triggerRevisionId,
    required SelfEngineJobOriginV2 origin,
    required int generation,
    required DateTime now,
  }) async {
    final eligible = await database.rawQuery(
      '''
      SELECT t.id,
             COUNT(DISTINCT r.diary_id) AS diary_count,
             COUNT(DISTINCT date(COALESCE(a.observed_at, r.entry_date))) AS date_count,
             julianday(MAX(COALESCE(a.observed_at, r.entry_date))) -
               julianday(MIN(COALESCE(a.observed_at, r.entry_date))) AS span_days
      FROM memory_threads t
      JOIN thread_memberships m
        ON m.thread_id = t.id AND m.generation = t.generation
      JOIN memory_atoms a
        ON a.id = m.atom_id AND a.generation = m.generation
      JOIN diary_revisions r ON r.id = a.revision_id
      JOIN diary_entries d ON d.id = r.diary_id
      WHERE t.id = ?
        AND t.generation = ?
        AND t.status = 'active'
        AND m.removed_at IS NULL
        AND a.superseded_at IS NULL
        AND d.deleted_at IS NULL
        AND r.revision_no = (
          SELECT MAX(latest.revision_no)
          FROM diary_revisions latest
          WHERE latest.diary_id = r.diary_id
        )
        AND NOT EXISTS (
          SELECT 1 FROM personal_theses thesis
          WHERE thesis.thread_id = t.id
            AND thesis.generation = t.generation
            AND thesis.status = 'active'
        )
      GROUP BY t.id
      HAVING diary_count >= 3
         AND date_count >= 2
         AND span_days >= ?
      ''',
      [threadId, generation, minimumSpanDays],
    );
    if (eligible.isEmpty) return false;
    final timestamp = now.toUtc().toIso8601String();
    final changed = await database.insert('thesis_jobs', {
      'id': jobId(threadId, triggerRevisionId, generation),
      'thread_id': threadId,
      'trigger_revision_id': triggerRevisionId,
      'origin': origin.name,
      'status': SelfEngineJobStatusV2.pending.name,
      'attempt_count': 0,
      'pipeline_version': SelfEnginePipelineV2.thesisPipelineVersion,
      'generation': generation,
      'created_at': timestamp,
      'updated_at': timestamp,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return changed != 0;
  }

  static Future<int> invalidateCurrentThesesUsingDiary(
    DatabaseExecutor database, {
    required String diaryId,
    required int generation,
    required DateTime now,
  }) {
    return database.rawUpdate(
      '''
      UPDATE personal_theses
      SET status = 'invalidated',
          current_version_id = NULL,
          thread_id = NULL,
          updated_at = ?
      WHERE generation = ?
        AND status = 'active'
        AND current_version_id IS NOT NULL
        AND (
          EXISTS (
            SELECT 1
            FROM personal_thesis_evidence evidence
            JOIN memory_atoms atom
              ON atom.id = evidence.atom_id
             AND atom.generation = evidence.generation
            JOIN diary_revisions revision ON revision.id = atom.revision_id
            WHERE evidence.thesis_version_id = personal_theses.current_version_id
              AND evidence.generation = personal_theses.generation
              AND revision.diary_id = ?
          )
          OR EXISTS (
            SELECT 1
            FROM thesis_derivation_atoms derivation
            JOIN memory_atoms atom
              ON atom.id = derivation.atom_id
             AND atom.generation = derivation.generation
            JOIN diary_revisions revision ON revision.id = atom.revision_id
            WHERE derivation.thesis_version_id = personal_theses.current_version_id
              AND derivation.generation = personal_theses.generation
              AND revision.diary_id = ?
          )
        )
      ''',
      [now.toUtc().toIso8601String(), generation, diaryId, diaryId],
    );
  }

  static Future<void> deleteThesesUsingDiary(
    DatabaseExecutor database, {
    required String diaryId,
    required int generation,
  }) async {
    await database.rawDelete(
      '''
      DELETE FROM personal_theses
      WHERE generation = ? AND id IN (
        SELECT DISTINCT v.thesis_id
        FROM personal_thesis_versions v
        JOIN (
          SELECT thesis_version_id, atom_id FROM personal_thesis_evidence
          UNION
          SELECT thesis_version_id, atom_id FROM thesis_derivation_atoms
        ) source ON source.thesis_version_id = v.id
        JOIN memory_atoms a ON a.id = source.atom_id
        JOIN diary_revisions r ON r.id = a.revision_id
        WHERE r.diary_id = ?
      )
      ''',
      [generation, diaryId],
    );
  }
}
