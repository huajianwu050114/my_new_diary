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
import 'package:my_new_diary/features/self_engine/application/personal_thesis_job_processor_v2.dart';
import 'package:my_new_diary/features/self_engine/application/ports/personal_thesis_synthesizer_v2.dart';
import 'package:my_new_diary/features/self_engine/application/ports/self_engine_availability_v2.dart';
import 'package:my_new_diary/features/self_engine/application/ports/self_engine_runner_v2.dart';
import 'package:my_new_diary/features/self_engine/application/self_engine_pipeline_runner_v2.dart';
import 'package:my_new_diary/features/self_engine/application/thesis_worker_v2.dart';
import 'package:my_new_diary/features/self_engine/data/ai/ai_personal_thesis_synthesizer_v2.dart';
import 'package:my_new_diary/features/self_engine/data/local/sqlite_personal_thesis_candidate_retriever_v2.dart';
import 'package:my_new_diary/features/self_engine/data/local/sqlite_self_engine_repository_v2.dart';
import 'package:my_new_diary/features/self_engine/data/local/thesis_work_v2.dart';
import 'package:my_new_diary/features/self_engine/data/local/thread_link_work_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/diary_source_fingerprint_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/memory_thread_link_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/personal_thesis_synthesis_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/personal_thesis_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/self_engine_job_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/self_engine_retry_policy_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Phase C1 Personal Thesis', () {
    late DiaryDatabaseV2 owner;
    late Database database;
    late SqliteSelfEngineRepositoryV2 repository;
    late SqliteDiaryRepositoryV2 diaryRepository;
    late DateTime now;

    setUp(() async {
      owner = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => inMemoryDatabasePath,
      );
      database = await owner.open();
      repository = SqliteSelfEngineRepositoryV2(database);
      diaryRepository = SqliteDiaryRepositoryV2(database);
      now = DateTime.utc(2026, 9, 20, 12);
    });

    tearDown(() async {
      await diaryRepository.dispose();
      await owner.close();
    });

    test('eligibility needs 3 Diaries, 2 dates, and a 7-day span', () async {
      final a1 = await _seedAtom(database, 'd1', DateTime.utc(2026, 1, 1));
      final a2 = await _seedAtom(database, 'd2', DateTime.utc(2026, 1, 1));
      await _seedThread(database, 't', [a1, a2]);
      expect(await _enqueue(database, 't', a2.revisionId, now), isFalse);

      final a3 = await _seedAtom(database, 'd3', DateTime.utc(2026, 1, 2));
      await _attach(database, 't', a3);
      expect(await _enqueue(database, 't', a3.revisionId, now), isFalse);

      final a4 = await _seedAtom(database, 'd4', DateTime.utc(2026, 1, 10));
      await _attach(database, 't', a4);
      expect(await _enqueue(database, 't', a4.revisionId, now), isTrue);
      expect(await _enqueue(database, 't', a4.revisionId, now), isFalse);
      expect(await database.query('thesis_jobs'), hasLength(1));
    });

    test(
      'same-Diary, historical, and deleted evidence do not qualify',
      () async {
        final same = await _seedAtom(
          database,
          'same-diary',
          DateTime.utc(2026, 1, 1),
          extraAtom: true,
        );
        await _seedThread(database, 'same-thread', [same]);
        await database.insert('thread_memberships', {
          'thread_id': 'same-thread',
          'atom_id': 'same-diary-a2',
          'relevance': 1.0,
          'origin': 'automatic',
          'generation': 1,
          'created_at': DateTime.utc(2026, 1, 10).toIso8601String(),
        });
        expect(
          await _enqueue(database, 'same-thread', same.revisionId, now),
          isFalse,
        );

        final h1 = await _seedAtom(
          database,
          'history-1',
          DateTime.utc(2026, 1, 1),
        );
        final h2 = await _seedAtom(
          database,
          'history-2',
          DateTime.utc(2026, 1, 10),
        );
        final h3 = await _seedAtom(
          database,
          'history-3',
          DateTime.utc(2026, 1, 20),
        );
        await _seedThread(database, 'history-thread', [h1, h2, h3]);
        await database.insert('diary_revisions', {
          'id': 'history-3-r2',
          'diary_id': 'history-3',
          'revision_no': 2,
          'body': 'new current source',
          'source_hash': 'hash-history-3-r2',
          'fingerprint_version': 1,
          'entry_date': DateTime.utc(2026, 1, 21).toIso8601String(),
          'tags': '[]',
          'created_at': DateTime.utc(2026, 1, 21).toIso8601String(),
        });
        expect(
          await _enqueue(database, 'history-thread', h3.revisionId, now),
          isFalse,
        );

        final d1 = await _seedAtom(
          database,
          'deleted-1',
          DateTime.utc(2026, 1, 1),
        );
        final d2 = await _seedAtom(
          database,
          'deleted-2',
          DateTime.utc(2026, 1, 10),
        );
        final d3 = await _seedAtom(
          database,
          'deleted-3',
          DateTime.utc(2026, 1, 20),
        );
        await _seedThread(database, 'deleted-thread', [d1, d2, d3]);
        await database.update(
          'diary_entries',
          {'deleted_at': now.toIso8601String()},
          where: 'id = ?',
          whereArgs: [d3.diaryId],
        );
        expect(
          await _enqueue(database, 'deleted-thread', d3.revisionId, now),
          isFalse,
        );
      },
    );

    test(
      'a qualifying Thread-link publish enqueues exactly one opportunity',
      () async {
        final first = await _seedAtom(
          database,
          'link-d1',
          DateTime.utc(2026, 1, 1),
        );
        final second = await _seedAtom(
          database,
          'link-d2',
          DateTime.utc(2026, 1, 10),
        );
        final third = await _seedAtom(
          database,
          'link-d3',
          DateTime.utc(2026, 1, 20),
        );
        await _seedThread(database, 'link-thread', [first, second]);
        await ThreadLinkWorkV2.enqueueRevision(
          database,
          revisionId: third.revisionId,
          origin: SelfEngineJobOriginV2.live,
          generation: 1,
          now: now,
        );
        final job = await repository.claimNextThreadLinkJob(now: now);
        expect(job, isNotNull);
        expect(
          await repository.publishThreadLinks(
            job!.id,
            leaseId: job.leaseId!,
            publishedAt: now,
            operations: [
              ThreadLinkOperationV2.attach(
                currentAtomId: third.atomId,
                threadId: 'link-thread',
              ),
            ],
          ),
          isTrue,
        );
        final jobs = await repository.getThesisJobs();
        expect(jobs, hasLength(1));
        expect(jobs.single.threadId, 'link-thread');
        expect(jobs.single.triggerRevisionId, third.revisionId);
        expect(jobs.single.origin, SelfEngineJobOriginV2.live);
        final outside = await _seedAtom(
          database,
          'link-outside',
          DateTime.utc(2026, 2, 1),
        );
        expect(
          () => database.insert('thesis_jobs', {
            'id': 'wrong-source',
            'thread_id': 'link-thread',
            'trigger_revision_id': outside.revisionId,
            'origin': 'live',
            'status': 'pending',
            'attempt_count': 0,
            'pipeline_version': 1,
            'generation': 1,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          }),
          throwsA(anything),
        );
      },
    );

    test(
      'historical Thesis work is durable but ignored by the live worker',
      () async {
        final fixture = await _eligibleFixture(
          database,
          now: now,
          enqueue: false,
        );
        expect(
          await ThesisWorkV2.enqueueIfEligible(
            database,
            threadId: fixture.threadId,
            triggerRevisionId: '${fixture.diaryIds.last}-r1',
            origin: SelfEngineJobOriginV2.historical,
            generation: 1,
            now: now,
          ),
          isTrue,
        );
        expect(await repository.claimNextThesisJob(now: now), isNull);
        expect(await repository.getThesisJobs(), hasLength(1));
      },
    );

    test('legal none completes once without inventing a Thesis', () async {
      final fixture = await _eligibleFixture(database, now: now);
      final synth = _FakeSynthesizer(
        (_) async => const PersonalThesisSynthesisDecisionV2.none(),
      );
      final worker = _worker(repository, database, synth, () => now);
      final outcome = await worker.runOnce();
      if (outcome != SelfEngineRunResultV2.completed) {
        fail((await repository.getThesisJobs()).single.error ?? '$outcome');
      }
      expect(await database.query('personal_theses'), isEmpty);
      expect(
        (await repository.getThesisJobs()).single.status,
        SelfEngineJobStatusV2.completed,
      );
      expect(synth.requests.single.thread.id, fixture.threadId);
    });

    test(
      'unavailable provider leaves work pending without burning attempts',
      () async {
        await _eligibleFixture(database, now: now);
        final synth = _FakeSynthesizer(
          (_) async => const PersonalThesisSynthesisDecisionV2.none(),
        );
        final worker = ThesisWorkerV2(
          repository: repository,
          processor: PersonalThesisJobProcessorV2(
            repository: repository,
            candidateRetriever: SqlitePersonalThesisCandidateRetrieverV2(
              database,
            ),
            synthesizer: synth,
            clock: () => now,
          ),
          availability: const _Availability(false),
          clock: () => now,
        );
        expect(await worker.runOnce(), SelfEngineRunResultV2.unavailable);
        final job = (await repository.getThesisJobs()).single;
        expect(job.status, SelfEngineJobStatusV2.pending);
        expect(job.attemptCount, 0);
        expect(synth.calls, 0);
      },
    );

    test(
      'first current Thesis atomically supersedes sibling opportunities',
      () async {
        final fixture = await _eligibleFixture(database, now: now);
        final later = await _seedAtom(
          database,
          'later-evidence',
          DateTime.utc(2026, 2, 1),
        );
        await _attach(database, fixture.threadId, later);
        expect(
          await _enqueue(
            database,
            fixture.threadId,
            later.revisionId,
            now.add(const Duration(seconds: 1)),
          ),
          isTrue,
        );
        expect(await repository.getThesisJobs(), hasLength(2));
        await _publishValid(repository, database, now);
        expect(
          (await repository.getThesisJobs()).every(
            (job) => job.status == SelfEngineJobStatusV2.completed,
          ),
          isTrue,
        );
        expect(
          await repository.claimNextThesisJob(
            now: now.add(const Duration(seconds: 2)),
          ),
          isNull,
        );
        expect(await database.query('personal_theses'), hasLength(1));
      },
    );

    test(
      'version 1 persists support, counter, and all prompt provenance',
      () async {
        final fixture = await _eligibleFixture(
          database,
          now: now,
          withCounter: true,
        );
        final synth = _FakeSynthesizer((request) async {
          expect(request.supportCandidates.length, lessThanOrEqualTo(12));
          expect(request.counterCandidates.length, lessThanOrEqualTo(16));
          return PersonalThesisSynthesisDecisionV2.create(
            statement: '我可能在规律运动后更容易恢复平静',
            rationale: '多次记录支持这个暂定解释，同时保留不同情境作为反证检查。',
            maturity: PersonalThesisMaturityV2.candidate,
            supportAtomIds: request.supportCandidates
                .take(2)
                .map((item) => item.atom.id)
                .toList(),
            counterAtomIds: [request.counterCandidates.first.atom.id],
          );
        });
        expect(
          await _worker(repository, database, synth, () => now).runOnce(),
          SelfEngineRunResultV2.completed,
        );

        final thesis = (await repository.getPersonalTheses()).single;
        expect(thesis.status, PersonalThesisStatusV2.active);
        expect(thesis.threadId, fixture.threadId);
        final version = (await repository.getPersonalThesisVersions(
          thesis.id,
        )).single;
        expect(version.versionNo, 1);
        expect(version.maturity, PersonalThesisMaturityV2.candidate);
        expect(version.trend, PersonalThesisTrendV2.stable);
        final evidence = await database.query('personal_thesis_evidence');
        expect(evidence.where((row) => row['role'] == 'support'), hasLength(2));
        expect(evidence.where((row) => row['role'] == 'counter'), hasLength(1));
        final request = synth.requests.single;
        final counterId = request.counterCandidates.first.atom.id;
        await database.delete(
          'personal_thesis_evidence',
          where: 'atom_id = ?',
          whereArgs: [counterId],
        );
        expect(
          () => database.insert('personal_thesis_evidence', {
            'thesis_version_id': version.id,
            'atom_id': counterId,
            'role': 'support',
            'generation': 1,
            'created_at': now.toIso8601String(),
          }),
          throwsA(anything),
        );
        final allSent = {
          ...request.supportCandidates.map((item) => item.atom.id),
          ...request.counterCandidates.map((item) => item.atom.id),
          ...request.threadDerivationAtomIds,
        };
        final derivation = (await database.query(
          'thesis_derivation_atoms',
        )).map((row) => row['atom_id']! as String).toSet();
        expect(derivation, containsAll(allSent));
      },
    );

    test('unknown and cross-role evidence IDs retry atomically', () async {
      await _eligibleFixture(database, now: now, withCounter: true);
      final synth = _FakeSynthesizer((request) async {
        return PersonalThesisSynthesisDecisionV2.create(
          statement: '我可能在运动后更容易平静',
          rationale: '这是可修正的暂定解释。',
          maturity: PersonalThesisMaturityV2.candidate,
          supportAtomIds: [request.supportCandidates.first.atom.id, 'invented'],
          counterAtomIds: const [],
        );
      });
      expect(
        await _worker(repository, database, synth, () => now).runOnce(),
        SelfEngineRunResultV2.retryScheduled,
      );
      expect(await database.query('personal_theses'), isEmpty);
      expect(await database.query('personal_thesis_versions'), isEmpty);
      expect(await database.query('personal_thesis_evidence'), isEmpty);
    });

    test(
      'provider failure is retryable and publishes no partial state',
      () async {
        await _eligibleFixture(database, now: now);
        final synth = _FakeSynthesizer(
          (_) async => throw StateError('offline'),
        );
        expect(
          await _worker(repository, database, synth, () => now).runOnce(),
          SelfEngineRunResultV2.retryScheduled,
        );
        final job = (await repository.getThesisJobs()).single;
        expect(job.status, SelfEngineJobStatusV2.retryable);
        expect(job.nextRetryAt, isNotNull);
        expect(await database.query('personal_theses'), isEmpty);
      },
    );

    test('support must span at least two distinct Diaries', () async {
      await _eligibleFixture(database, now: now);
      final synth = _FakeSynthesizer((request) async {
        final firstDiary = request.supportCandidates.first.diaryId;
        final sameDiary = request.supportCandidates
            .where((item) => item.diaryId == firstDiary)
            .map((item) => item.atom.id)
            .toList();
        return PersonalThesisSynthesisDecisionV2.create(
          statement: '我可能在运动后更容易平静',
          rationale: '这是可修正的暂定解释。',
          maturity: PersonalThesisMaturityV2.candidate,
          supportAtomIds: sameDiary.length >= 2
              ? sameDiary.take(2).toList()
              : [sameDiary.single, sameDiary.single],
          counterAtomIds: const [],
        );
      });
      expect(
        await _worker(repository, database, synth, () => now).runOnce(),
        SelfEngineRunResultV2.retryScheduled,
      );
      expect(await database.query('personal_theses'), isEmpty);
    });

    test(
      'wording guard rejects essence, diagnosis, and second person',
      () async {
        await _eligibleFixture(database, now: now);
        final synth = _FakeSynthesizer((request) async {
          return PersonalThesisSynthesisDecisionV2.create(
            statement: '你本质上永远是一个焦虑症患者',
            rationale: '这些记录证明了人格障碍。',
            maturity: PersonalThesisMaturityV2.candidate,
            supportAtomIds: request.supportCandidates
                .take(2)
                .map((item) => item.atom.id)
                .toList(),
            counterAtomIds: const [],
          );
        });
        expect(
          await _worker(repository, database, synth, () => now).runOnce(),
          SelfEngineRunResultV2.retryScheduled,
        );
        expect(await database.query('personal_theses'), isEmpty);
      },
    );

    test(
      'claim is atomic and an expired lease rejects its stale owner',
      () async {
        await _eligibleFixture(database, now: now);
        final claims = await Future.wait([
          repository.claimNextThesisJob(
            now: now,
            leaseDuration: const Duration(minutes: 1),
          ),
          repository.claimNextThesisJob(
            now: now,
            leaseDuration: const Duration(minutes: 1),
          ),
        ]);
        expect(claims.whereType<Object>(), hasLength(1));
        final stale = claims.where((job) => job != null).single!;
        final expiredAt = now.add(const Duration(minutes: 2));
        expect(await repository.recoverExpiredThesisLeases(now: expiredAt), 1);
        final fresh = await repository.claimNextThesisJob(
          now: expiredAt.add(const Duration(minutes: 2)),
        );
        expect(fresh, isNotNull);
        expect(fresh!.leaseId, isNot(stale.leaseId));
        expect(
          await repository.publishThesis(
            stale.id,
            leaseId: stale.leaseId!,
            publishedAt: expiredAt.add(const Duration(minutes: 2)),
            result: const PersonalThesisPublishV2.none(),
          ),
          isFalse,
        );
        expect(
          await repository.publishThesis(
            fresh.id,
            leaseId: fresh.leaseId!,
            publishedAt: expiredAt.add(const Duration(minutes: 2)),
            result: const PersonalThesisPublishV2.none(),
          ),
          isTrue,
        );
      },
    );

    test(
      'retry has a maximum and a poison job does not block later work',
      () async {
        repository = SqliteSelfEngineRepositoryV2(
          database,
          retryPolicy: const SelfEngineRetryPolicyV2(
            maxAttempts: 2,
            baseDelay: Duration(milliseconds: 1),
          ),
        );
        await _eligibleFixture(database, now: now, threadId: 'poison');
        final poison = await repository.claimNextThesisJob(now: now);
        expect(poison!.threadId, 'poison');
        await repository.markThesisJobFailed(
          poison.id,
          leaseId: poison.leaseId!,
          failedAt: now,
          error: 'bad',
        );
        final poisonRetry = await repository.claimNextThesisJob(
          now: now.add(const Duration(milliseconds: 2)),
        );
        expect(poisonRetry!.id, poison.id);
        await repository.markThesisJobFailed(
          poisonRetry.id,
          leaseId: poisonRetry.leaseId!,
          failedAt: now.add(const Duration(milliseconds: 2)),
          error: 'still bad',
        );
        expect(
          (await repository.getThesisJobs()).first.status,
          SelfEngineJobStatusV2.failed,
        );
        await _eligibleFixture(
          database,
          now: now.add(const Duration(seconds: 1)),
          threadId: 'healthy',
          idPrefix: 'h',
        );
        final next = await repository.claimNextThesisJob(
          now: now.add(const Duration(milliseconds: 3)),
        );
        expect(next!.threadId, 'healthy');
      },
    );

    test('generation change prevents stale Thesis publication', () async {
      await _eligibleFixture(database, now: now);
      final claimed = await repository.claimNextThesisJob(now: now);
      await repository.clearAllDerivedDataForGlobalRebuild();
      expect(
        await repository.publishThesis(
          claimed!.id,
          leaseId: claimed.leaseId!,
          publishedAt: now.add(const Duration(seconds: 1)),
          result: const PersonalThesisPublishV2.none(),
        ),
        isFalse,
      );
      expect(await database.query('personal_theses'), isEmpty);
    });

    test(
      'publish rollback leaves no partial Thesis and retry is idempotent',
      () async {
        await _eligibleFixture(database, now: now, withCounter: true);
        final job = await repository.claimNextThesisJob(now: now);
        final request = await SqlitePersonalThesisCandidateRetrieverV2(
          database,
        ).retrieve(job!.threadId);
        final support = request!.supportCandidates
            .take(2)
            .map((item) => item.atom.id)
            .toList();
        final result = PersonalThesisPublishV2.create(
          decision: PersonalThesisSynthesisDecisionV2.create(
            statement: '我可能在规律运动后更容易恢复平静',
            rationale: '多次记录支持这个可修正的暂定解释。',
            maturity: PersonalThesisMaturityV2.candidate,
            supportAtomIds: support,
            counterAtomIds: const [],
          ),
          derivationAtomIds: <String>{
            ...request.threadDerivationAtomIds,
            ...request.supportCandidates.map((item) => item.atom.id),
            ...request.counterCandidates.map((item) => item.atom.id),
          }.toList(),
        );
        await database.execute('''
        CREATE TRIGGER fail_thesis_derivation
        BEFORE INSERT ON thesis_derivation_atoms
        BEGIN
          SELECT RAISE(ABORT, 'injected publish failure');
        END
      ''');
        await expectLater(
          repository.publishThesis(
            job.id,
            leaseId: job.leaseId!,
            publishedAt: now,
            result: result,
          ),
          throwsA(anything),
        );
        expect(await database.query('personal_theses'), isEmpty);
        expect(await database.query('personal_thesis_versions'), isEmpty);
        expect(await database.query('personal_thesis_evidence'), isEmpty);
        expect(
          (await repository.getThesisJobs()).single.status,
          SelfEngineJobStatusV2.processing,
        );
        await database.execute('DROP TRIGGER fail_thesis_derivation');
        expect(
          await repository.publishThesis(
            job.id,
            leaseId: job.leaseId!,
            publishedAt: now,
            result: result,
          ),
          isTrue,
        );
        expect(await database.query('personal_theses'), hasLength(1));
        expect(await database.query('personal_thesis_versions'), hasLength(1));
      },
    );

    test('worker is single-flight during a slow synthesizer call', () async {
      await _eligibleFixture(database, now: now);
      final entered = Completer<void>();
      final release = Completer<void>();
      final synth = _FakeSynthesizer((_) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        return const PersonalThesisSynthesisDecisionV2.none();
      });
      final worker = _worker(repository, database, synth, () => now);
      final first = worker.runOnce();
      await entered.future;
      final second = worker.runOnce();
      expect(identical(first, second), isTrue);
      release.complete();
      expect(await first, SelfEngineRunResultV2.completed);
      expect(synth.calls, 1);
    });

    test(
      'Thread invalidation keeps history but permanent delete removes it',
      () async {
        final fixture = await _eligibleFixture(database, now: now);
        await _publishValid(repository, database, now);
        await ThreadLinkWorkV2.invalidateThreadsUsingDiary(
          database,
          diaryId: fixture.diaryIds.first,
          generation: 1,
          now: now,
        );
        final invalidated = (await repository.getPersonalTheses()).single;
        expect(invalidated.status, PersonalThesisStatusV2.invalidated);
        expect(invalidated.threadId, isNull);
        expect(
          await repository.getPersonalThesisVersions(invalidated.id),
          hasLength(1),
        );

        final second = await _eligibleFixture(
          database,
          now: now.add(const Duration(days: 1)),
          threadId: 'privacy',
          idPrefix: 'p',
        );
        await _publishValid(
          repository,
          database,
          now.add(const Duration(days: 1)),
        );
        await diaryRepository.deletePermanently(second.diaryIds.first);
        expect(
          await database.query(
            'personal_theses',
            where: 'source_thread_id = ?',
            whereArgs: ['privacy'],
          ),
          isEmpty,
        );
        expect(
          await database.query(
            'personal_thesis_versions',
            where: "id LIKE ?",
            whereArgs: ['%privacy%'],
          ),
          isEmpty,
        );
      },
    );

    test(
      'editing an external selected counter invalidates only the current Thesis',
      () async {
        final fixture = await _publishWithExternalProvenance(
          repository,
          database,
          now,
          selectCounter: true,
        );
        final beforeEvidence = await database.query('personal_thesis_evidence');
        final beforeDerivation = await database.query(
          'thesis_derivation_atoms',
        );
        expect(
          beforeEvidence,
          contains(
            predicate<Map<String, Object?>>(
              (row) =>
                  row['atom_id'] == fixture.externalAtomId &&
                  row['role'] == 'counter',
            ),
          ),
        );

        final original = await diaryRepository.getById(fixture.externalDiaryId);
        await diaryRepository.save(
          original!.copyWith(
            body: '修改后的外部反证记录',
            updatedAt: now.add(const Duration(minutes: 1)),
          ),
        );

        await _expectCurrentThesisInvalidated(
          database,
          fixture,
          evidenceCount: beforeEvidence.length,
          derivationCount: beforeDerivation.length,
        );
      },
    );

    test(
      'editing external prompt-only provenance invalidates the current Thesis',
      () async {
        final fixture = await _publishWithExternalProvenance(
          repository,
          database,
          now,
        );
        expect(
          await database.query(
            'personal_thesis_evidence',
            where: 'atom_id = ?',
            whereArgs: [fixture.externalAtomId],
          ),
          isEmpty,
        );
        expect(
          await database.query(
            'thesis_derivation_atoms',
            where: 'atom_id = ?',
            whereArgs: [fixture.externalAtomId],
          ),
          hasLength(1),
        );
        final evidenceCount = (await database.query(
          'personal_thesis_evidence',
        )).length;
        final derivationCount = (await database.query(
          'thesis_derivation_atoms',
        )).length;

        final original = await diaryRepository.getById(fixture.externalDiaryId);
        await diaryRepository.save(
          original!.copyWith(
            body: '修改后的 prompt-only 记录',
            updatedAt: now.add(const Duration(minutes: 1)),
          ),
        );

        await _expectCurrentThesisInvalidated(
          database,
          fixture,
          evidenceCount: evidenceCount,
          derivationCount: derivationCount,
        );
      },
    );

    test(
      'soft-deleting external provenance invalidates the current Thesis',
      () async {
        final fixture = await _publishWithExternalProvenance(
          repository,
          database,
          now,
        );
        final evidenceCount = (await database.query(
          'personal_thesis_evidence',
        )).length;
        final derivationCount = (await database.query(
          'thesis_derivation_atoms',
        )).length;

        await diaryRepository.moveToTrash(
          fixture.externalDiaryId,
          deletedAt: now.add(const Duration(minutes: 1)),
        );

        await _expectCurrentThesisInvalidated(
          database,
          fixture,
          evidenceCount: evidenceCount,
          derivationCount: derivationCount,
        );
        expect(
          (await diaryRepository.getById(fixture.externalDiaryId))!.isDeleted,
          isTrue,
        );
      },
    );

    test('same-content save does not invalidate the current Thesis', () async {
      final fixture = await _publishWithExternalProvenance(
        repository,
        database,
        now,
      );
      final original = await diaryRepository.getById(fixture.externalDiaryId);

      await diaryRepository.save(
        original!.copyWith(
          updatedAt: now.add(const Duration(minutes: 1)),
          isFavorite: true,
        ),
      );

      final thesis = (await database.query(
        'personal_theses',
        where: 'id = ?',
        whereArgs: [fixture.thesisId],
      )).single;
      expect(thesis['status'], 'active');
      expect(thesis['current_version_id'], fixture.versionId);
      expect(thesis['thread_id'], fixture.threadId);
      expect(
        await database.query(
          'diary_revisions',
          where: 'diary_id = ?',
          whereArgs: [fixture.externalDiaryId],
        ),
        hasLength(1),
      );
    });

    test(
      'Thesis invalidation failure rolls back the Diary source change',
      () async {
        final fixture = await _publishWithExternalProvenance(
          repository,
          database,
          now,
        );
        final original = await diaryRepository.getById(fixture.externalDiaryId);
        await database.execute('''
          CREATE TRIGGER fail_current_thesis_invalidation
          BEFORE UPDATE OF status ON personal_theses
          WHEN OLD.id = '${fixture.thesisId}'
          BEGIN
            SELECT RAISE(ABORT, 'injected Thesis invalidation failure');
          END
        ''');

        await expectLater(
          diaryRepository.save(
            original!.copyWith(
              body: '这次修改必须完整回滚',
              updatedAt: now.add(const Duration(minutes: 1)),
            ),
          ),
          throwsA(anything),
        );

        expect(
          (await diaryRepository.getById(fixture.externalDiaryId))!.body,
          original.body,
        );
        expect(
          await database.query(
            'diary_revisions',
            where: 'diary_id = ?',
            whereArgs: [fixture.externalDiaryId],
          ),
          hasLength(1),
        );
        final thesis = (await database.query(
          'personal_theses',
          where: 'id = ?',
          whereArgs: [fixture.thesisId],
        )).single;
        expect(thesis['status'], 'active');
        expect(thesis['current_version_id'], fixture.versionId);
        expect(thesis['thread_id'], fixture.threadId);
      },
    );

    test(
      'permanent delete still removes a Thesis using external prompt provenance',
      () async {
        final fixture = await _publishWithExternalProvenance(
          repository,
          database,
          now,
        );
        final version = (await database.query(
          'personal_thesis_versions',
          where: 'id = ?',
          whereArgs: [fixture.versionId],
        )).single;
        expect(version['statement'], isNotEmpty);
        expect(version['rationale'], isNotEmpty);

        await diaryRepository.deletePermanently(fixture.externalDiaryId);

        expect(await database.query('personal_theses'), isEmpty);
        expect(await database.query('personal_thesis_versions'), isEmpty);
        expect(await database.query('personal_thesis_evidence'), isEmpty);
        expect(await database.query('thesis_derivation_atoms'), isEmpty);
        expect(
          (await database.query(
            'memory_threads',
            where: 'id = ?',
            whereArgs: [fixture.threadId],
          )).single['status'],
          'active',
        );
      },
    );

    test(
      'normal edit ignores historical provenance outside current Thesis version',
      () async {
        final historical = await _seedAtom(
          database,
          'historical-provenance',
          DateTime.utc(2025, 12, 1),
        );
        final current = await _seedAtom(
          database,
          'current-provenance',
          DateTime.utc(2026, 1, 1),
        );
        await _seedThread(database, 'future-version-thread', [current]);
        final stamp = now.toIso8601String();
        await database.insert('personal_theses', {
          'id': 'future-version-thesis',
          'source_thread_id': 'future-version-thread',
          'status': 'invalidated',
          'generation': 1,
          'created_at': stamp,
          'updated_at': stamp,
        });
        for (final versionNo in [1, 2]) {
          await database.insert('personal_thesis_versions', {
            'id': 'future-version-v$versionNo',
            'thesis_id': 'future-version-thesis',
            'version_no': versionNo,
            'statement': '受控测试版本 $versionNo',
            'rationale': '仅用于验证 current-version provenance 查询。',
            'maturity': 'candidate',
            'trend': 'stable',
            'generation': 1,
            'created_at': stamp,
          });
        }
        await database.insert('thesis_derivation_atoms', {
          'thesis_version_id': 'future-version-v1',
          'atom_id': historical.atomId,
          'generation': 1,
          'created_at': stamp,
        });
        await database.insert('thesis_derivation_atoms', {
          'thesis_version_id': 'future-version-v2',
          'atom_id': current.atomId,
          'generation': 1,
          'created_at': stamp,
        });
        await database.update(
          'personal_theses',
          {
            'thread_id': 'future-version-thread',
            'status': 'active',
            'current_version_id': 'future-version-v2',
          },
          where: 'id = ?',
          whereArgs: ['future-version-thesis'],
        );

        final original = await diaryRepository.getById(historical.diaryId);
        await diaryRepository.save(
          original!.copyWith(
            body: '历史版本依赖的 Diary 已修改',
            updatedAt: now.add(const Duration(minutes: 1)),
          ),
        );

        final thesis = (await database.query(
          'personal_theses',
          where: 'id = ?',
          whereArgs: ['future-version-thesis'],
        )).single;
        expect(thesis['status'], 'active');
        expect(thesis['current_version_id'], 'future-version-v2');
        expect(thesis['thread_id'], 'future-version-thread');
      },
    );

    test('prompt-only provenance causes permanent privacy deletion', () async {
      final fixture = await _eligibleFixture(database, now: now);
      await _publishValid(repository, database, now);
      final thesis = (await repository.getPersonalTheses()).single;
      final version = (await repository.getPersonalThesisVersions(
        thesis.id,
      )).single;
      final support = (await database.query(
        'personal_thesis_evidence',
        where: "thesis_version_id = ? AND role = 'support'",
        whereArgs: [version.id],
      )).map((row) => row['atom_id']! as String).toSet();
      final promptOnlyDiary = fixture.diaryIds.firstWhere(
        (id) => !support.any((atomId) => atomId.startsWith('$id-')),
      );
      await diaryRepository.deletePermanently(promptOnlyDiary);
      expect(await database.query('personal_theses'), isEmpty);
      expect(await database.query('personal_thesis_versions'), isEmpty);
      expect(await database.query('personal_thesis_evidence'), isEmpty);
      expect(await database.query('thesis_derivation_atoms'), isEmpty);
    });

    test(
      'bounded retriever caps support and counter prompt evidence',
      () async {
        final support = <_SeededAtom>[];
        for (var i = 0; i < 20; i++) {
          support.add(
            await _seedAtom(
              database,
              's$i',
              DateTime.utc(2025, 1, 1).add(Duration(days: i * 8)),
            ),
          );
        }
        await _seedThread(database, 'bounded', support);
        for (var i = 0; i < 120; i++) {
          await _seedAtom(
            database,
            'c$i',
            DateTime.utc(2024, 1, 1).add(Duration(days: i)),
          );
        }
        final request = await SqlitePersonalThesisCandidateRetrieverV2(
          database,
        ).retrieve('bounded');
        expect(request!.supportCandidates, hasLength(12));
        expect(request.counterCandidates, hasLength(16));
        expect(
          request.supportCandidates.map((item) => item.diaryId),
          containsAll(['s0', 's19']),
        );
        expect(
          request.counterCandidates.map((item) => item.diaryId),
          containsAll(['c0', 'c119']),
        );
        expect(request.threadDerivationAtomIds, hasLength(20));
      },
    );

    test(
      'counter retrieval excludes deleted, superseded, and stale evidence',
      () async {
        final fixture = await _eligibleFixture(
          database,
          now: now,
          enqueue: false,
        );
        final deleted = await _seedAtom(
          database,
          'counter-deleted',
          DateTime.utc(2025, 1, 1),
        );
        final superseded = await _seedAtom(
          database,
          'counter-superseded',
          DateTime.utc(2025, 2, 1),
        );
        await database.update(
          'diary_entries',
          {'deleted_at': now.toIso8601String()},
          where: 'id = ?',
          whereArgs: [deleted.diaryId],
        );
        await database.update(
          'memory_atoms',
          {'superseded_at': now.toIso8601String()},
          where: 'id = ?',
          whereArgs: [superseded.atomId],
        );
        await database.execute(
          'DROP TRIGGER memory_atoms_generation_insert_guard',
        );
        final stale = await _seedAtom(
          database,
          'counter-stale',
          DateTime.utc(2025, 3, 1),
          generation: 2,
        );
        await database.execute('''
        CREATE TRIGGER memory_atoms_generation_insert_guard
        BEFORE INSERT ON memory_atoms
        WHEN NEW.generation != (
          SELECT generation FROM self_engine_state WHERE id = 1
        )
        BEGIN
          SELECT RAISE(ABORT, 'stale Self Engine generation');
        END
      ''');
        final request = await SqlitePersonalThesisCandidateRetrieverV2(
          database,
        ).retrieve(fixture.threadId);
        final ids = request!.counterCandidates.map((item) => item.atom.id);
        expect(ids, isNot(contains(deleted.atomId)));
        expect(ids, isNot(contains(superseded.atomId)));
        expect(ids, isNot(contains(stale.atomId)));
      },
    );

    test(
      'strict adapter rejects unknown actions, keys, enums, and duplicates',
      () async {
        SharedPreferences.setMockInitialValues({});
        final adapter = AiPersonalThesisSynthesizerV2(
          GeminiRestClientV2(configurationStore: AiConfigurationStoreV2()),
        );
        for (final json in [
          '{"action":"maybe"}',
          '{"action":"none","extra":1}',
          '{"action":"create","statement":"I may change","rationale":"tentative","maturity":"candidate","supportAtomIds":["a","b"],"counterAtomIds":["a"]}',
          '{"action":"create","statement":"我可能改变","rationale":"暂定","maturity":"established","supportAtomIds":["a","b"],"counterAtomIds":[]}',
          '{"action":"create","statement":"我可能改变","rationale":"暂定","maturity":"candidate","supportAtomIds":["a","a"],"counterAtomIds":[]}',
        ]) {
          expect(
            () => adapter.parse(json),
            throwsA(isA<PersonalThesisFormatFailureV2>()),
          );
        }
      },
    );

    test(
      'provider payload contains bounded evidence but no Diary body or key',
      () async {
        SharedPreferences.setMockInitialValues({});
        final secretStore = _SecretStore();
        final configuration = AiConfigurationStoreV2(secretStore: secretStore);
        await configuration.save(
          enabled: true,
          selfEngineEnabled: true,
          provider: AiProviderV2.gemini,
          model: 'test-model',
          modelStrategy: AiModelStrategyV2.custom,
          apiKey: 'TOP-SECRET-KEY',
        );
        final fixture = await _eligibleFixture(
          database,
          now: now,
          enqueue: false,
        );
        await database.update(
          'diary_entries',
          {'body': 'PRIVATE FULL DIARY BODY THAT MUST NOT LEAVE'},
          where: 'id = ?',
          whereArgs: [fixture.diaryIds.first],
        );
        final synthesisRequest = await SqlitePersonalThesisCandidateRetrieverV2(
          database,
        ).retrieve(fixture.threadId);
        late String requestBody;
        final client = GeminiRestClientV2(
          configurationStore: configuration,
          httpClient: MockClient((http.Request request) async {
            requestBody = request.body;
            return http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': '{"action":"none"}'},
                      ],
                    },
                  },
                ],
              }),
              200,
            );
          }),
        );
        expect(
          (await AiPersonalThesisSynthesizerV2(
            client,
          ).synthesize(synthesisRequest!)).action,
          PersonalThesisSynthesisActionV2.none,
        );
        expect(requestBody, contains('supportCandidates'));
        expect(requestBody, isNot(contains('PRIVATE FULL DIARY BODY')));
        expect(requestBody, isNot(contains('TOP-SECRET-KEY')));
        expect(requestBody, isNot(contains('thesis_jobs')));
      },
    );

    test('pipeline runs exactly one bounded Thesis opportunity', () async {
      final extraction = _CountingRunner();
      final linking = _CountingRunner();
      final thesis = _CountingRunner();
      final pipeline = SelfEnginePipelineRunnerV2(
        extractionRunner: extraction,
        threadLinkRunner: linking,
        thesisRunner: thesis,
      );
      await pipeline.runOnce();
      expect(extraction.calls, 1);
      expect(linking.calls, 1);
      expect(thesis.calls, 1);
    });
  });

  test('fresh v14 has Thesis tables and strict foreign keys', () async {
    final owner = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => inMemoryDatabasePath,
    );
    final database = await owner.open();
    expect(await database.query('personal_theses'), isEmpty);
    expect(await database.query('thesis_jobs'), isEmpty);
    expect(
      () => database.insert('thesis_jobs', {
        'id': 'bad',
        'thread_id': 'missing',
        'trigger_revision_id': 'missing',
        'origin': 'live',
        'status': 'pending',
        'attempt_count': 0,
        'pipeline_version': 1,
        'generation': 1,
        'created_at': DateTime.utc(2026).toIso8601String(),
        'updated_at': DateTime.utc(2026).toIso8601String(),
      }),
      throwsA(anything),
    );
    await owner.close();
  });

  test('v13 upgrades to v14 without changing source data', () async {
    final temp = await Directory.systemTemp.createTemp('diary-v14-test-');
    final path = '${temp.path}${Platform.pathSeparator}upgrade.db';
    addTearDown(() async {
      await databaseFactoryFfi.deleteDatabase(path);
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final first = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => path,
    );
    final database = await first.open();
    await _seedAtom(database, 'preserved', DateTime.utc(2026, 1, 1));
    await first.close();

    final raw = await databaseFactoryFfi.openDatabase(path);
    await _dropV14(raw);
    await raw.execute('PRAGMA user_version = 13');
    await raw.close();

    final upgraded = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => path,
    );
    final opened = await upgraded.open();
    addTearDown(upgraded.close);
    expect(await opened.query('diary_entries'), hasLength(1));
    expect(await opened.query('diary_revisions'), hasLength(1));
    expect(await opened.query('memory_atoms'), hasLength(1));
    expect(await opened.query('personal_theses'), isEmpty);
    expect(await opened.query('thesis_jobs'), isEmpty);
  });

  test('v14 onOpen rejects Thesis schema drift', () async {
    final temp = await Directory.systemTemp.createTemp('diary-v14-drift-');
    final path = '${temp.path}${Platform.pathSeparator}drift.db';
    addTearDown(() async {
      await databaseFactoryFfi.deleteDatabase(path);
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final first = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => path,
    );
    final database = await first.open();
    await database.execute('DROP INDEX thesis_jobs_origin_ready_index');
    await first.close();
    final drifted = DiaryDatabaseV2(
      factory: databaseFactoryFfi,
      databasePath: () async => path,
    );
    await expectLater(drifted.open(), throwsA(isA<StateError>()));
  });
}

