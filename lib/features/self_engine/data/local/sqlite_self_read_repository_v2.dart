import 'package:sqflite/sqflite.dart';

import '../../domain/entities/self_read_model_v2.dart';
import '../../domain/repositories/self_read_repository_v2.dart';

class SqliteSelfReadRepositoryV2 implements SelfReadRepositoryV2 {
  const SqliteSelfReadRepositoryV2(this._database);

  final Database _database;

  static const _activeThreadProjection = '''
    FROM memory_threads t
    JOIN self_engine_state s ON s.id = 1
    JOIN thread_memberships m
      ON m.thread_id = t.id AND m.generation = t.generation
    JOIN memory_atoms a
      ON a.id = m.atom_id AND a.generation = m.generation
    JOIN diary_revisions r ON r.id = a.revision_id
    JOIN diary_entries d ON d.id = r.diary_id
    WHERE t.generation = s.generation
      AND t.status = 'active'
      AND m.removed_at IS NULL
      AND a.superseded_at IS NULL
      AND d.deleted_at IS NULL
      AND r.revision_no = (
        SELECT MAX(latest.revision_no)
        FROM diary_revisions latest
        WHERE latest.diary_id = r.diary_id
      )
  ''';

  @override
  Future<List<SelfThreadSummaryV2>> getActiveThreads({
    int limit = 50,
    int offset = 0,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be greater than zero');
    }
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'must not be negative');
    }
    final rows = await _database.rawQuery(
      '''
      SELECT t.id, t.title, t.description,
             MIN(COALESCE(a.observed_at, r.entry_date)) AS first_seen,
             MAX(COALESCE(a.observed_at, r.entry_date)) AS last_seen,
             COUNT(DISTINCT r.diary_id) AS distinct_diary_count,
             COUNT(DISTINCT a.id) AS evidence_count
      $_activeThreadProjection
      GROUP BY t.id, t.title, t.description
      ORDER BY last_seen DESC, t.id
      LIMIT ? OFFSET ?
      ''',
      [limit, offset],
    );
    return rows.map(_summaryFromRow).toList(growable: false);
  }

  @override
  Future<SelfThreadDetailV2?> getThreadDetail(String threadId) async {
    final summaries = await _database.rawQuery(
      '''
      SELECT t.id, t.title, t.description,
             MIN(COALESCE(a.observed_at, r.entry_date)) AS first_seen,
             MAX(COALESCE(a.observed_at, r.entry_date)) AS last_seen,
             COUNT(DISTINCT r.diary_id) AS distinct_diary_count,
             COUNT(DISTINCT a.id) AS evidence_count
      $_activeThreadProjection
        AND t.id = ?
      GROUP BY t.id, t.title, t.description
      ''',
      [threadId],
    );
    if (summaries.isEmpty) return null;
    final evidenceRows = await _database.rawQuery(
      '''
      SELECT a.id AS atom_id, r.diary_id,
             COALESCE(a.observed_at, r.entry_date) AS occurred_at,
             a.statement, a.source_quote
      $_activeThreadProjection
        AND t.id = ?
      ORDER BY occurred_at DESC, a.id
      ''',
      [threadId],
    );
    return SelfThreadDetailV2(
      summary: _summaryFromRow(summaries.single),
      evidence: evidenceRows
          .map(
            (row) => SelfThreadEvidenceV2(
              atomId: row['atom_id']! as String,
              diaryId: row['diary_id']! as String,
              occurredAt: DateTime.parse(row['occurred_at']! as String),
              statement: row['statement']! as String,
              sourceQuote: row['source_quote']! as String,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<SelfEngineReadStateV2> getSelfEngineState() async {
    final rows = await _database.rawQuery('''
      SELECT
        EXISTS(
          SELECT 1
          FROM self_engine_jobs j
          JOIN self_engine_state s ON s.id = 1
          WHERE j.generation = s.generation
            AND j.origin = 'live'
            AND j.status IN ('pending', 'processing', 'retryable')
          UNION ALL
          SELECT 1
          FROM thread_link_jobs j
          JOIN self_engine_state s ON s.id = 1
          WHERE j.generation = s.generation
            AND j.origin = 'live'
            AND j.status IN ('pending', 'processing', 'retryable')
        ) AS has_live_work,
        EXISTS(
          SELECT 1
          FROM self_engine_jobs j
          JOIN self_engine_state s ON s.id = 1
          WHERE j.generation = s.generation
            AND j.origin = 'live'
            AND j.status = 'failed'
          UNION ALL
          SELECT 1
          FROM thread_link_jobs j
          JOIN self_engine_state s ON s.id = 1
          WHERE j.generation = s.generation
            AND j.origin = 'live'
            AND j.status = 'failed'
        ) AS has_failed_work
    ''');
    final row = rows.single;
    return SelfEngineReadStateV2(
      hasLiveWork: row['has_live_work'] == 1,
      hasFailedWork: row['has_failed_work'] == 1,
    );
  }

  SelfThreadSummaryV2 _summaryFromRow(Map<String, Object?> row) =>
      SelfThreadSummaryV2(
        id: row['id']! as String,
        title: row['title']! as String,
        description: row['description']! as String,
        firstSeen: DateTime.parse(row['first_seen']! as String),
        lastSeen: DateTime.parse(row['last_seen']! as String),
        distinctDiaryCount: row['distinct_diary_count']! as int,
        evidenceCount: row['evidence_count']! as int,
      );
}
