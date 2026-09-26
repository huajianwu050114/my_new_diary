import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../../application/ports/memory_thread_candidate_retriever_v2.dart';
import '../../domain/entities/memory_atom_v2.dart';
import '../../domain/entities/memory_thread_link_v2.dart';
import '../../domain/entities/memory_thread_v2.dart';

class SqliteMemoryThreadCandidateRetrieverV2
    implements MemoryThreadCandidateRetrieverV2 {
  const SqliteMemoryThreadCandidateRetrieverV2(
    this._database, {
    this.maxThreadCandidates = 8,
    this.maxAtomCandidates = 16,
    this.maxRepresentativeAtoms = 3,
    this.threadScanLimit = 64,
    this.atomScanLimit = 200,
  });

  final Database _database;
  final int maxThreadCandidates;
  final int maxAtomCandidates;
  final int maxRepresentativeAtoms;
  final int threadScanLimit;
  final int atomScanLimit;

  @override
  Future<List<ThreadAtomEvidenceV2>> activeAtomsForRevision(
    String revisionId,
  ) async {
    final rows = await _database.rawQuery(
      '''
      SELECT a.*, r.diary_id, r.entry_date
      FROM memory_atoms a
      JOIN diary_revisions r ON r.id = a.revision_id
      JOIN diary_entries d ON d.id = r.diary_id
      JOIN self_engine_state s ON s.id = 1
      WHERE a.revision_id = ?
        AND a.generation = s.generation
        AND a.superseded_at IS NULL
        AND d.deleted_at IS NULL
        AND r.revision_no = (
          SELECT MAX(latest.revision_no)
          FROM diary_revisions latest
          WHERE latest.diary_id = r.diary_id
        )
      ORDER BY a.created_at, a.id
      ''',
      [revisionId],
    );
    return rows.map(_evidenceFromRow).toList(growable: false);
  }

  @override
  Future<MemoryThreadLinkRequestV2?> retrieve(String atomId) async {
    final currentRows = await _database.rawQuery(
      '''
      SELECT a.*, r.diary_id, r.entry_date
      FROM memory_atoms a
      JOIN diary_revisions r ON r.id = a.revision_id
      JOIN diary_entries d ON d.id = r.diary_id
      JOIN self_engine_state s ON s.id = 1
      WHERE a.id = ?
        AND a.generation = s.generation
        AND a.superseded_at IS NULL
        AND d.deleted_at IS NULL
        AND r.revision_no = (
          SELECT MAX(latest.revision_no)
          FROM diary_revisions latest
          WHERE latest.diary_id = r.diary_id
        )
      LIMIT 1
      ''',
      [atomId],
    );
    if (currentRows.isEmpty) return null;
    final current = _evidenceFromRow(currentRows.single);
    final threadCandidates = await _threadCandidates(current);
    final atomCandidates = await _atomCandidates(current);
    return MemoryThreadLinkRequestV2(
      currentAtom: current,
      threadCandidates: threadCandidates,
      atomCandidates: atomCandidates,
    );
  }

  Future<List<MemoryThreadCandidateV2>> _threadCandidates(
    ThreadAtomEvidenceV2 current,
  ) async {
    final rows = await _database.rawQuery(
      '''
      SELECT t.*
      FROM memory_threads t
      JOIN self_engine_state s ON s.id = 1
      WHERE t.generation = s.generation
        AND t.status = 'active'
        AND (
          SELECT COUNT(DISTINCT r.diary_id)
          FROM thread_memberships m
          JOIN memory_atoms a
            ON a.id = m.atom_id AND a.generation = m.generation
          JOIN diary_revisions r ON r.id = a.revision_id
          JOIN diary_entries d ON d.id = r.diary_id
          WHERE m.thread_id = t.id
            AND m.removed_at IS NULL
            AND a.superseded_at IS NULL
            AND d.deleted_at IS NULL
            AND r.revision_no = (
              SELECT MAX(latest.revision_no)
              FROM diary_revisions latest
              WHERE latest.diary_id = r.diary_id
            )
        ) >= 2
      ORDER BY t.last_seen DESC, t.id
      LIMIT ?
      ''',
      [threadScanLimit],
    );
    if (rows.isEmpty) return const [];
    final ids = rows.map((row) => row['id']! as String).toList(growable: false);
    final placeholders = List.filled(ids.length, '?').join(',');
    final representativeRows = await _database.rawQuery(
      '''
      WITH ranked AS (
        SELECT m.thread_id, a.*, r.diary_id, r.entry_date,
               ROW_NUMBER() OVER (
                 PARTITION BY m.thread_id
                 ORDER BY COALESCE(a.observed_at, r.entry_date) DESC, a.id
               ) AS evidence_rank
        FROM thread_memberships m
        JOIN memory_atoms a
          ON a.id = m.atom_id AND a.generation = m.generation
        JOIN diary_revisions r ON r.id = a.revision_id
        JOIN diary_entries d ON d.id = r.diary_id
        JOIN self_engine_state s ON s.id = 1
        WHERE m.thread_id IN ($placeholders)
          AND m.generation = s.generation
          AND m.removed_at IS NULL
          AND a.superseded_at IS NULL
          AND d.deleted_at IS NULL
          AND r.revision_no = (
            SELECT MAX(latest.revision_no)
            FROM diary_revisions latest
            WHERE latest.diary_id = r.diary_id
          )
      )
      SELECT * FROM ranked
      WHERE evidence_rank <= ?
      ORDER BY thread_id, evidence_rank
      ''',
      [...ids, maxRepresentativeAtoms],
    );
    final representatives = <String, List<ThreadAtomEvidenceV2>>{};
    for (final row in representativeRows) {
      representatives
          .putIfAbsent(row['thread_id']! as String, () => [])
          .add(_evidenceFromRow(row));
    }
    final derivationRows = await _database.rawQuery('''
      SELECT source.thread_id, source.atom_id
      FROM thread_derivation_atoms source
      JOIN self_engine_state s ON s.id = 1
      WHERE source.thread_id IN ($placeholders)
        AND source.generation = s.generation
      ORDER BY source.thread_id, source.atom_id
      ''', ids);
    final derivationAtomIds = <String, List<String>>{};
    for (final row in derivationRows) {
      derivationAtomIds
          .putIfAbsent(row['thread_id']! as String, () => [])
          .add(row['atom_id']! as String);
    }
    final scored = <({double score, MemoryThreadCandidateV2 value})>[];
    final query = _features(
      '${current.atom.statement} ${current.atom.sourceQuote}',
    );
    for (final row in rows) {
      final thread = _threadFromRow(row);
      final evidence = representatives[thread.id] ?? const [];
      final text = StringBuffer('${thread.title} ${thread.description}');
      for (final atom in evidence) {
        text.write(' ${atom.atom.statement} ${atom.atom.sourceQuote}');
      }
      final score = _overlap(query, _features(text.toString()));
      if (score > 0) {
        scored.add((
          score: score,
          value: MemoryThreadCandidateV2(
            thread: thread,
            representativeAtoms: List.unmodifiable(evidence),
            derivationAtomIds: List.unmodifiable(
              derivationAtomIds[thread.id] ?? const <String>[],
            ),
          ),
        ));
      }
    }
    scored.sort((left, right) {
      final byScore = right.score.compareTo(left.score);
      if (byScore != 0) return byScore;
      return right.value.thread.lastSeen.compareTo(left.value.thread.lastSeen);
    });
    return scored
        .take(maxThreadCandidates)
        .map((item) => item.value)
        .toList(growable: false);
  }

  Future<List<ThreadAtomEvidenceV2>> _atomCandidates(
    ThreadAtomEvidenceV2 current,
  ) async {
    final rows = await _database.rawQuery(
      '''
      SELECT a.*, r.diary_id, r.entry_date
      FROM memory_atoms a
      JOIN diary_revisions r ON r.id = a.revision_id
      JOIN diary_entries d ON d.id = r.diary_id
      JOIN self_engine_state s ON s.id = 1
      WHERE a.generation = s.generation
        AND a.id != ?
        AND r.diary_id != ?
        AND a.superseded_at IS NULL
        AND d.deleted_at IS NULL
        AND r.revision_no = (
          SELECT MAX(latest.revision_no)
          FROM diary_revisions latest
          WHERE latest.diary_id = r.diary_id
        )
        AND NOT EXISTS (
          SELECT 1
          FROM thread_memberships m
          WHERE m.atom_id = a.id
            AND m.generation = a.generation
            AND m.removed_at IS NULL
        )
      ORDER BY a.observed_at DESC, a.id
      LIMIT ?
      ''',
      [current.atom.id, current.diaryId, atomScanLimit],
    );
    final query = _features(
      '${current.atom.statement} ${current.atom.sourceQuote}',
    );
    final scored = <({double score, ThreadAtomEvidenceV2 value})>[];
    for (final row in rows) {
      final evidence = _evidenceFromRow(row);
      final overlap = _overlap(
        query,
        _features('${evidence.atom.statement} ${evidence.atom.sourceQuote}'),
      );
      if (overlap <= 0) continue;
      final kindBoost = evidence.atom.kind == current.atom.kind ? 0.1 : 0.0;
      scored.add((score: overlap + kindBoost, value: evidence));
    }
    scored.sort((left, right) {
      final byScore = right.score.compareTo(left.score);
      if (byScore != 0) return byScore;
      return right.value.entryDate.compareTo(left.value.entryDate);
    });
    return scored
        .take(maxAtomCandidates)
        .map((item) => item.value)
        .toList(growable: false);
  }

  Set<String> _features(String value) {
    final normalized = value.toLowerCase();
    final features = <String>{};
    for (final match in RegExp(r'[a-z0-9]+').allMatches(normalized)) {
      final token = match.group(0)!;
      if (token.length >= 2) features.add('w:$token');
    }
    final cjk = normalized.runes
        .where(
          (rune) =>
              (rune >= 0x3400 && rune <= 0x4dbf) ||
              (rune >= 0x4e00 && rune <= 0x9fff),
        )
        .toList(growable: false);
    for (var index = 0; index + 1 < cjk.length; index++) {
      features.add('c:${String.fromCharCodes(cjk.sublist(index, index + 2))}');
    }
    return features;
  }

  double _overlap(Set<String> left, Set<String> right) {
    if (left.isEmpty || right.isEmpty) return 0;
    final intersection = left.intersection(right).length;
    if (intersection == 0) return 0;
    return intersection / math.sqrt(left.length * right.length);
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

  DateTime? _date(Object? value) =>
      value is String && value.isNotEmpty ? DateTime.parse(value) : null;
}