Future<void> _dropV14(Database database) async {
  await database.execute(
    'DROP TRIGGER memory_threads_invalidate_theses_before_delete',
  );
  await database.execute('DROP TABLE thesis_jobs');
  await database.execute('DROP TABLE thesis_derivation_atoms');
  await database.execute('DROP TABLE personal_thesis_evidence');
  await database.execute('DROP TABLE personal_thesis_versions');
  await database.execute('DROP TABLE personal_theses');
}

Future<_ExternalProvenanceFixture> _publishWithExternalProvenance(
  SqliteSelfEngineRepositoryV2 repository,
  Database database,
  DateTime now, {
  bool selectCounter = false,
}) async {
  final fixture = await _eligibleFixture(database, now: now, withCounter: true);
  String? externalDiaryId;
  String? externalAtomId;
  final synth = _FakeSynthesizer((request) async {
    final external = request.counterCandidates.firstWhere(
      (candidate) => !fixture.diaryIds.contains(candidate.diaryId),
    );
    externalDiaryId = external.diaryId;
    externalAtomId = external.atom.id;
    return PersonalThesisSynthesisDecisionV2.create(
      statement: '我可能在规律运动后更容易恢复平静',
      rationale: '多次记录支持这个可修正的暂定解释。',
      maturity: PersonalThesisMaturityV2.candidate,
      supportAtomIds: request.supportCandidates
          .take(2)
          .map((item) => item.atom.id)
          .toList(),
      counterAtomIds: selectCounter ? [external.atom.id] : const [],
    );
  });
  expect(
    await _worker(repository, database, synth, () => now).runOnce(),
    SelfEngineRunResultV2.completed,
  );
  final thesis = (await repository.getPersonalTheses()).single;
  final version = (await repository.getPersonalThesisVersions(
    thesis.id,
  )).single;
  return _ExternalProvenanceFixture(
    threadId: fixture.threadId,
    thesisId: thesis.id,
    versionId: version.id,
    externalDiaryId: externalDiaryId!,
    externalAtomId: externalAtomId!,
  );
}

