import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_new_diary/features/ai/data/ai_configuration_store_v2.dart';
import 'package:my_new_diary/features/ai/data/gemini_rest_client_v2.dart';
import 'package:my_new_diary/features/diary/data/local/diary_database_v2.dart';
import 'package:my_new_diary/features/diary/data/local/sqlite_diary_repository_v2.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';
import 'package:my_new_diary/features/self_engine/application/memory_atom_job_processor_v2.dart';
import 'package:my_new_diary/features/self_engine/application/memory_atom_validator_v2.dart';
import 'package:my_new_diary/features/self_engine/application/configured_self_engine_availability_v2.dart';
import 'package:my_new_diary/features/self_engine/application/ports/memory_extractor_v2.dart';
import 'package:my_new_diary/features/self_engine/application/ports/self_engine_availability_v2.dart';
import 'package:my_new_diary/features/self_engine/application/ports/self_engine_runner_v2.dart';
import 'package:my_new_diary/features/self_engine/application/self_engine_job_recovery_v2.dart';
import 'package:my_new_diary/features/self_engine/application/self_engine_lifecycle_maintenance_v2.dart';
import 'package:my_new_diary/features/self_engine/application/self_engine_worker_v2.dart';
import 'package:my_new_diary/features/self_engine/data/ai/ai_memory_extractor_v2.dart';
import 'package:my_new_diary/features/self_engine/data/local/sqlite_self_engine_repository_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/diary_revision_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/memory_atom_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/memory_extraction_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/self_engine_derived_result_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/self_engine_job_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/source_computation_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/self_engine_retry_policy_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/self_engine_pipeline_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Memory Atom validator', () {
    const validator = MemoryAtomValidatorV2();
    final revision = _revision('今天跑了五公里。我很累，但决定明天休息。');

    test('accepts exact evidence and derives omitted offsets', () {
      final atoms = validator.validate(
        revision,
        _batch([
          _candidate(kind: 'event', statement: '今天跑了五公里', quote: '今天跑了五公里'),
        ]),
      );

      expect(atoms, hasLength(1));
      expect(atoms.single.sourceStart, 0);
      expect(atoms.single.sourceEnd, 7);
    });

    test('allows a valid zero-atom result', () {
      expect(validator.validate(revision, _batch(const [])), isEmpty);
    });

    test('rejects all-invalid kinds, traits, and hallucinated evidence', () {
      expect(
        () => validator.validate(
          revision,
          _batch([
            _candidate(
              kind: 'personalityTrait',
              statement: '作者很自律',
              quote: '今天跑了五公里',
            ),
            _candidate(kind: 'belief', statement: '作者永远乐观', quote: '文中不存在'),
          ]),
        ),
        throwsA(isA<MemoryExtractionValidationFailureV2>()),
      );
    });

    test('accepts the valid subset of a mixed result', () {
      final atoms = validator.validate(
        revision,
        _batch([
          _candidate(
            kind: 'feeling',
            statement: 'A supported feeling',
            quote: revision.body,
          ),
          _candidate(
            kind: 'unknownKind',
            statement: 'Bad kind',
            quote: revision.body,
          ),
          _candidate(
            kind: 'belief',
            statement: 'Hallucinated',
            quote: 'missing quote',
          ),
        ]),
      );

      expect(atoms, hasLength(1));
      expect(atoms.single.kind, MemoryAtomKindV2.feeling);
    });

    test('drops duplicates and mismatched offsets', () {
      final atoms = validator.validate(
        revision,
        _batch([
          _candidate(kind: 'feeling', statement: '感到很累', quote: '我很累'),
          _candidate(kind: 'feeling', statement: '感到很累', quote: '我很累'),
          _candidate(
            kind: 'decision',
            statement: '决定明天休息',
            quote: '决定明天休息',
            start: 0,
            end: 6,
          ),
        ]),
      );

      expect(atoms, hasLength(1));
      expect(atoms.single.kind, MemoryAtomKindV2.feeling);
    });

    test('rejects an over-limit batch as a severe result failure', () {
      final candidates = List.generate(
        7,
        (index) =>
            _candidate(kind: 'event', statement: '事件 $index', quote: '今天跑了五公里'),
      );

      expect(
        () => validator.validate(revision, _batch(candidates)),
        throwsA(isA<MemoryExtractionValidationFailureV2>()),
      );
    });
  });

  group('Memory Atom worker', () {
    late DiaryDatabaseV2 databaseOwner;
    late SqliteDiaryRepositoryV2 diaryRepository;
    late SqliteSelfEngineRepositoryV2 selfRepository;
    late _FakeExtractor extractor;
    late DateTime now;

    setUp(() async {
      databaseOwner = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => inMemoryDatabasePath,
      );
      final database = await databaseOwner.open();
      diaryRepository = SqliteDiaryRepositoryV2(database);
      selfRepository = SqliteSelfEngineRepositoryV2(database);
      extractor = _FakeExtractor(
        (revision) async => _batch([
          _candidate(
            kind: 'event',
            statement: '记录了：${revision.body}',
            quote: revision.body,
          ),
        ]),
      );
      now = DateTime.utc(2026, 8, 1, 9);
    });

    tearDown(() async {
      await diaryRepository.dispose();
      await databaseOwner.close();
    });

    SelfEngineWorkerV2 worker({
      SelfEngineAvailabilityV2 availability = const _Availability(true),
      Duration leaseDuration = const Duration(minutes: 5),
      Duration heartbeatInterval = const Duration(minutes: 1),
    }) => SelfEngineWorkerV2(
      repository: selfRepository,
      processor: MemoryAtomJobProcessorV2(
        repository: selfRepository,
        extractor: extractor,
        clock: () => now,
        leaseDuration: leaseDuration,
        heartbeatInterval: heartbeatInterval,
      ),
      availability: availability,
      clock: () => now,
      leaseDuration: leaseDuration,
    );

    test(
      'valid extraction persists cache, atoms, and completion atomically',
      () async {
        await diaryRepository.save(_entry(body: 'A'));

        expect(await worker().runOnce(), SelfEngineRunResultV2.completed);
        final job = (await selfRepository.getJobs()).single;
        final atoms = await selfRepository.getAtomsForRevision(job.revisionId);
        final cached = await selfRepository.getComputationResult(
          job.computationId,
        );

        expect(job.status, SelfEngineJobStatusV2.completed);
        expect(atoms.single.revisionId, job.revisionId);
        expect(atoms.single.sourceQuote, 'A');
        expect(cached?.atoms, hasLength(1));
        expect(cached?.extractorVersion, 1);
        expect(cached?.promptVersion, 1);
        expect(cached?.modelIdentifier, 'fake:model');
      },
    );

    test('zero atoms is cached and completes the job', () async {
      extractor.handler = (_) async => _batch(const []);
      await diaryRepository.save(_entry(body: 'ordinary'));

      expect(await worker().runOnce(), SelfEngineRunResultV2.completed);
      final job = (await selfRepository.getJobs()).single;
      expect(await selfRepository.getAtomsForRevision(job.revisionId), isEmpty);
      expect(
        (await selfRepository.getComputationResult(job.computationId))?.atoms,
        isEmpty,
      );
    });

    test(
      'all-invalid extraction retries without caching an empty result',
      () async {
        extractor.handler = (revision) async => _batch([
          _candidate(
            kind: 'event',
            statement: 'Unsupported evidence',
            quote: 'not in the revision',
          ),
          _candidate(
            kind: 'invalidKind',
            statement: 'Invalid kind',
            quote: revision.body,
          ),
        ]);
        await diaryRepository.save(_entry(body: 'actual evidence'));

        expect(await worker().runOnce(), SelfEngineRunResultV2.retryScheduled);
        final job = (await selfRepository.getJobs()).single;
        expect(job.status, SelfEngineJobStatusV2.retryable);
        expect(job.attemptCount, 1);
        expect(
          await selfRepository.getComputationResult(job.computationId),
          isNull,
        );
        expect(
          await selfRepository.getAtomsForRevision(job.revisionId),
          isEmpty,
        );
      },
    );

    test(
      'A to B to C to A keeps four histories and reuses three computations',
      () async {
        final run = worker();
        for (final body in const ['A', 'B', 'C', 'A']) {
          await diaryRepository.save(
            _entry(
              body: body,
              updatedAt: now = now.add(const Duration(days: 1)),
            ),
          );
          expect(await run.runOnce(), SelfEngineRunResultV2.completed);
        }

        final revisions = await selfRepository.getRevisionsForDiary('diary-1');
        final jobs = await selfRepository.getJobs();
        final database = await databaseOwner.open();
        expect(revisions, hasLength(4));
        expect(revisions.map((value) => value.revisionNo), [1, 2, 3, 4]);
        expect(jobs, hasLength(4));
        expect(jobs.map((value) => value.revisionId).toSet(), hasLength(4));
        expect(await database.query('self_engine_computations'), hasLength(3));
        expect(
          await database.query('self_engine_computation_results'),
          hasLength(3),
        );
        expect(extractor.calls, 3);
        final firstA = await selfRepository.getAtomsForRevision(
          revisions[0].id,
        );
        final secondA = await selfRepository.getAtomsForRevision(
          revisions[3].id,
        );
        expect(firstA.single.id, isNot(secondA.single.id));
        expect(firstA.single.revisionId, revisions[0].id);
        expect(secondA.single.revisionId, revisions[3].id);
        expect(firstA.single.statement, secondA.single.statement);
      },
    );

    test('unavailable AI does not claim or burn an attempt', () async {
      await diaryRepository.save(_entry());

      expect(
        await worker(availability: const _Availability(false)).runOnce(),
        SelfEngineRunResultV2.unavailable,
      );
      final job = (await selfRepository.getJobs()).single;
      expect(job.status, SelfEngineJobStatusV2.pending);
      expect(job.attemptCount, 0);
      expect(extractor.calls, 0);
    });

    test(
      'resume reconciliation creates historical work that is not claimed',
      () async {
        await diaryRepository.restoreFromBackup(
          _entry(id: 'legacy', body: 'legacy private text'),
        );
        final run = worker();

        await SelfEngineLifecycleMaintenanceV2(
          recovery: SelfEngineJobRecoveryV2(selfRepository),
          runner: run,
        ).afterResume();

        final job = (await selfRepository.getJobs()).single;
        expect(job.origin, SelfEngineJobOriginV2.historical);
        expect(job.status, SelfEngineJobStatusV2.pending);
        expect(job.attemptCount, 0);
        expect(extractor.calls, 0);
      },
    );

    test('cold-start recovery does not upload a legacy diary', () async {
      await diaryRepository.restoreFromBackup(
        _entry(id: 'legacy-cold', body: 'cold-start history'),
      );
      final recovery = SelfEngineJobRecoveryV2(selfRepository);
      await recovery.afterColdStart(now: now);
      await recovery.reconcileLegacyDiaries();

      expect(await worker().runOnce(), SelfEngineRunResultV2.noWork);
      final job = (await selfRepository.getJobs()).single;
      expect(job.origin, SelfEngineJobOriginV2.historical);
      expect(job.status, SelfEngineJobStatusV2.pending);
      expect(job.attemptCount, 0);
      expect(extractor.calls, 0);
    });

    test('live work bypasses historical backlog without burning it', () async {
      await diaryRepository.restoreFromBackup(
        _entry(id: 'legacy', body: 'historical backlog'),
      );
      await selfRepository.backfillMissingRevisions();
      await diaryRepository.save(_entry(id: 'live', body: 'new live diary'));
      final before = await selfRepository.getJobs();
      expect(
        before.singleWhere((job) => job.diaryId == 'legacy').origin,
        SelfEngineJobOriginV2.historical,
      );
      expect(
        before.singleWhere((job) => job.diaryId == 'live').origin,
        SelfEngineJobOriginV2.live,
      );

      expect(await worker().runOnce(), SelfEngineRunResultV2.completed);

      final after = await selfRepository.getJobs();
      final historical = after.singleWhere((job) => job.diaryId == 'legacy');
      final live = after.singleWhere((job) => job.diaryId == 'live');
      expect(historical.status, SelfEngineJobStatusV2.pending);
      expect(historical.attemptCount, 0);
      expect(live.status, SelfEngineJobStatusV2.completed);
      expect(extractor.calls, 1);
    });

    test(
      'permanent delete prunes private cache only after its last reference',
      () async {
        final run = worker();
        await diaryRepository.save(
          _entry(id: 'shared-a', body: 'shared quote'),
        );
        expect(await run.runOnce(), SelfEngineRunResultV2.completed);
        await diaryRepository.save(
          _entry(id: 'shared-b', body: 'shared quote'),
        );
        expect(await run.runOnce(), SelfEngineRunResultV2.completed);
        final database = await databaseOwner.open();
        expect(await database.query('self_engine_computations'), hasLength(1));
        expect(
          await database.query('self_engine_computation_results'),
          hasLength(1),
        );

        await diaryRepository.deletePermanently('shared-a');

        expect(await selfRepository.getRevisionsForDiary('shared-a'), isEmpty);
        expect(
          (await selfRepository.getJobs()).where(
            (job) => job.diaryId == 'shared-a',
          ),
          isEmpty,
        );
        expect(await database.query('memory_atoms'), hasLength(1));
        expect(await database.query('self_engine_computations'), hasLength(1));
        expect(
          await database.query('self_engine_computation_results'),
          hasLength(1),
        );

        await diaryRepository.deletePermanently('shared-b');

        expect(await database.query('diary_revisions'), isEmpty);
        expect(await database.query('self_engine_jobs'), isEmpty);
        expect(await database.query('memory_atoms'), isEmpty);
        expect(await database.query('self_engine_computations'), isEmpty);
        expect(
          await database.query('self_engine_computation_results'),
          isEmpty,
        );
        expect(
          await database.rawQuery(
            "SELECT result_json FROM self_engine_computation_results "
            "WHERE result_json LIKE '%shared quote%'",
          ),
          isEmpty,
        );
      },
    );

    test('heartbeat renews the active lease during slow extraction', () async {
      final started = Completer<void>();
      final release = Completer<MemoryExtractionBatchV2>();
      extractor.handler = (revision) {
        started.complete();
        return release.future;
      };
      await diaryRepository.save(_entry(body: 'slow'));
      final liveWorker = SelfEngineWorkerV2(
        repository: selfRepository,
        processor: MemoryAtomJobProcessorV2(
          repository: selfRepository,
          extractor: extractor,
          leaseDuration: const Duration(seconds: 2),
          heartbeatInterval: const Duration(milliseconds: 50),
        ),
        availability: const _Availability(true),
        leaseDuration: const Duration(seconds: 2),
      );
      final running = liveWorker.runOnce();
      await started.future;
      final initialExpiry =
          (await selfRepository.getJobs()).single.leaseExpiresAt!;

      await Future<void>.delayed(const Duration(milliseconds: 180));
      final renewedExpiry =
          (await selfRepository.getJobs()).single.leaseExpiresAt!;
      release.complete(
        _batch([_candidate(kind: 'event', statement: 'slow', quote: 'slow')]),
      );

      expect(renewedExpiry.isAfter(initialExpiry), isTrue);
      expect(await running, SelfEngineRunResultV2.completed);
    });

    test(
      'a trigger during extraction gets a single-flight follow-up',
      () async {
        final started = Completer<void>();
        final releaseFirst = Completer<void>();
        var activeExtractions = 0;
        var maxConcurrentExtractions = 0;
        extractor.handler = (revision) async {
          activeExtractions++;
          if (activeExtractions > maxConcurrentExtractions) {
            maxConcurrentExtractions = activeExtractions;
          }
          try {
            if (revision.body == 'first') {
              if (!started.isCompleted) started.complete();
              await releaseFirst.future;
            }
            return _batch([
              _candidate(
                kind: 'event',
                statement: 'Observed ${revision.body}',
                quote: revision.body,
              ),
            ]);
          } finally {
            activeExtractions--;
          }
        };
        await diaryRepository.save(_entry(id: 'first', body: 'first'));
        final run = worker();
        final firstRun = run.runOnce();
        await started.future;

        await diaryRepository.save(_entry(id: 'second', body: 'second'));
        final coalesced = run.runOnce();
        releaseFirst.complete();

        expect(await firstRun, SelfEngineRunResultV2.completed);
        expect(await coalesced, SelfEngineRunResultV2.completed);
        final jobs = await selfRepository.getJobs();
        expect(
          jobs.where((job) => job.status == SelfEngineJobStatusV2.completed),
          hasLength(2),
        );
        expect(extractor.calls, 2);
        expect(maxConcurrentExtractions, 1);
      },
    );

    test(
      'malformed result retries, poison job does not block later work, then fails',
      () async {
        selfRepository = SqliteSelfEngineRepositoryV2(
          await databaseOwner.open(),
          retryPolicy: const SelfEngineRetryPolicyV2(
            maxAttempts: 2,
            baseDelay: Duration(minutes: 1),
          ),
        );
        extractor.handler = (revision) async {
          if (revision.body == 'poison') {
            throw const MemoryExtractionFormatFailureV2('malformed JSON');
          }
          return _batch([
            _candidate(kind: 'event', statement: 'good', quote: revision.body),
          ]);
        };
        await diaryRepository.save(_entry(body: 'poison'));
        await diaryRepository.save(_entry(id: 'diary-2', body: 'good'));
        final run = worker();

        expect(await run.runOnce(), SelfEngineRunResultV2.retryScheduled);
        expect(await run.runOnce(), SelfEngineRunResultV2.completed);
        now = now.add(const Duration(minutes: 2));
        expect(await run.runOnce(), SelfEngineRunResultV2.terminalFailure);

        final jobs = await selfRepository.getJobs();
        expect(
          jobs.singleWhere((job) => job.diaryId == 'diary-1').status,
          SelfEngineJobStatusV2.failed,
        );
        expect(
          jobs.singleWhere((job) => job.diaryId == 'diary-2').status,
          SelfEngineJobStatusV2.completed,
        );
      },
    );

    test('expired old lease cannot publish cache or atoms', () async {
      await diaryRepository.save(_entry(body: 'lease'));
      final old = (await selfRepository.claimNextJob(
        now: now,
        leaseDuration: const Duration(seconds: 1),
      ))!;
      now = now.add(const Duration(seconds: 2));
      await selfRepository.recoverExpiredLeases(now: now);
      now = now.add(const Duration(minutes: 2));
      final current = (await selfRepository.claimNextJob(now: now))!;
      final oldProcessor = MemoryAtomJobProcessorV2(
        repository: selfRepository,
        extractor: extractor,
        clock: () => now,
      );

      await expectLater(
        oldProcessor.process(old),
        throwsA(isA<SelfEngineOwnershipLostV2>()),
      );
      expect(
        await selfRepository.getComputationResult(old.computationId),
        isNull,
      );
      expect(await selfRepository.getAtomsForRevision(old.revisionId), isEmpty);
      expect(current.leaseId, isNot(old.leaseId));
    });

    test(
      'generation rebuild invalidates an extraction already in flight',
      () async {
        final started = Completer<void>();
        final release = Completer<MemoryExtractionBatchV2>();
        extractor.handler = (_) {
          started.complete();
          return release.future;
        };
        await diaryRepository.save(_entry(body: 'generation'));
        final future = worker().runOnce();
        await started.future;

        await selfRepository.clearAllDerivedDataForGlobalRebuild();
        release.complete(
          _batch([
            _candidate(
              kind: 'event',
              statement: 'generation',
              quote: 'generation',
            ),
          ]),
        );

        expect(await future, SelfEngineRunResultV2.ownershipLost);
        final job = (await selfRepository.getJobs()).single;
        expect(job.status, SelfEngineJobStatusV2.pending);
        expect(job.generation, 2);
        expect(
          await selfRepository.getComputationResult(job.computationId),
          isNull,
        );
        expect(
          await selfRepository.getAtomsForRevision(job.revisionId),
          isEmpty,
        );
      },
    );

    test(
      'publish validation failure rolls cache, atoms, and completion back',
      () async {
        await diaryRepository.save(_entry(body: 'evidence'));
        final job = (await selfRepository.claimNextJob(now: now))!;
        final badDraft = MemoryAtomDraftV2(
          kind: MemoryAtomKindV2.event,
          statement: 'different cache payload',
          sourceQuote: 'evidence',
          sourceStart: 0,
          sourceEnd: 8,
          scope: MemoryAtomScopeV2.state,
        );
        final atom = _atomFor(job, statement: 'materialized payload');

        await expectLater(
          selfRepository.publishResult(
            job.id,
            leaseId: job.leaseId!,
            publishedAt: now,
            result: SelfEngineDerivedResultV2(
              atoms: [atom],
              computationResult: SourceComputationResultV2(
                computationId: job.computationId,
                atoms: [badDraft],
                extractorVersion: 1,
                promptVersion: 1,
                modelIdentifier: 'fake:model',
                createdAt: now,
              ),
            ),
          ),
          throwsStateError,
        );

        expect(
          await selfRepository.getComputationResult(job.computationId),
          isNull,
        );
        expect(
          await selfRepository.getAtomsForRevision(job.revisionId),
          isEmpty,
        );
        expect(
          (await selfRepository.getJobs()).single.status,
          SelfEngineJobStatusV2.processing,
        );
      },
    );

    test('repository rejects an atom bound to a different revision', () async {
      await diaryRepository.save(_entry(body: 'first evidence'));
      await diaryRepository.save(_entry(id: 'diary-2', body: 'other evidence'));
      final claimed = (await selfRepository.claimNextJob(now: now))!;
      final otherRevision = (await selfRepository.getRevisionsForDiary(
        'diary-2',
      )).single;
      final wrong = MemoryAtomV2(
        id: 'wrong-revision-atom',
        revisionId: otherRevision.id,
        kind: MemoryAtomKindV2.event,
        statement: 'wrong revision',
        sourceQuote: 'first evidence',
        sourceStart: 0,
        sourceEnd: 14,
        scope: MemoryAtomScopeV2.state,
        pipelineVersion: claimed.pipelineVersion,
        generation: claimed.generation,
        createdAt: now,
      );

      await expectLater(
        selfRepository.publishResult(
          claimed.id,
          leaseId: claimed.leaseId!,
          publishedAt: now,
          result: SelfEngineDerivedResultV2(atoms: [wrong]),
        ),
        throwsStateError,
      );
      expect(
        await selfRepository.getAtomsForRevision(claimed.revisionId),
        isEmpty,
      );
      expect(
        await selfRepository.getAtomsForRevision(otherRevision.id),
        isEmpty,
      );
    });

    test('save callback runs only after source transaction commits', () async {
      var callbacks = 0;
      final notifyingRepository = SqliteDiaryRepositoryV2(
        await databaseOwner.open(),
        onSourceSaved: () => callbacks++,
      );
      addTearDown(notifyingRepository.dispose);

      await notifyingRepository.save(_entry(id: 'callback'));

      expect(callbacks, 1);
      expect(
        await selfRepository.getRevisionsForDiary('callback'),
        hasLength(1),
      );
      expect(
        (await selfRepository.getJobs()).where(
          (job) => job.diaryId == 'callback',
        ),
        hasLength(1),
      );
    });
  });

  test('resume maintenance also offers one worker run', () async {
    final owner = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => inMemoryDatabasePath,
    );
    final repository = SqliteSelfEngineRepositoryV2(await owner.open());
    final runner = _CountingRunner();
    addTearDown(owner.close);
    await SelfEngineLifecycleMaintenanceV2(
      recovery: SelfEngineJobRecoveryV2(repository),
      runner: runner,
    ).afterResume();

    expect(runner.calls, 1);
  });

  group('schema v12', () {
    test('fresh database creates computation result table and FK', () async {
      final owner = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => inMemoryDatabasePath,
      );
      final database = await owner.open();
      addTearDown(owner.close);

      expect(
        await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name='self_engine_computation_results'",
        ),
        hasLength(1),
      );
      final jobColumns = await database.rawQuery(
        'PRAGMA table_info(self_engine_jobs)',
      );
      expect(jobColumns.map((row) => row['name']), contains('origin'));
      expect(
        () => database.insert('self_engine_computation_results', {
          'computation_id': 'missing',
          'result_json': '[]',
          'extractor_version': 1,
          'prompt_version': 1,
          'model_identifier': 'fake:model',
          'created_at': DateTime.utc(2026).toIso8601String(),
        }),
        throwsA(anything),
      );
    });

    test('v11 upgrades to v12 without losing source state', () async {
      final temp = await Directory.systemTemp.createTemp('diary-v12-test-');
      final dbPath = '${temp.path}${Platform.pathSeparator}upgrade.db';
      addTearDown(() async {
        await databaseFactoryFfi.deleteDatabase(dbPath);
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final firstOwner = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => dbPath,
      );
      final database = await firstOwner.open();
      final diary = SqliteDiaryRepositoryV2(database);
      await diary.save(_entry(body: 'preserved'));
      await diary.dispose();
      await firstOwner.close();

      final raw = await databaseFactoryFfi.openDatabase(dbPath);
      await raw.execute('DROP TABLE self_engine_computation_results');
      await raw.execute('DROP INDEX self_engine_jobs_origin_ready_index');
      await raw.execute('ALTER TABLE self_engine_jobs DROP COLUMN origin');
      await raw.execute('PRAGMA user_version = 11');
      await raw.close();

      final upgradedOwner = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => dbPath,
      );
      final upgraded = await upgradedOwner.open();
      addTearDown(upgradedOwner.close);
      expect(await upgraded.query('diary_entries'), hasLength(1));
      expect(await upgraded.query('diary_revisions'), hasLength(1));
      expect(await upgraded.query('self_engine_jobs'), hasLength(1));
      expect(
        (await upgraded.query('self_engine_jobs')).single['origin'],
        SelfEngineJobOriginV2.historical.name,
      );
      expect(await upgraded.query('self_engine_computation_results'), isEmpty);
    });
  });

  test('cache identity versions share one explicit semantic contract', () {
    expect(
      SelfEnginePipelineV2.pipelineVersion,
      SelfEnginePipelineV2.semanticVersion,
    );
    expect(
      AiMemoryExtractorV2.extractorVersion,
      SelfEnginePipelineV2.semanticVersion,
    );
    expect(
      AiMemoryExtractorV2.promptVersion,
      SelfEnginePipelineV2.semanticVersion,
    );
  });

  test(
    'configured availability requires explicit opt-in and an API key',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secrets = _SecretStore();
      final store = AiConfigurationStoreV2(secretStore: secrets);
      final availability = ConfiguredSelfEngineAvailabilityV2(store);
      expect(await availability.canProcess(), isFalse);

      await store.save(
        enabled: true,
        selfEngineEnabled: true,
        provider: AiProviderV2.gemini,
        model: 'test-model',
      );
      expect(await availability.canProcess(), isFalse);

      await store.save(
        enabled: true,
        selfEngineEnabled: true,
        provider: AiProviderV2.gemini,
        model: 'test-model',
        apiKey: 'secret',
      );
      expect(await availability.canProcess(), isTrue);
    },
  );

  test(
    'AI adapter rejects malformed JSON and sends only the requested diary',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secretStore = _SecretStore();
      final store = AiConfigurationStoreV2(secretStore: secretStore);
      await store.save(
        enabled: true,
        selfEngineEnabled: true,
        provider: AiProviderV2.gemini,
        model: 'test-model',
        modelStrategy: AiModelStrategyV2.custom,
        apiKey: 'secret',
      );
      late String requestBody;
      final client = GeminiRestClientV2(
        configurationStore: store,
        httpClient: MockClient((request) async {
          requestBody = request.body;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '{not-json'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      await expectLater(
        AiMemoryExtractorV2(client).extract(_revision('PRIVATE-DIARY-BODY')),
        throwsA(isA<MemoryExtractionFormatFailureV2>()),
      );
      expect(requestBody, contains('PRIVATE-DIARY-BODY'));
      expect(requestBody, contains('responseMimeType'));
      expect(requestBody, isNot(contains('secret')));
    },
  );
}

MemoryExtractionBatchV2 _batch(List<MemoryExtractionCandidateV2> candidates) =>
    MemoryExtractionBatchV2(
      candidates: candidates,
      extractorVersion: SelfEnginePipelineV2.extractorVersion,
      promptVersion: SelfEnginePipelineV2.promptVersion,
      modelIdentifier: 'fake:model',
    );

MemoryExtractionCandidateV2 _candidate({
  required String kind,
  required String statement,
  required String quote,
  int? start,
  int? end,
  String scope = 'state',
}) => MemoryExtractionCandidateV2(
  kind: kind,
  statement: statement,
  sourceQuote: quote,
  sourceStart: start,
  sourceEnd: end,
  scope: scope,
);

DiaryEntryV2 _entry({
  String id = 'diary-1',
  String body = 'A quiet morning',
  DateTime? updatedAt,
}) => DiaryEntryV2(
  id: id,
  body: body,
  entryDate: DateTime.utc(2026, 8, 1),
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: updatedAt ?? DateTime.utc(2026, 8, 1),
);

DiaryRevisionV2 _revision(String body) => DiaryRevisionV2(
  id: 'revision-1',
  diaryId: 'diary-1',
  revisionNo: 1,
  body: body,
  sourceHash: 'hash',
  entryDate: DateTime.utc(2026, 8, 1),
  createdAt: DateTime.utc(2026, 8, 1),
);

MemoryAtomV2 _atomFor(SelfEngineJobV2 job, {required String statement}) =>
    MemoryAtomV2(
      id: '${job.revisionId}-atom-1',
      revisionId: job.revisionId,
      kind: MemoryAtomKindV2.event,
      statement: statement,
      sourceQuote: 'evidence',
      sourceStart: 0,
      sourceEnd: 8,
      scope: MemoryAtomScopeV2.state,
      pipelineVersion: job.pipelineVersion,
      generation: job.generation,
      createdAt: DateTime.utc(2026, 8, 1, 9),
    );

class _FakeExtractor implements MemoryExtractorV2 {
  _FakeExtractor(this.handler);

  Future<MemoryExtractionBatchV2> Function(DiaryRevisionV2 revision) handler;
  int calls = 0;

  @override
  Future<MemoryExtractionBatchV2> extract(DiaryRevisionV2 revision) {
    calls++;
    return handler(revision);
  }
}

class _Availability implements SelfEngineAvailabilityV2 {
  const _Availability(this.available);

  final bool available;

  @override
  Future<bool> canProcess() async => available;
}

class _CountingRunner implements SelfEngineRunnerV2 {
  int calls = 0;
  final called = Completer<void>();

  @override
  Future<SelfEngineRunResultV2> runOnce() async {
    calls++;
    if (!called.isCompleted) called.complete();
    return SelfEngineRunResultV2.noWork;
  }
}

class _SecretStore implements AiSecretStoreV2 {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
