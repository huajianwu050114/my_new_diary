import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/diary/data/local/diary_database_v2.dart';
import 'package:my_new_diary/features/diary/data/local/sqlite_diary_repository_v2.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';
import 'package:my_new_diary/features/self_engine/application/self_engine_job_recovery_v2.dart';
import 'package:my_new_diary/features/self_engine/data/local/sqlite_self_engine_repository_v2.dart';
import 'package:my_new_diary/features/self_engine/data/local/self_engine_outbox_writer_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/diary_source_fingerprint_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/self_engine_job_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/self_engine_derived_result_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/diary_revision_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/memory_atom_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/memory_thread_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/thread_membership_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/self_engine_retry_policy_v2.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late DiaryDatabaseV2 databaseOwner;
  late SqliteDiaryRepositoryV2 diaryRepository;
  late SqliteSelfEngineRepositoryV2 selfRepository;

  setUp(() async {
    databaseOwner = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => inMemoryDatabasePath,
    );
    final database = await databaseOwner.open();
    diaryRepository = SqliteDiaryRepositoryV2(database);
    selfRepository = SqliteSelfEngineRepositoryV2(database);
  });

  tearDown(() async {
    await diaryRepository.dispose();
    await databaseOwner.close();
  });

  test('fingerprint excludes derived and order-only changes', () {
    final original = _entry();
    final derivedOnly = original.copyWith(
      isFavorite: true,
      aiAnalyses: const ['reply'],
      contentDelta: '[{"insert":"A quiet morning","attributes":{"bold":true}}]',
      tags: const ['calm', 'daily'],
    );

    expect(
      DiarySourceFingerprintV2.calculate(derivedOnly),
      DiarySourceFingerprintV2.calculate(original),
    );
    expect(
      DiarySourceFingerprintV2.calculate(
        original.copyWith(body: 'A different morning'),
      ),
      isNot(DiarySourceFingerprintV2.calculate(original)),
    );
    expect(
      DiarySourceFingerprintV2.calculate(
        original.copyWith(body: 'Cafe\u0301', tags: const ['e\u0301']),
      ),
      DiarySourceFingerprintV2.calculate(
        original.copyWith(body: 'Café', tags: const ['é']),
      ),
    );
    expect(
      DiarySourceFingerprintV2.calculate(
        original.copyWith(
          location: const DiaryLocation(
            latitude: -0.0,
            longitude: 0.0,
            address: ' origin ',
          ),
        ),
      ),
      DiarySourceFingerprintV2.calculate(
        original.copyWith(
          location: const DiaryLocation(
            latitude: 0.0,
            longitude: -0.0,
            address: 'origin',
          ),
        ),
      ),
    );
    expect(
      () => DiarySourceFingerprintV2.calculate(
        original.copyWith(
          location: const DiaryLocation(latitude: double.nan, longitude: 0),
        ),
      ),
      throwsFormatException,
    );
  });

  test(
    'semantic edits append revisions without replacing diary identity',
    () async {
      final original = _entry();
      await diaryRepository.save(original);
      final firstRevision = await selfRepository.getLatestRevision(original.id);
      final database = await databaseOwner.open();
      final createdAt = DateTime.utc(2026, 1, 2).toIso8601String();
      await database.insert('memory_atoms', {
        'id': 'existing-atom',
        'revision_id': firstRevision!.id,
        'kind': 'event',
        'statement': 'Existing evidence',
        'source_quote': 'A quiet morning',
        'scope': 'state',
        'pipeline_version': 1,
        'generation': 1,
        'created_at': createdAt,
      });

      await diaryRepository.save(
        original.copyWith(
          body: 'A changed morning',
          contentDelta: '[{"insert":"A changed morning\\n"}]',
          updatedAt: DateTime.utc(2026, 1, 3),
        ),
      );

      final revisions = await selfRepository.getAllRevisions();
      expect((await diaryRepository.getById(original.id))?.id, original.id);
      expect(revisions, hasLength(2));
      expect(revisions.first.id, firstRevision.id);
      expect(await database.query('memory_atoms'), hasLength(1));
      expect(revisions.map((value) => value.body), [
        'A quiet morning',
        'A changed morning',
      ]);
    },
  );

  test(
    'job insertion failure rolls back diary and revision together',
    () async {
      await diaryRepository.save(_entry());
      final existingJobId = (await selfRepository.getJobs()).single.id;
      var call = 0;
      final failingRepository = SqliteDiaryRepositoryV2(
        await databaseOwner.open(),
        selfEngineOutbox: SelfEngineOutboxWriterV2(
          createId: () => call++ == 0 ? 'new-revision' : existingJobId,
        ),
      );
      try {
        await expectLater(
          failingRepository.save(_entry(id: 'rollback-entry')),
          throwsA(anything),
        );
        expect(await diaryRepository.getById('rollback-entry'), isNull);
        expect(
          (await selfRepository.getAllRevisions()).where(
            (value) => value.diaryId == 'rollback-entry',
          ),
          isEmpty,
        );
      } finally {
        await failingRepository.dispose();
      }
    },
  );

  test('favorite and AI reply changes do not append revision or job', () async {
    final original = _entry();
    await diaryRepository.save(original);

    await diaryRepository.setFavorite(original.id, isFavorite: true);
    await diaryRepository.save(
      original.copyWith(
        isFavorite: true,
        aiAnalyses: const ['AI reply'],
        updatedAt: DateTime.utc(2026, 1, 4),
      ),
    );

    expect(await selfRepository.getAllRevisions(), hasLength(1));
    expect(await selfRepository.getJobs(), hasLength(1));
  });

  test(
    'contentDelta-only formatting does not append revision or job',
    () async {
      final original = _entry();
      await diaryRepository.save(original);
      await diaryRepository.save(
        original.copyWith(
          contentDelta:
              '[{"insert":"A quiet morning","attributes":{"bold":true}}]',
          updatedAt: DateTime.utc(2026, 1, 4),
        ),
      );

      expect(await selfRepository.getAllRevisions(), hasLength(1));
      expect(await selfRepository.getJobs(), hasLength(1));
    },
  );

  test('same source is deduplicated and rapid edits remain bounded', () async {
    var entry = _entry();
    await diaryRepository.save(entry);
    await diaryRepository.save(entry);
    for (var index = 1; index <= 5; index++) {
      entry = entry.copyWith(
        body: 'Edit $index',
        updatedAt: DateTime.utc(2026, 1, 2, 8, index),
      );
      await diaryRepository.save(entry);
    }

    expect(await selfRepository.getAllRevisions(), hasLength(6));
    expect(await selfRepository.getJobs(), hasLength(6));
  });

  test('A to B to C to A keeps revision jobs but reuses computation', () async {
    final a = _entry();
    await diaryRepository.save(a);
    await diaryRepository.save(a.copyWith(body: 'B'));
    await diaryRepository.save(a.copyWith(body: 'C'));
    await diaryRepository.save(a);

    final revisions = await selfRepository.getAllRevisions();
    final jobs = await selfRepository.getJobs();
    final database = await databaseOwner.open();
    expect(revisions.map((value) => value.revisionNo), [1, 2, 3, 4]);
    expect(revisions.map((value) => value.body), [
      'A quiet morning',
      'B',
      'C',
      'A quiet morning',
    ]);
    expect(jobs, hasLength(4));
    expect(jobs.map((value) => value.revisionId).toSet(), {
      ...revisions.map((value) => value.id),
    });
    expect(revisions.first.sourceHash, revisions.last.sourceHash);
    expect(jobs.first.computationId, jobs.last.computationId);
    expect(await database.query('self_engine_computations'), hasLength(3));
  });

  test('processing job is recovered after a simulated crash', () async {
    await diaryRepository.save(_entry());
    final claimed = await selfRepository.claimNextJob(
      now: DateTime.utc(2026, 1, 2, 9),
    );
    expect(claimed?.status, SelfEngineJobStatusV2.processing);
    expect(claimed?.attemptCount, 1);

    final recovered = await selfRepository.recoverExpiredLeases(
      now: DateTime.utc(2026, 1, 2, 9, 6),
    );
    final jobs = await selfRepository.getJobs();

    expect(recovered, 1);
    expect(jobs.single.status, SelfEngineJobStatusV2.retryable);
    expect(jobs.single.attemptCount, 1);
  });

  test('retryable job is claimed only after its retry time', () async {
    await diaryRepository.save(_entry());
    final claimed = await selfRepository.claimNextJob(
      now: DateTime.utc(2026, 1, 2, 9),
    );
    await selfRepository.markJobFailed(
      claimed!.id,
      leaseId: claimed.leaseId!,
      failedAt: DateTime.utc(2026, 1, 2, 9),
      error: 'temporary failure',
    );

    expect(
      await selfRepository.claimNextJob(
        now: DateTime.utc(2026, 1, 2, 9, 0, 59),
      ),
      isNull,
    );
    final retried = await selfRepository.claimNextJob(
      now: DateTime.utc(2026, 1, 2, 9, 1),
    );
    expect(retried?.status, SelfEngineJobStatusV2.processing);
    expect(retried?.attemptCount, 2);
  });

  test('clearing derived data preserves raw diary and revisions', () async {
    await diaryRepository.save(_entry());
    final revision = (await selfRepository.getAllRevisions()).single;
    final database = await databaseOwner.open();
    final now = DateTime.utc(2026, 1, 2).toIso8601String();
    await database.insert('memory_atoms', {
      'id': 'atom-1',
      'revision_id': revision.id,
      'kind': 'event',
      'statement': 'A quiet morning happened.',
      'source_quote': 'A quiet morning',
      'scope': 'state',
      'pipeline_version': 1,
      'generation': 1,
      'created_at': now,
    });
    await database.insert('memory_threads', {
      'id': 'thread-1',
      'title': 'Quiet mornings',
      'description': '',
      'status': 'active',
      'first_seen': now,
      'last_seen': now,
      'pipeline_version': 1,
      'generation': 1,
      'created_at': now,
      'updated_at': now,
    });
    await database.insert('thread_memberships', {
      'thread_id': 'thread-1',
      'atom_id': 'atom-1',
      'relevance': 1.0,
      'origin': 'automatic',
      'generation': 1,
      'created_at': now,
    });

    await selfRepository.clearAllDerivedDataForGlobalRebuild();

    expect(await diaryRepository.getById('entry-1'), isNotNull);
    expect(await selfRepository.getAllRevisions(), hasLength(1));
    expect(await database.query('memory_atoms'), isEmpty);
    expect(await database.query('memory_threads'), isEmpty);
    expect(await database.query('thread_memberships'), isEmpty);
    expect(
      (await selfRepository.getJobs()).single.status,
      SelfEngineJobStatusV2.pending,
    );
    expect(
      () => database.insert('memory_atoms', {
        'id': 'stale-atom',
        'revision_id': revision.id,
        'kind': 'event',
        'statement': 'stale result',
        'source_quote': 'stale',
        'scope': 'state',
        'pipeline_version': 1,
        'generation': 1,
        'created_at': now,
      }),
      throwsA(anything),
      reason: 'a worker from the previous generation must not publish results',
    );
  });

  test('stale generation cannot update an atom', () async {
    await diaryRepository.save(_entry());
    final revision = (await selfRepository.getAllRevisions()).single;
    final database = await databaseOwner.open();
    final now = DateTime.utc(2026, 1, 2).toIso8601String();
    await database.insert('memory_atoms', {
      'id': 'old-atom',
      'revision_id': revision.id,
      'kind': 'event',
      'statement': 'Old statement',
      'source_quote': 'Old',
      'scope': 'state',
      'pipeline_version': 1,
      'generation': 1,
      'created_at': now,
    });
    await database.update('self_engine_state', {
      'generation': 2,
    }, where: 'id = 1');

    expect(
      () => database.update(
        'memory_atoms',
        {'statement': 'Stale atom update'},
        where: 'id = ?',
        whereArgs: ['old-atom'],
      ),
      throwsA(anything),
    );
  });

  test('stale generation cannot update a thread', () async {
    await diaryRepository.save(_entry());
    final database = await databaseOwner.open();
    final now = DateTime.utc(2026, 1, 2).toIso8601String();
    await database.insert('memory_threads', {
      'id': 'old-thread',
      'title': 'Old thread',
      'description': '',
      'status': 'active',
      'first_seen': now,
      'last_seen': now,
      'pipeline_version': 1,
      'generation': 1,
      'created_at': now,
      'updated_at': now,
    });
    await database.update('self_engine_state', {
      'generation': 2,
    }, where: 'id = 1');

    expect(
      () => database.update(
        'memory_threads',
        {'title': 'Stale thread update'},
        where: 'id = ?',
        whereArgs: ['old-thread'],
      ),
      throwsA(anything),
    );
  });

  test('stale generation cannot add a membership to current data', () async {
    await diaryRepository.save(_entry());
    final revision = (await selfRepository.getAllRevisions()).single;
    final database = await databaseOwner.open();
    final now = DateTime.utc(2026, 1, 2).toIso8601String();
    await selfRepository.clearAllDerivedDataForGlobalRebuild();
    await database.insert('memory_atoms', {
      'id': 'current-atom',
      'revision_id': revision.id,
      'kind': 'event',
      'statement': 'Current statement',
      'source_quote': 'Current',
      'scope': 'state',
      'pipeline_version': 1,
      'generation': 2,
      'created_at': now,
    });
    await database.insert('memory_threads', {
      'id': 'current-thread',
      'title': 'Current thread',
      'description': '',
      'status': 'active',
      'first_seen': now,
      'last_seen': now,
      'pipeline_version': 1,
      'generation': 2,
      'created_at': now,
      'updated_at': now,
    });

    expect(
      () => database.insert('thread_memberships', {
        'thread_id': 'current-thread',
        'atom_id': 'current-atom',
        'relevance': 1.0,
        'origin': 'automatic',
        'generation': 1,
        'created_at': now,
      }),
      throwsA(anything),
    );
  });

  test('generation invalidation rejects stale publish atomically', () async {
    await diaryRepository.save(_entry());
    final claimed = (await selfRepository.claimNextJob(
      now: DateTime.utc(2026, 1, 2, 9),
    ))!;
    await selfRepository.clearAllDerivedDataForGlobalRebuild();
    final publishedAt = DateTime.utc(2026, 1, 2, 9, 1);
    final staleResult = SelfEngineDerivedResultV2(
      atoms: [
        MemoryAtomV2(
          id: 'stale-publish-atom',
          revisionId: claimed.revisionId,
          kind: MemoryAtomKindV2.event,
          statement: 'Stale',
          sourceQuote: 'Stale',
          scope: MemoryAtomScopeV2.state,
          pipelineVersion: claimed.pipelineVersion,
          generation: claimed.generation,
          createdAt: publishedAt,
        ),
      ],
      threads: [
        MemoryThreadV2(
          id: 'stale-publish-thread',
          title: 'Stale',
          description: '',
          status: MemoryThreadStatusV2.active,
          firstSeen: publishedAt,
          lastSeen: publishedAt,
          pipelineVersion: claimed.pipelineVersion,
          generation: claimed.generation,
          createdAt: publishedAt,
          updatedAt: publishedAt,
        ),
      ],
      memberships: [
        ThreadMembershipV2(
          threadId: 'stale-publish-thread',
          atomId: 'stale-publish-atom',
          relevance: 1,
          origin: ThreadMembershipOriginV2.automatic,
          generation: claimed.generation,
          createdAt: publishedAt,
        ),
      ],
    );

    expect(
      await selfRepository.publishResult(
        claimed.id,
        leaseId: claimed.leaseId!,
        publishedAt: publishedAt,
        result: staleResult,
      ),
      isFalse,
    );
    final current = (await selfRepository.getJobs()).single;
    expect(current.status, SelfEngineJobStatusV2.pending);
    expect(current.generation, 2);
    final database = await databaseOwner.open();
    expect(await database.query('memory_atoms'), isEmpty);
    expect(await database.query('memory_threads'), isEmpty);
    expect(await database.query('thread_memberships'), isEmpty);
  });

  test('generation invalidation rejects stale fail', () async {
    await diaryRepository.save(_entry());
    final claimed = (await selfRepository.claimNextJob(
      now: DateTime.utc(2026, 1, 2, 9),
    ))!;
    await selfRepository.clearAllDerivedDataForGlobalRebuild();

    expect(
      await selfRepository.markJobFailed(
        claimed.id,
        leaseId: claimed.leaseId!,
        failedAt: DateTime.utc(2026, 1, 2, 9, 1),
        error: 'stale worker',
      ),
      isFalse,
    );
    final current = (await selfRepository.getJobs()).single;
    expect(current.status, SelfEngineJobStatusV2.pending);
    expect(current.generation, 2);
    expect(current.error, isNull);
  });

  test('foreign keys reject orphan revisions and jobs', () async {
    final database = await databaseOwner.open();
    final now = DateTime.utc(2026, 1, 2).toIso8601String();

    expect(
      () => database.insert('diary_revisions', {
        'id': 'orphan',
        'diary_id': 'missing',
        'revision_no': 1,
        'body': 'orphan',
        'source_hash': 'hash',
        'entry_date': now,
        'created_at': now,
      }),
      throwsA(anything),
    );

    await diaryRepository.save(_entry());
    final revision = (await selfRepository.getAllRevisions()).single;
    final job = (await selfRepository.getJobs()).single;
    expect(
      () => database.insert('self_engine_jobs', {
        'id': 'mismatched-job',
        'revision_id': revision.id,
        'computation_id': job.computationId,
        'source_hash': 'wrong-hash',
        'fingerprint_version': 1,
        'job_type': 'sourceChanged',
        'status': 'pending',
        'attempt_count': 0,
        'pipeline_version': 1,
        'generation': 1,
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(anything),
    );
    expect(
      () => database.update(
        'self_engine_jobs',
        {'status': 'processing'},
        where: 'id = ?',
        whereArgs: [job.id],
      ),
      throwsA(anything),
      reason: 'processing state must always have a lease owner and expiry',
    );
    final jobColumns = await database.rawQuery(
      'PRAGMA table_info(self_engine_jobs)',
    );
    expect(jobColumns.map((row) => row['name']), isNot(contains('diary_id')));
  });

  test('computation FK independently rejects a wrong computation', () async {
    await diaryRepository.save(_entry());
    await diaryRepository.save(_entry(id: 'other', body: 'Other source'));
    final database = await databaseOwner.open();
    final revisions = await selfRepository.getAllRevisions();
    final jobs = await selfRepository.getJobs();
    final revision = revisions.singleWhere(
      (value) => value.diaryId == 'entry-1',
    );
    final otherJob = jobs.singleWhere((value) => value.diaryId == 'other');
    final now = DateTime.utc(2026, 1, 2).toIso8601String();

    expect(
      () => database.insert('self_engine_jobs', {
        'id': 'wrong-computation-only',
        'revision_id': revision.id,
        'computation_id': otherJob.computationId,
        'source_hash': revision.sourceHash,
        'fingerprint_version': revision.fingerprintVersion,
        'job_type': 'sourceChanged',
        'status': 'pending',
        'attempt_count': 0,
        'pipeline_version': 1,
        'generation': 1,
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(anything),
    );
  });

  test('publish atom thread membership and completion are atomic', () async {
    await diaryRepository.save(_entry());
    final claimed = (await selfRepository.claimNextJob(
      now: DateTime.utc(2026, 1, 2, 9),
    ))!;
    final now = DateTime.utc(2026, 1, 2, 9, 1);
    final result = SelfEngineDerivedResultV2(
      atoms: [
        MemoryAtomV2(
          id: 'atom-published',
          revisionId: claimed.revisionId,
          kind: MemoryAtomKindV2.event,
          statement: 'A quiet morning happened.',
          sourceQuote: 'A quiet morning',
          scope: MemoryAtomScopeV2.state,
          pipelineVersion: claimed.pipelineVersion,
          generation: claimed.generation,
          createdAt: now,
        ),
      ],
      threads: [
        MemoryThreadV2(
          id: 'thread-published',
          title: 'Quiet mornings',
          description: '',
          status: MemoryThreadStatusV2.active,
          firstSeen: now,
          lastSeen: now,
          pipelineVersion: claimed.pipelineVersion,
          generation: claimed.generation,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      memberships: [
        ThreadMembershipV2(
          threadId: 'thread-published',
          atomId: 'atom-published',
          relevance: 1,
          origin: ThreadMembershipOriginV2.automatic,
          generation: claimed.generation,
          createdAt: now,
        ),
      ],
    );

    expect(
      await selfRepository.publishResult(
        claimed.id,
        leaseId: claimed.leaseId!,
        publishedAt: now,
        result: result,
      ),
      isTrue,
    );
    final database = await databaseOwner.open();
    expect(await database.query('memory_atoms'), hasLength(1));
    expect(await database.query('memory_threads'), hasLength(1));
    expect(await database.query('thread_memberships'), hasLength(1));
    expect(
      (await selfRepository.getJobs()).single.status,
      SelfEngineJobStatusV2.completed,
    );
  });

  test('failed publish rolls back derived rows and job completion', () async {
    await diaryRepository.save(_entry());
    final claimed = (await selfRepository.claimNextJob(
      now: DateTime.utc(2026, 1, 2, 9),
    ))!;
    final now = DateTime.utc(2026, 1, 2, 9, 1);
    final bad = SelfEngineDerivedResultV2(
      atoms: [
        MemoryAtomV2(
          id: 'atom-rolled-back',
          revisionId: claimed.revisionId,
          kind: MemoryAtomKindV2.event,
          statement: 'Statement',
          sourceQuote: 'Quote',
          scope: MemoryAtomScopeV2.state,
          pipelineVersion: claimed.pipelineVersion,
          generation: claimed.generation,
          createdAt: now,
        ),
      ],
      memberships: [
        ThreadMembershipV2(
          threadId: 'missing-thread',
          atomId: 'atom-rolled-back',
          relevance: 1,
          origin: ThreadMembershipOriginV2.automatic,
          generation: claimed.generation,
          createdAt: now,
        ),
      ],
    );

    await expectLater(
      selfRepository.publishResult(
        claimed.id,
        leaseId: claimed.leaseId!,
        publishedAt: now,
        result: bad,
      ),
      throwsA(anything),
    );
    final database = await databaseOwner.open();
    expect(await database.query('memory_atoms'), isEmpty);
    expect(
      (await selfRepository.getJobs()).single.status,
      SelfEngineJobStatusV2.processing,
    );
  });

  test('same revision ID with different content is rejected', () async {
    await diaryRepository.save(_entry());
    final original = (await selfRepository.getAllRevisions()).single;
    final changedEntry = _entry(body: 'Conflicting content');
    final conflicting = DiaryRevisionV2(
      id: original.id,
      diaryId: original.diaryId,
      revisionNo: original.revisionNo,
      body: changedEntry.body,
      contentDelta: changedEntry.contentDelta,
      sourceHash: DiarySourceFingerprintV2.calculate(changedEntry),
      entryDate: changedEntry.entryDate,
      mood: changedEntry.mood,
      tags: changedEntry.tags,
      latitude: changedEntry.location?.latitude,
      longitude: changedEntry.location?.longitude,
      address: changedEntry.location?.address,
      createdAt: original.createdAt,
    );
    await expectLater(
      selfRepository.restoreRevision(conflicting),
      throwsStateError,
    );
    expect((await selfRepository.getAllRevisions()).single.body, original.body);
  });

  test('expired lease rejects stale worker and grants a new token', () async {
    await diaryRepository.save(_entry());
    final first = await selfRepository.claimNextJob(
      now: DateTime.utc(2026, 1, 2, 9),
    );
    expect(first?.leaseId, isNotNull);
    expect(
      await selfRepository.claimNextJob(now: DateTime.utc(2026, 1, 2, 9, 1)),
      isNull,
    );

    await selfRepository.recoverExpiredLeases(
      now: DateTime.utc(2026, 1, 2, 9, 6),
    );
    final second = await selfRepository.claimNextJob(
      now: DateTime.utc(2026, 1, 2, 9, 7),
    );
    expect(second?.leaseId, isNot(first?.leaseId));
    expect(
      await selfRepository.publishResult(
        first!.id,
        leaseId: first.leaseId!,
        publishedAt: DateTime.utc(2026, 1, 2, 9, 7, 1),
        result: const SelfEngineDerivedResultV2(),
      ),
      isFalse,
    );
    expect(
      await selfRepository.publishResult(
        second!.id,
        leaseId: second.leaseId!,
        publishedAt: DateTime.utc(2026, 1, 2, 9, 7, 1),
        result: const SelfEngineDerivedResultV2(),
      ),
      isTrue,
    );
  });

  test(
    'poison job reaches terminal failure without starving later work',
    () async {
      selfRepository = SqliteSelfEngineRepositoryV2(
        await databaseOwner.open(),
        retryPolicy: const SelfEngineRetryPolicyV2(
          maxAttempts: 3,
          baseDelay: Duration(seconds: 10),
          maxDelay: Duration(seconds: 30),
        ),
      );
      await diaryRepository.save(_entry(id: 'poison'));
      await diaryRepository.save(_entry(id: 'later', body: 'Later work'));
      var now = DateTime.utc(2026, 1, 2, 10);
      var poison = await selfRepository.claimNextJob(now: now);
      expect(poison?.diaryId, 'poison');
      await selfRepository.markJobFailed(
        poison!.id,
        leaseId: poison.leaseId!,
        failedAt: now,
        error: 'bad input',
      );

      final later = await selfRepository.claimNextJob(now: now);
      expect(later?.diaryId, 'later');
      await selfRepository.publishResult(
        later!.id,
        leaseId: later.leaseId!,
        publishedAt: now,
        result: const SelfEngineDerivedResultV2(),
      );

      now = now.add(const Duration(seconds: 10));
      poison = await selfRepository.claimNextJob(now: now);
      await selfRepository.markJobFailed(
        poison!.id,
        leaseId: poison.leaseId!,
        failedAt: now,
        error: 'bad input',
      );
      now = now.add(const Duration(seconds: 20));
      poison = await selfRepository.claimNextJob(now: now);
      await selfRepository.markJobFailed(
        poison!.id,
        leaseId: poison.leaseId!,
        failedAt: now,
        error: 'bad input',
      );
      expect(
        (await selfRepository.getJobs(
          status: SelfEngineJobStatusV2.failed,
        )).single.diaryId,
        'poison',
      );
    },
  );

  test(
    'per-diary rebuild invalidates an affected thread and requeues survivors',
    () async {
      await diaryRepository.save(_entry(id: 'a'));
      await diaryRepository.save(_entry(id: 'b', body: 'B'));
      final revisions = await selfRepository.getAllRevisions();
      final database = await databaseOwner.open();
      final now = DateTime.utc(2026, 1, 2).toIso8601String();
      for (final revision in revisions) {
        await database.insert('memory_atoms', {
          'id': 'atom-${revision.diaryId}',
          'revision_id': revision.id,
          'kind': 'event',
          'statement': revision.body,
          'source_quote': revision.body,
          'scope': 'state',
          'pipeline_version': 1,
          'generation': 1,
          'created_at': now,
        });
      }
      await database.insert('memory_threads', {
        'id': 'shared',
        'title': 'Shared',
        'description': '',
        'status': 'active',
        'first_seen': now,
        'last_seen': now,
        'pipeline_version': 1,
        'generation': 1,
        'created_at': now,
        'updated_at': now,
      });
      for (final revision in revisions) {
        await database.insert('thread_memberships', {
          'thread_id': 'shared',
          'atom_id': 'atom-${revision.diaryId}',
          'relevance': 1.0,
          'origin': 'automatic',
          'generation': 1,
          'created_at': now,
        });
      }

      await selfRepository.rebuildDerivedDataForDiary('a');
      expect(await database.query('memory_threads'), isEmpty);
      expect(await database.query('memory_atoms'), hasLength(1));
      expect(await database.query('thread_memberships'), isEmpty);
      expect(
        (await database.query('thread_link_jobs')).single['revision_id'],
        revisions.singleWhere((revision) => revision.diaryId == 'b').id,
      );
    },
  );

  test(
    'legacy diary backfill is incremental idempotent and resumable',
    () async {
      final database = await databaseOwner.open();
      final mapperTime = DateTime.utc(2026, 1, 2);
      for (final id in ['legacy-a', 'legacy-b', 'legacy-c']) {
        await database.insert('diary_entries', {
          'id': id,
          'body': id,
          'entry_date': mapperTime.toIso8601String(),
          'created_at': mapperTime.toIso8601String(),
          'updated_at': mapperTime.toIso8601String(),
        });
      }
      expect(await selfRepository.backfillMissingRevisions(limit: 1), 1);
      final recovery = SelfEngineJobRecoveryV2(selfRepository);
      expect(await recovery.reconcileLegacyDiaries(limit: 1), 2);
      expect(await recovery.reconcileLegacyDiaries(limit: 1), 0);
      expect(await selfRepository.getAllRevisions(), hasLength(3));
      expect(await selfRepository.getJobs(), hasLength(3));
    },
  );

  test(
    'v10 to v11 migration preserves diary and snapshots it on edit',
    () async {
      await diaryRepository.dispose();
      await databaseOwner.close();
      final directory = await Directory.systemTemp.createTemp('diary-v10-v11-');
      final databasePath = path.join(directory.path, 'diary.db');
      final oldDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 10,
          onCreate: (database, _) => _createV10DiaryTable(database),
        ),
      );
      final timestamp = DateTime.utc(2026, 1, 1).toIso8601String();
      await oldDatabase.insert('diary_entries', {
        'id': 'legacy-entry',
        'body': 'Before upgrade',
        'content_delta': '[{"insert":"Before upgrade\\n"}]',
        'entry_date': timestamp,
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      await oldDatabase.insert('custom_festivals', {
        'id': 'festival-1',
        'name': 'Preserved',
        'month': 1,
        'day': 2,
        'created_at': timestamp,
      });
      await oldDatabase.insert('life_fragments', {
        'id': 'fragment-1',
        'title': 'Preserved guide',
        'core_insight': '',
        'context': '',
        'evidence': '',
        'future_use': '',
        'message_to_future_self': '',
        'theme': '',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      await oldDatabase.insert('life_fragment_revisions', {
        'id': 'fragment-revision-1',
        'fragment_id': 'fragment-1',
        'snapshot_json': '{"title":"Before upgrade"}',
        'created_at': timestamp,
      });
      await oldDatabase.insert('life_spaces', {
        'id': 'space-1',
        'name': 'Preserved space',
        'icon_code_point': 1,
        'color_value': 1,
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      await oldDatabase.insert('life_documents', {
        'id': 'document-1',
        'space': 'space-1',
        'title': 'Preserved document',
        'markdown': 'text',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      await oldDatabase.close();

      final upgradedOwner = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => databasePath,
      );
      final upgradedDiary = SqliteDiaryRepositoryV2(await upgradedOwner.open());
      final upgradedSelf = SqliteSelfEngineRepositoryV2(
        await upgradedOwner.open(),
      );
      try {
        final legacy = await upgradedDiary.getById('legacy-entry');
        expect(legacy?.body, 'Before upgrade');
        final upgradedDatabase = await upgradedOwner.open();
        expect(await upgradedDatabase.query('custom_festivals'), hasLength(1));
        expect(await upgradedDatabase.query('life_fragments'), hasLength(1));
        expect(
          await upgradedDatabase.query('life_fragment_revisions'),
          hasLength(1),
        );
        expect(await upgradedDatabase.query('life_spaces'), hasLength(1));
        expect(await upgradedDatabase.query('life_documents'), hasLength(1));
        await upgradedDiary.save(
          legacy!.copyWith(
            body: 'After upgrade',
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
        );
        expect(
          (await upgradedSelf.getAllRevisions()).map((value) => value.body),
          ['Before upgrade', 'After upgrade'],
        );
      } finally {
        await upgradedDiary.dispose();
        await upgradedOwner.close();
        await directory.delete(recursive: true);
        databaseOwner = DiaryDatabaseV2(
          factory: databaseFactoryFfi,
          databasePath: () async => inMemoryDatabasePath,
        );
        diaryRepository = SqliteDiaryRepositoryV2(await databaseOwner.open());
      }
    },
  );

  test(
    'malformed v11 schema fails validation instead of silent repair',
    () async {
      await diaryRepository.dispose();
      await databaseOwner.close();
      final directory = await Directory.systemTemp.createTemp('diary-bad-v11-');
      final databasePath = path.join(directory.path, 'diary.db');
      final malformed = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 11,
          onCreate: (database, _) async {
            await _createV10DiaryTable(database);
            await database.execute(
              'CREATE TABLE self_engine_state (id INTEGER PRIMARY KEY)',
            );
          },
        ),
      );
      await malformed.close();
      final owner = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => databasePath,
      );
      try {
        await expectLater(owner.open(), throwsStateError);
      } finally {
        await owner.close();
        await directory.delete(recursive: true);
        databaseOwner = DiaryDatabaseV2(
          factory: databaseFactoryFfi,
          databasePath: () async => inMemoryDatabasePath,
        );
        diaryRepository = SqliteDiaryRepositoryV2(await databaseOwner.open());
        selfRepository = SqliteSelfEngineRepositoryV2(
          await databaseOwner.open(),
        );
      }
    },
  );
}

Future<void> _createV10DiaryTable(Database database) async {
  await database.execute('''
    CREATE TABLE diary_entries (
      id TEXT PRIMARY KEY NOT NULL,
      body TEXT NOT NULL,
      content_delta TEXT,
      entry_date TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      image_ids TEXT NOT NULL DEFAULT '[]',
      mood TEXT,
      tags TEXT NOT NULL DEFAULT '[]',
      latitude REAL,
      longitude REAL,
      address TEXT,
      ai_analyses TEXT NOT NULL DEFAULT '[]',
      is_favorite INTEGER NOT NULL DEFAULT 0,
      deleted_at TEXT
    )
  ''');
  await database.execute('''
    CREATE TABLE custom_festivals (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      month INTEGER NOT NULL,
      day INTEGER NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE life_fragments (
      id TEXT PRIMARY KEY NOT NULL,
      title TEXT NOT NULL,
      core_insight TEXT NOT NULL,
      context TEXT NOT NULL,
      evidence TEXT NOT NULL,
      future_use TEXT NOT NULL,
      message_to_future_self TEXT NOT NULL,
      theme TEXT NOT NULL,
      tags TEXT NOT NULL DEFAULT '[]',
      source_diary_ids TEXT NOT NULL DEFAULT '[]',
      is_rope INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'draft',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE life_fragment_revisions (
      id TEXT PRIMARY KEY NOT NULL,
      fragment_id TEXT NOT NULL,
      snapshot_json TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE life_spaces (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      icon_code_point INTEGER NOT NULL,
      color_value INTEGER NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_system INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE life_documents (
      id TEXT PRIMARY KEY NOT NULL,
      space TEXT NOT NULL,
      title TEXT NOT NULL,
      markdown TEXT NOT NULL,
      document_type TEXT NOT NULL DEFAULT 'note',
      document_date TEXT,
      template_id TEXT,
      tags TEXT NOT NULL DEFAULT '[]',
      is_pinned INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
  ''');
}

DiaryEntryV2 _entry({String id = 'entry-1', String body = 'A quiet morning'}) {
  final timestamp = DateTime.utc(2026, 1, 2, 8);
  return DiaryEntryV2(
    id: id,
    body: body,
    contentDelta: '[{"insert":"A quiet morning\\n"}]',
    entryDate: DateTime.utc(2026, 1, 2),
    createdAt: timestamp,
    updatedAt: timestamp,
    mood: 'calm',
    tags: const ['daily', 'calm'],
    location: const DiaryLocation(
      latitude: 22.3193,
      longitude: 114.1694,
      address: 'Hong Kong',
    ),
  );
}