Future<void> _expectCurrentThesisInvalidated(
  Database database,
  _ExternalProvenanceFixture fixture, {
  required int evidenceCount,
  required int derivationCount,
}) async {
  final thread = (await database.query(
    'memory_threads',
    where: 'id = ?',
    whereArgs: [fixture.threadId],
  )).single;
  expect(thread['status'], 'active');
  final thesis = (await database.query(
    'personal_theses',
    where: 'id = ?',
    whereArgs: [fixture.thesisId],
  )).single;
  expect(thesis['status'], 'invalidated');
  expect(thesis['current_version_id'], isNull);
  expect(thesis['thread_id'], isNull);
  expect(
    await database.query(
      'personal_thesis_versions',
      where: 'id = ?',
      whereArgs: [fixture.versionId],
    ),
    hasLength(1),
  );
  expect(
    await database.query('personal_thesis_evidence'),
    hasLength(evidenceCount),
  );
  expect(
    await database.query('thesis_derivation_atoms'),
    hasLength(derivationCount),
  );
}

ThesisWorkerV2 _worker(
  SqliteSelfEngineRepositoryV2 repository,
  Database database,
  _FakeSynthesizer synthesizer,
  DateTime Function() clock,
) => ThesisWorkerV2(
  repository: repository,
  processor: PersonalThesisJobProcessorV2(
    repository: repository,
    candidateRetriever: SqlitePersonalThesisCandidateRetrieverV2(database),
    synthesizer: synthesizer,
    clock: clock,
  ),
  availability: const _Availability(),
  clock: clock,
);

