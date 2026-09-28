import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/diary/data/local/diary_database_v2.dart';
import 'package:my_new_diary/features/self_engine/data/local/sqlite_self_read_repository_v2.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('SQLite Self read repository', () {
    late DiaryDatabaseV2 owner;
    late Database database;
    late SqliteSelfReadRepositoryV2 repository;

    setUp(() async {
      owner = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => inMemoryDatabasePath,
      );
      database = await owner.open();
      repository = SqliteSelfReadRepositoryV2(database);
    });

    tearDown(() => owner.close());

    test('overview enforces active evidence and aggregate semantics', () async {
      await _insertDiary(database, id: 'stale', entryDate: _date(2024, 1));
      await _insertAtom(
        database,
        id: 'stale-atom',
        revisionId: 'stale-r1',
        observedAt: _date(2024, 1),
        generation: 1,
      );
      await _insertThread(
        database,
        id: 'stale-thread',
        title: 'Stale generation',
        generation: 1,
      );
      await _insertMembership(
        database,
        threadId: 'stale-thread',
        atomId: 'stale-atom',
        generation: 1,
      );
      await database.update('self_engine_state', {
        'generation': 2,
      }, where: 'id = 1');

      await _insertDiary(database, id: 'd1', entryDate: _date(2026, 6));
      await _insertDiary(database, id: 'd2', entryDate: _date(2026, 7));
      await _insertDiary(database, id: 'd3', entryDate: _date(2026, 5));
      await _insertDiary(
        database,
        id: 'deleted',
        entryDate: _date(2026, 8),
        deleted: true,
      );
      await _insertDiary(database, id: 'old', entryDate: _date(2025, 1));
      await _insertRevision(
        database,
        diaryId: 'old',
        revisionNo: 2,
        entryDate: _date(2025, 1),
      );

      await _insertAtom(
        database,
        id: 'd1-a1',
        revisionId: 'd1-r1',
        observedAt: _date(2026, 6, 2),
        generation: 2,
      );
      await _insertAtom(
        database,
        id: 'd1-a2',
        revisionId: 'd1-r1',
        observedAt: _date(2026, 6, 8),
        generation: 2,
      );
      await _insertAtom(
        database,
        id: 'd2-a1',
        revisionId: 'd2-r1',
        observedAt: _date(2026, 7, 4),
        generation: 2,
      );
      await _insertAtom(
        database,
        id: 'd3-a1',
        revisionId: 'd3-r1',
        observedAt: _date(2026, 5, 3),
        generation: 2,
      );
      await _insertAtom(
        database,
        id: 'deleted-a1',
        revisionId: 'deleted-r1',
        observedAt: _date(2026, 8),
        generation: 2,
      );
      await _insertAtom(
        database,
        id: 'superseded-a1',
        revisionId: 'd3-r1',
        observedAt: _date(2026, 9),
        generation: 2,
        superseded: true,
      );
      await _insertAtom(
        database,
        id: 'old-a1',
        revisionId: 'old-r1',
        observedAt: _date(2026, 10),
        generation: 2,
      );

      for (final (id, title, status) in [
        ('recent', 'Recent thread', 'active'),
        ('older', 'Older thread', 'active'),
        ('deleted-only', 'Deleted source', 'active'),
        ('superseded-only', 'Superseded source', 'active'),
        ('old-revision-only', 'Old revision', 'active'),
        ('archived', 'Archived thread', 'archived'),
        ('merged', 'Merged thread', 'merged'),
      ]) {
        await _insertThread(
          database,
          id: id,
          title: title,
          generation: 2,
          status: status,
        );
      }
      for (final atomId in ['d1-a1', 'd1-a2', 'd2-a1']) {
        await _insertMembership(
          database,
          threadId: 'recent',
          atomId: atomId,
          generation: 2,
        );
      }
      await _insertMembership(
        database,
        threadId: 'older',
        atomId: 'd3-a1',
        generation: 2,
      );
      for (final pair in [
        ('deleted-only', 'deleted-a1'),
        ('superseded-only', 'superseded-a1'),
        ('old-revision-only', 'old-a1'),
        ('archived', 'd1-a1'),
        ('merged', 'd2-a1'),
      ]) {
        await _insertMembership(
          database,
          threadId: pair.$1,
          atomId: pair.$2,
          generation: 2,
        );
      }

      final result = await repository.getActiveThreads();

      expect(result.map((item) => item.id), ['recent', 'older']);
      expect(result.first.distinctDiaryCount, 2);
      expect(result.first.evidenceCount, 3);
      expect(result.first.firstSeen, _date(2026, 6, 2));
      expect(result.first.lastSeen, _date(2026, 7, 4));
      expect(result.last.distinctDiaryCount, 1);
    });

    test('overview pagination is bounded, stable, and complete', () async {
      const total = 53;
      final expected = <({String id, DateTime lastSeen})>[];
      for (var index = 0; index < total; index++) {
        final suffix = index.toString().padLeft(2, '0');
        final diaryId = 'page-diary-$suffix';
        final atomId = 'page-atom-$suffix';
        final threadId = 'page-thread-$suffix';
        final occurredAt = DateTime.utc(
          2026,
          1,
          1,
        ).add(Duration(days: index ~/ 2));
        await _insertDiary(database, id: diaryId, entryDate: occurredAt);
        await _insertAtom(
          database,
          id: atomId,
          revisionId: '$diaryId-r1',
          observedAt: occurredAt,
          generation: 1,
        );
        await _insertThread(
          database,
          id: threadId,
          title: 'Thread $suffix',
          generation: 1,
        );
        await _insertMembership(
          database,
          threadId: threadId,
          atomId: atomId,
          generation: 1,
        );
        expected.add((id: threadId, lastSeen: occurredAt));
      }
      expected.sort((left, right) {
        final time = right.lastSeen.compareTo(left.lastSeen);
        return time != 0 ? time : left.id.compareTo(right.id);
      });

      final first = await repository.getActiveThreads();
      final second = await repository.getActiveThreads(offset: first.length);
      final ids = [...first, ...second].map((thread) => thread.id).toList();

      expect(first, hasLength(50));
      expect(second, hasLength(3));
      expect(ids, expected.map((item) => item.id));
      expect(ids.toSet(), hasLength(total));
    });

    test('detail is newest-first and keeps Diary traceability', () async {
      await _insertDiary(database, id: 'a', entryDate: _date(2026, 1));
      await _insertDiary(database, id: 'b', entryDate: _date(2026, 2));
      await _insertAtom(
        database,
        id: 'a-atom',
        revisionId: 'a-r1',
        observedAt: _date(2026, 1, 20),
        generation: 1,
        statement: '跑步后思绪变得安静',
        quote: '跑步之后脑子安静了很多。',
      );
      await database.update(
        'memory_atoms',
        {'observed_at': null},
        where: 'id = ?',
        whereArgs: ['a-atom'],
      );
      await _insertAtom(
        database,
        id: 'b-atom',
        revisionId: 'b-r1',
        observedAt: _date(2026, 2, 20),
        generation: 1,
        statement: '跑步后焦虑有所减轻',
        quote: '今晚跑完步，焦虑减轻了一些。',
      );
      await _insertThread(
        database,
        id: 'running',
        title: '跑步与情绪恢复',
        generation: 1,
      );
      for (final atomId in ['a-atom', 'b-atom']) {
        await _insertMembership(
          database,
          threadId: 'running',
          atomId: atomId,
          generation: 1,
        );
      }

      final detail = await repository.getThreadDetail('running');

      expect(detail, isNotNull);
      expect(detail!.evidence.map((item) => item.atomId), ['b-atom', 'a-atom']);
      expect(detail.evidence.first.diaryId, 'b');
      expect(detail.evidence.first.statement, '跑步后焦虑有所减轻');
      expect(detail.evidence.first.sourceQuote, '今晚跑完步，焦虑减轻了一些。');
      expect(detail.evidence.first.occurredAt, _date(2026, 2, 20));
      expect(detail.evidence.last.occurredAt, _date(2026, 1));
    });

    test('source deletion and edit disappear on the next read', () async {
      await _insertDiary(database, id: 'a', entryDate: _date(2026, 1));
      await _insertDiary(database, id: 'b', entryDate: _date(2026, 2));
      for (final id in ['a', 'b']) {
        await _insertAtom(
          database,
          id: '$id-atom',
          revisionId: '$id-r1',
          observedAt: _date(2026, id == 'a' ? 1 : 2),
          generation: 1,
        );
      }
      await _insertThread(
        database,
        id: 'thread',
        title: 'Active sources',
        generation: 1,
      );
      for (final id in ['a', 'b']) {
        await _insertMembership(
          database,
          threadId: 'thread',
          atomId: '$id-atom',
          generation: 1,
        );
      }

      await database.update(
        'diary_entries',
        {'deleted_at': _date(2026, 3).toIso8601String()},
        where: 'id = ?',
        whereArgs: ['a'],
      );
      var detail = await repository.getThreadDetail('thread');
      expect(detail!.evidence.map((item) => item.diaryId), ['b']);

      await database.update(
        'memory_atoms',
        {'superseded_at': _date(2026, 3).toIso8601String()},
        where: 'id = ?',
        whereArgs: ['b-atom'],
      );
      detail = await repository.getThreadDetail('thread');
      expect(detail, isNull);
    });

    test('read state exposes only current live queue state', () async {
      await _insertDiary(database, id: 'a', entryDate: _date(2026, 1));
      await database.insert('self_engine_computations', {
        'id': 'computation-a',
        'source_hash': 'hash-a-r1',
        'fingerprint_version': 1,
        'pipeline_version': 1,
        'job_type': 'sourceChanged',
        'created_at': _date(2026, 1).toIso8601String(),
      });
      await database.insert('self_engine_jobs', {
        'id': 'job-a',
        'revision_id': 'a-r1',
        'computation_id': 'computation-a',
        'source_hash': 'hash-a-r1',
        'fingerprint_version': 1,
        'job_type': 'sourceChanged',
        'status': 'processing',
        'origin': 'live',
        'attempt_count': 1,
        'pipeline_version': 1,
        'generation': 1,
        'created_at': _date(2026, 1).toIso8601String(),
        'updated_at': _date(2026, 1).toIso8601String(),
        'lease_id': 'lease',
        'lease_expires_at': _date(2027, 1).toIso8601String(),
      });

      final state = await repository.getSelfEngineState();

      expect(state.hasLiveWork, isTrue);
      expect(state.hasFailedWork, isFalse);
    });
  });
}

