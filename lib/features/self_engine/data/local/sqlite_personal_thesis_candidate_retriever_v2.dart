import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../../application/ports/personal_thesis_candidate_retriever_v2.dart';
import '../../domain/entities/memory_atom_v2.dart';
import '../../domain/entities/memory_thread_link_v2.dart';
import '../../domain/entities/memory_thread_v2.dart';
import '../../domain/entities/personal_thesis_synthesis_v2.dart';

class SqlitePersonalThesisCandidateRetrieverV2
    implements PersonalThesisCandidateRetrieverV2 {
  const SqlitePersonalThesisCandidateRetrieverV2(
    this._database, {
    this.maxSupportCandidates = 12,
    this.maxCounterCandidates = 16,
    this.counterScanLimit = 96,
  });

  final Database _database;
  final int maxSupportCandidates;
  final int maxCounterCandidates;
  final int counterScanLimit;

  @override
  Future<PersonalThesisSynthesisRequestV2?> retrieve(String threadId) async {
    final threadRows = await _database.rawQuery(
      '''
      SELECT t.*
      FROM memory_threads t
      JOIN self_engine_state s ON s.id = 1
      WHERE t.id = ? AND t.generation = s.generation AND t.status = 'active'
      LIMIT 1
      ''',
      [threadId],
    );
    if (threadRows.isEmpty) return null;
    final thread = _threadFromRow(threadRows.single);
    final support = await _support(thread);
    if (!_eligible(support)) return null;
    final counter = await _counter(thread, support);
    final derivationRows = await _database.rawQuery(
      '''
      SELECT atom_id FROM thread_derivation_atoms
      WHERE thread_id = ? AND generation = ?
      UNION
      SELECT atom_id FROM thread_memberships
      WHERE thread_id = ? AND generation = ? AND removed_at IS NULL
      ORDER BY atom_id
      ''',
      [thread.id, thread.generation, thread.id, thread.generation],
    );
    return PersonalThesisSynthesisRequestV2(
      thread: thread,
      supportCandidates: List.unmodifiable(support),
      counterCandidates: List.unmodifiable(counter),
      threadDerivationAtomIds: List.unmodifiable(
        derivationRows.map((row) => row['atom_id']! as String),
      ),
    );
  }

  Future<List<ThreadAtomEvidenceV2>> _support(MemoryThreadV2 thread) async {
    final rows = await _database.rawQuery(
      '''
      WITH active AS (
        SELECT a.*, r.diary_id, r.entry_date,
               ROW_NUMBER() OVER (
                 PARTITION BY r.diary_id
                 ORDER BY COALESCE(a.observed_at, r.entry_date) DESC, a.id
               ) AS diary_rank
        FROM thread_memberships m
        JOIN memory_atoms a
          ON a.id = m.atom_id AND a.generation = m.generation
        JOIN diary_revisions r ON r.id = a.revision_id
        JOIN diary_entries d ON d.id = r.diary_id
        WHERE m.thread_id = ? AND m.generation = ?
          AND m.removed_at IS NULL AND a.superseded_at IS NULL
          AND d.deleted_at IS NULL
          AND r.revision_no = (
            SELECT MAX(latest.revision_no) FROM diary_revisions latest
            WHERE latest.diary_id = r.diary_id
          )
      ), ranked AS (
        SELECT active.*,
               ROW_NUMBER() OVER (
                 ORDER BY COALESCE(observed_at, entry_date), id
               ) AS historical_rank,
               ROW_NUMBER() OVER (
                 ORDER BY COALESCE(observed_at, entry_date) DESC, id
               ) AS recent_rank
        FROM active
      )
      SELECT * FROM ranked
      ORDER BY CASE WHEN diary_rank = 1 THEN 0 ELSE 1 END,
               MIN(historical_rank, recent_rank),
               diary_rank, COALESCE(observed_at, entry_date) DESC, id
      LIMIT ?
      ''',
      [thread.id, thread.generation, maxSupportCandidates],
    );
    return rows.map(_evidenceFromRow).toList(growable: false);
  }

  bool _eligible(List<ThreadAtomEvidenceV2> evidence) {
    if (evidence.map((item) => item.diaryId).toSet().length < 3) return false;
    final dates = evidence.map(_observed).toList(growable: false)..sort();
    final distinctDates = dates
        .map((date) => '${date.year}-${date.month}-${date.day}')
        .toSet();
    return distinctDates.length >= 2 &&
        dates.last.difference(dates.first).inDays >= 7;
  }

  Future<List<ThreadAtomEvidenceV2>> _counter(
    MemoryThreadV2 thread,
    List<ThreadAtomEvidenceV2> support,
  ) async {
    final rows = await _database.rawQuery(
      '''
      WITH active AS (
        SELECT a.*, r.diary_id, r.entry_date
        FROM memory_atoms a
        JOIN diary_revisions r ON r.id = a.revision_id
        JOIN diary_entries d ON d.id = r.diary_id
        JOIN self_engine_state s ON s.id = 1
        WHERE a.generation = s.generation
          AND a.superseded_at IS NULL AND d.deleted_at IS NULL
          AND r.revision_no = (
            SELECT MAX(latest.revision_no) FROM diary_revisions latest
            WHERE latest.diary_id = r.diary_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM thread_memberships m
            WHERE m.thread_id = ? AND m.atom_id = a.id
              AND m.generation = a.generation AND m.removed_at IS NULL
          )
      ), ranked AS (
        SELECT active.*,
               ROW_NUMBER() OVER (
                 ORDER BY COALESCE(observed_at, entry_date), id
               ) AS historical_rank,
               ROW_NUMBER() OVER (
                 ORDER BY COALESCE(observed_at, entry_date) DESC, id
               ) AS recent_rank
        FROM active
      )
      SELECT * FROM ranked
      ORDER BY MIN(historical_rank, recent_rank), id
      LIMIT ?
      ''',
      [thread.id, counterScanLimit],
    );
    final values = rows.map(_evidenceFromRow).toList(growable: false);
    if (values.length <= maxCounterCandidates) return values;
    final query = _features(
      '${thread.title} ${thread.description} '
      '${support.map((item) => item.atom.statement).join(' ')}',
    );
    final scored =
        values
            .map(
              (value) => (
                value: value,
                score: _overlap(
                  query,
                  _features(
                    '${value.atom.statement} ${value.atom.sourceQuote}',
                  ),
                ),
              ),
            )
            .toList(growable: false)
          ..sort((left, right) {
            final score = right.score.compareTo(left.score);
            if (score != 0) return score;
            final date = _observed(
              right.value,
            ).compareTo(_observed(left.value));
            if (date != 0) return date;
            return left.value.atom.id.compareTo(right.value.atom.id);
          });
    final selected = <String, ThreadAtomEvidenceV2>{};
    for (final item in scored.take(maxCounterCandidates ~/ 2)) {
      selected[item.value.atom.id] = item.value;
    }
    for (final value in values.take(maxCounterCandidates ~/ 4)) {
      selected[value.atom.id] = value;
    }
    for (final value in values.reversed.take(maxCounterCandidates ~/ 4)) {
      selected[value.atom.id] = value;
    }
    for (final item in scored) {
      if (selected.length >= maxCounterCandidates) break;
      selected[item.value.atom.id] = item.value;
    }
    return selected.values.take(maxCounterCandidates).toList(growable: false);
  }

  Set<String> _features(String value) {
    final normalized = value.toLowerCase();
    final result = <String>{};
    for (final match in RegExp(r'[a-z0-9]+').allMatches(normalized)) {
      final token = match.group(0)!;
      if (token.length >= 2) result.add('w:$token');
    }
    final cjk = normalized.runes
        .where(
          (rune) =>
              (rune >= 0x3400 && rune <= 0x4dbf) ||
              (rune >= 0x4e00 && rune <= 0x9fff),
        )
        .toList(growable: false);
    for (var index = 0; index + 1 < cjk.length; index++) {
      result.add('c:${String.fromCharCodes(cjk.sublist(index, index + 2))}');
    }
    return result;
  }

  double _overlap(Set<String> left, Set<String> right) {
    if (left.isEmpty || right.isEmpty) return 0;
    return left.intersection(right).length /
        math.sqrt(left.length * right.length);
  }

  ThreadAtomEvidenceV2 _evidenceFromRow(Map<String, Object?> row) =>
      ThreadAtomEvidenceV2(
        atom: MemoryAtomV2(
          id: row['id']! as String,
          revisionId: row['revision_id']! as String,
          kind: MemoryAtomKindV2.values.byName(row['kind']! as String),
          statement: row['statement']! as String,
          sourceQuote: row['source_quote']! as String,
          sourceStart: row['source_start'] as int?,
          sourceEnd: row['source_end'] as int?,
          observedAt: _date(row['observed_at']),
          scope: MemoryAtomScopeV2.values.byName(row['scope']! as String),
          pipelineVersion: row['pipeline_version']! as int,
          generation: row['generation']! as int,
          createdAt: DateTime.parse(row['created_at']! as String),
          supersededAt: _date(row['superseded_at']),
        ),
        diaryId: row['diary_id']! as String,
        entryDate: DateTime.parse(row['entry_date']! as String),
      );

  MemoryThreadV2 _threadFromRow(Map<String, Object?> row) => MemoryThreadV2(
    id: row['id']! as String,
    title: row['title']! as String,
    description: row['description']! as String,
    status: MemoryThreadStatusV2.values.byName(row['status']! as String),
    firstSeen: DateTime.parse(row['first_seen']! as String),
    lastSeen: DateTime.parse(row['last_seen']! as String),
    mergedIntoId: row['merged_into_id'] as String?,
    pipelineVersion: row['pipeline_version']! as int,
    generation: row['generation']! as int,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
  );

  DateTime _observed(ThreadAtomEvidenceV2 value) =>
      (value.atom.observedAt ?? value.entryDate).toUtc();

  DateTime? _date(Object? value) =>
      value is String && value.isNotEmpty ? DateTime.parse(value) : null;
}