Future<void> _publishValid(
  SqliteSelfEngineRepositoryV2 repository,
  Database database,
  DateTime now,
) async {
  final synth = _FakeSynthesizer((request) async {
    return PersonalThesisSynthesisDecisionV2.create(
      statement: '我可能在规律运动后更容易恢复平静',
      rationale: '多次记录支持这个可修正的暂定解释。',
      maturity: PersonalThesisMaturityV2.candidate,
      supportAtomIds: request.supportCandidates
          .take(2)
          .map((item) => item.atom.id)
          .toList(),
      counterAtomIds: const [],
    );
  });
  expect(
    await _worker(repository, database, synth, () => now).runOnce(),
    SelfEngineRunResultV2.completed,
  );
}

Future<_Fixture> _eligibleFixture(
  Database database, {
  required DateTime now,
  String threadId = 'thread',
  String idPrefix = '',
  bool withCounter = false,
  bool enqueue = true,
}) async {
  final atoms = <_SeededAtom>[];
  for (var i = 0; i < 3; i++) {
    atoms.add(
      await _seedAtom(
        database,
        '$idPrefix${threadId}d$i',
        DateTime.utc(2026, 1, 1).add(Duration(days: i * 10)),
        extraAtom: i == 0,
      ),
    );
  }
  await _seedThread(database, threadId, atoms);
  await database.insert('thread_memberships', {
    'thread_id': threadId,
    'atom_id': '${atoms.first.diaryId}-a2',
    'relevance': 1.0,
    'origin': 'automatic',
    'generation': 1,
    'created_at': atoms.first.observedAt.toUtc().toIso8601String(),
  });
  await database.insert('thread_derivation_atoms', {
    'thread_id': threadId,
    'atom_id': '${atoms.first.diaryId}-a2',
    'generation': 1,
    'created_at': atoms.first.observedAt.toUtc().toIso8601String(),
  });
  if (withCounter) {
    await _seedAtom(
      database,
      '$idPrefix${threadId}counter',
      DateTime.utc(2025, 12, 1),
      statement: '有时休息而不是运动也能让我恢复平静',
    );
  }
  if (enqueue) {
    expect(
      await _enqueue(database, threadId, atoms.last.revisionId, now),
      isTrue,
    );
  }
  return _Fixture(
    threadId: threadId,
    diaryIds: atoms.map((item) => item.diaryId).toList(),
  );
}