DateTime _date(int year, int month, [int day = 1]) =>
    DateTime.utc(year, month, day);

Future<void> _insertDiary(
  Database database, {
  required String id,
  required DateTime entryDate,
  bool deleted = false,
}) async {
  final timestamp = entryDate.toIso8601String();
  await database.insert('diary_entries', {
    'id': id,
    'body': 'Diary $id',
    'entry_date': timestamp,
    'created_at': timestamp,
    'updated_at': timestamp,
    'image_ids': '[]',
    'tags': '[]',
    'ai_analyses': '[]',
    'is_favorite': 0,
    'deleted_at': deleted ? timestamp : null,
  });
  await _insertRevision(
    database,
    diaryId: id,
    revisionNo: 1,
    entryDate: entryDate,
  );
}

Future<void> _insertRevision(
  Database database, {
  required String diaryId,
  required int revisionNo,
  required DateTime entryDate,
}) async {
  final revisionId = '$diaryId-r$revisionNo';
  await database.insert('diary_revisions', {
    'id': revisionId,
    'diary_id': diaryId,
    'revision_no': revisionNo,
    'body': 'Diary $diaryId revision $revisionNo',
    'source_hash': 'hash-$revisionId',
    'fingerprint_version': 1,
    'entry_date': entryDate.toIso8601String(),
    'tags': '[]',
    'created_at': entryDate.toIso8601String(),
  });
}

Future<void> _insertAtom(
  Database database, {
  required String id,
  required String revisionId,
  required DateTime observedAt,
  required int generation,
  String statement = 'Statement',
  String quote = 'Source quote',
  bool superseded = false,
}) => database.insert('memory_atoms', {
  'id': id,
  'revision_id': revisionId,
  'kind': 'event',
  'statement': statement,
  'source_quote': quote,
  'observed_at': observedAt.toIso8601String(),
  'scope': 'state',
  'pipeline_version': 1,
  'generation': generation,
  'created_at': observedAt.toIso8601String(),
  'superseded_at': superseded ? observedAt.toIso8601String() : null,
});

Future<void> _insertThread(
  Database database, {
  required String id,
  required String title,
  required int generation,
  String status = 'active',
}) {
  final timestamp = _date(2026, 1).toIso8601String();
  return database.insert('memory_threads', {
    'id': id,
    'title': title,
    'description': 'Description for $title',
    'status': status,
    'first_seen': timestamp,
    'last_seen': timestamp,
    'pipeline_version': 1,
    'generation': generation,
    'created_at': timestamp,
    'updated_at': timestamp,
  });
}

Future<void> _insertMembership(
  Database database, {
  required String threadId,
  required String atomId,
  required int generation,
}) => database.insert('thread_memberships', {
  'thread_id': threadId,
  'atom_id': atomId,
  'relevance': 1.0,
  'origin': 'automatic',
  'generation': generation,
  'created_at': _date(2026, 1).toIso8601String(),
});