Future<_SeededAtom> _seedAtom(
  Database database,
  String diaryId,
  DateTime date, {
  String statement = '运动之后我更容易恢复平静',
  bool extraAtom = false,
  int generation = 1,
}) async {
  final stamp = date.toUtc().toIso8601String();
  final revisionId = '$diaryId-r1';
  final atomId = '$diaryId-a1';
  final entry = DiaryEntryV2(
    id: diaryId,
    body: statement,
    entryDate: date,
    createdAt: date,
    updatedAt: date,
  );
  await database.insert('diary_entries', {
    'id': diaryId,
    'body': statement,
    'entry_date': stamp,
    'created_at': stamp,
    'updated_at': stamp,
    'image_ids': '[]',
    'tags': '[]',
    'ai_analyses': '[]',
    'is_favorite': 0,
  });
  await database.insert('diary_revisions', {
    'id': revisionId,
    'diary_id': diaryId,
    'revision_no': 1,
    'body': statement,
    'source_hash': DiarySourceFingerprintV2.calculate(entry),
    'fingerprint_version': 1,
    'entry_date': stamp,
    'tags': '[]',
    'created_at': stamp,
  });
  await database.insert('memory_atoms', {
    'id': atomId,
    'revision_id': revisionId,
    'kind': 'feeling',
    'statement': statement,
    'source_quote': statement,
    'observed_at': stamp,
    'scope': 'state',
    'pipeline_version': 1,
    'generation': generation,
    'created_at': stamp,
  });
  if (extraAtom) {
    await database.insert('memory_atoms', {
      'id': '$diaryId-a2',
      'revision_id': revisionId,
      'kind': 'event',
      'statement': '同一天的另一次运动也让我安静下来',
      'source_quote': '同一天的另一次运动也让我安静下来',
      'observed_at': stamp,
      'scope': 'state',
      'pipeline_version': 1,
      'generation': generation,
      'created_at': stamp,
    });
  }
  return _SeededAtom(
    diaryId: diaryId,
    revisionId: revisionId,
    atomId: atomId,
    observedAt: date,
  );
}

Future<void> _seedThread(
  Database database,
  String threadId,
  List<_SeededAtom> atoms,
) async {
  final dates = atoms.map((item) => item.observedAt).toList()..sort();
  final now = DateTime.utc(2026, 9, 1).toIso8601String();
  await database.insert('memory_threads', {
    'id': threadId,
    'title': '运动与情绪恢复',
    'description': '记录运动与情绪恢复之间反复出现的联系。',
    'status': 'active',
    'first_seen': dates.first.toUtc().toIso8601String(),
    'last_seen': dates.last.toUtc().toIso8601String(),
    'pipeline_version': 1,
    'generation': 1,
    'created_at': now,
    'updated_at': now,
  });
  for (final atom in atoms) {
    await _attach(database, threadId, atom);
  }
}

Future<void> _attach(
  Database database,
  String threadId,
  _SeededAtom atom,
) async {
  final stamp = atom.observedAt.toUtc().toIso8601String();
  await database.insert('thread_memberships', {
    'thread_id': threadId,
    'atom_id': atom.atomId,
    'relevance': 1.0,
    'origin': 'automatic',
    'generation': 1,
    'created_at': stamp,
  });
  await database.insert('thread_derivation_atoms', {
    'thread_id': threadId,
    'atom_id': atom.atomId,
    'generation': 1,
    'created_at': stamp,
  });
}

Future<bool> _enqueue(
  Database database,
  String threadId,
  String revisionId,
  DateTime now,
) => ThesisWorkV2.enqueueIfEligible(
  database,
  threadId: threadId,
  triggerRevisionId: revisionId,
  origin: SelfEngineJobOriginV2.live,
  generation: 1,
  now: now,
);

class _Fixture {
  const _Fixture({required this.threadId, required this.diaryIds});
  final String threadId;
  final List<String> diaryIds;
}

class _ExternalProvenanceFixture {
  const _ExternalProvenanceFixture({
    required this.threadId,
    required this.thesisId,
    required this.versionId,
    required this.externalDiaryId,
    required this.externalAtomId,
  });

  final String threadId;
  final String thesisId;
  final String versionId;
  final String externalDiaryId;
  final String externalAtomId;
}

class _SeededAtom {
  const _SeededAtom({
    required this.diaryId,
    required this.revisionId,
    required this.atomId,
    required this.observedAt,
  });
  final String diaryId;
  final String revisionId;
  final String atomId;
  final DateTime observedAt;
}

class _FakeSynthesizer implements PersonalThesisSynthesizerV2 {
  _FakeSynthesizer(this.handler);
  final Future<PersonalThesisSynthesisDecisionV2> Function(
    PersonalThesisSynthesisRequestV2 request,
  )
  handler;
  final requests = <PersonalThesisSynthesisRequestV2>[];
  int calls = 0;

  @override
  Future<PersonalThesisSynthesisDecisionV2> synthesize(
    PersonalThesisSynthesisRequestV2 request,
  ) {
    calls++;
    requests.add(request);
    return handler(request);
  }
}

class _Availability implements SelfEngineAvailabilityV2 {
  const _Availability([this.available = true]);
  final bool available;
  @override
  Future<bool> canProcess() async => available;
}

class _CountingRunner implements SelfEngineRunnerV2 {
  int calls = 0;
  @override
  Future<SelfEngineRunResultV2> runOnce() async {
    calls++;
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
