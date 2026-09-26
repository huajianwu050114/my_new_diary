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
import 'package:my_new_diary/features/self_engine/application/memory_thread_link_job_processor_v2.dart';
import 'package:my_new_diary/features/self_engine/application/ports/memory_extractor_v2.dart';
import 'package:my_new_diary/features/self_engine/application/ports/memory_thread_linker_v2.dart';
import 'package:my_new_diary/features/self_engine/application/ports/self_engine_availability_v2.dart';
import 'package:my_new_diary/features/self_engine/application/ports/self_engine_runner_v2.dart';
import 'package:my_new_diary/features/self_engine/application/self_engine_pipeline_runner_v2.dart';
import 'package:my_new_diary/features/self_engine/application/self_engine_worker_v2.dart';
import 'package:my_new_diary/features/self_engine/application/thread_link_worker_v2.dart';
import 'package:my_new_diary/features/self_engine/data/ai/ai_memory_thread_linker_v2.dart';
import 'package:my_new_diary/features/self_engine/data/local/sqlite_memory_thread_candidate_retriever_v2.dart';
import 'package:my_new_diary/features/self_engine/data/local/sqlite_self_engine_repository_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/diary_revision_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/memory_extraction_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/memory_atom_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/memory_thread_link_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/self_engine_job_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/self_engine_pipeline_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Phase B2 Thread pipeline', () {
    late DiaryDatabaseV2 owner;
    late Database database;
    late SqliteDiaryRepositoryV2 diary;
    late SqliteSelfEngineRepositoryV2 self;
    late SqliteMemoryThreadCandidateRetrieverV2 candidates;
    late _FakeThreadLinker linker;
    late SelfEngineWorkerV2 extractionWorker;
    late ThreadLinkWorkerV2 linkWorker;
    late DateTime now;

    setUp(() async {
      owner = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => inMemoryDatabasePath,
      );
      database = await owner.open();
      diary = SqliteDiaryRepositoryV2(database);
      self = SqliteSelfEngineRepositoryV2(database);
      candidates = SqliteMemoryThreadCandidateRetrieverV2(database);
      linker = _FakeThreadLinker(_recurringThemeDecision);
      now = DateTime.utc(2026, 9, 1, 12);
      extractionWorker = SelfEngineWorkerV2(
        repository: self,
        processor: MemoryAtomJobProcessorV2(
          repository: self,
          extractor: const _OneAtomExtractor(),
          clock: () => now,
        ),
        availability: const _Availability(true),
        clock: () => now,
      );
      linkWorker = ThreadLinkWorkerV2(
        repository: self,
        processor: MemoryThreadLinkJobProcessorV2(
          repository: self,
          candidateRetriever: candidates,
          linker: linker,
          clock: () => now,
        ),
        availability: const _Availability(true),
        clock: () => now,
      );
    });

    tearDown(() async {
      await diary.dispose();
      await owner.close();
    });

    Future<void> saveExtractLink({
      required String id,
      required String body,
      required DateTime date,
    }) async {
      now = date.add(const Duration(hours: 12));
      await diary.save(_entry(id: id, body: body, date: date));
      expect(await extractionWorker.runOnce(), SelfEngineRunResultV2.completed);
      expect(await linkWorker.runOnce(), SelfEngineRunResultV2.completed);
    }

    test('none, create, then attach forms one longitudinal Thread', () async {
      await saveExtractLink(
        id: 'd1',
        body: '跑步帮助我的情绪恢复',
        date: DateTime.utc(2026, 1, 1),
      );
      expect(await database.query('memory_threads'), isEmpty);
      expect(linker.calls, 0, reason: 'A singleton is resolved locally.');

      await saveExtractLink(
        id: 'd2',
        body: '今天跑步后情绪恢复了一些',
        date: DateTime.utc(2026, 2, 1),
      );
      var threads = await database.query('memory_threads');
      expect(threads, hasLength(1));
      expect(await database.query('thread_memberships'), hasLength(2));
      expect(
        threads.single['first_seen'],
        DateTime.utc(2026, 1, 1).toIso8601String(),
      );
      expect(
        threads.single['last_seen'],
        DateTime.utc(2026, 2, 1).toIso8601String(),
      );

      await saveExtractLink(
        id: 'd3',
        body: '跑步依然帮助情绪恢复',
        date: DateTime.utc(2026, 3, 1),
      );
      threads = await database.query('memory_threads');
      expect(threads, hasLength(1));
      expect(await database.query('thread_memberships'), hasLength(3));
      expect(
        threads.single['last_seen'],
        DateTime.utc(2026, 3, 1).toIso8601String(),
      );
      expect(linker.calls, 2);
    });

    test('revisions of one Diary never satisfy recurrence', () async {
      await saveExtractLink(
        id: 'same',
        body: '跑步帮助情绪恢复',
        date: DateTime.utc(2026, 1, 1),
      );
      now = DateTime.utc(2026, 1, 2);
      await diary.save(
        _entry(
          id: 'same',
          body: '跑步仍然帮助情绪恢复',
          date: DateTime.utc(2026, 1, 1),
          updatedAt: now,
        ),
      );
      expect(await extractionWorker.runOnce(), SelfEngineRunResultV2.completed);
      expect(await linkWorker.runOnce(), SelfEngineRunResultV2.completed);

      expect(await database.query('diary_revisions'), hasLength(2));
      expect(await database.query('memory_atoms'), hasLength(2));
      expect(
        (await database.query(
          'memory_atoms',
          where: 'superseded_at IS NOT NULL',
        )),
        hasLength(1),
      );
      expect(await database.query('memory_threads'), isEmpty);
      expect(linker.calls, 0);
    });

    test('invalid candidate IDs retry and do not publish', () async {
      await saveExtractLink(
        id: 'a',
        body: '升学选择让我反复思考',
        date: DateTime.utc(2026, 1, 1),
      );
      linker.handler = (_) async => const MemoryThreadLinkDecisionV2(
        actions: [MemoryThreadLinkActionV2.attach(threadId: 'invented')],
      );
      now = DateTime.utc(2026, 2, 1, 12);
      await diary.save(
        _entry(id: 'b', body: '我还在思考升学选择', date: DateTime.utc(2026, 2, 1)),
      );
      await extractionWorker.runOnce();

      expect(await linkWorker.runOnce(), SelfEngineRunResultV2.retryScheduled);
      expect(await database.query('memory_threads'), isEmpty);
      final job = (await self.getThreadLinkJobs()).last;
      expect(job.status, SelfEngineJobStatusV2.retryable);
      expect(job.attemptCount, 1);
    });

    test('more than two memberships is rejected', () async {
      await saveExtractLink(
        id: 'a',
        body: '创作软件让我获得自由',
        date: DateTime.utc(2026, 1, 1),
      );
      linker.handler = (request) async => MemoryThreadLinkDecisionV2(
        actions: [
          for (var index = 0; index < 3; index++)
            MemoryThreadLinkActionV2.create(
              title: '创作与自由 $index',
              description: '关于创作软件与自由感的长期记录。',
              candidateAtomIds: [request.atomCandidates.first.atom.id],
            ),
        ],
      );
      now = DateTime.utc(2026, 2, 1, 12);
      await diary.save(
        _entry(id: 'b', body: '创作软件也让我接近自由', date: DateTime.utc(2026, 2, 1)),
      );
      await extractionWorker.runOnce();

      expect(await linkWorker.runOnce(), SelfEngineRunResultV2.retryScheduled);
      expect(await database.query('memory_threads'), isEmpty);
    });

    test(
      'unavailable AI leaves link work pending without burning attempts',
      () async {
        now = DateTime.utc(2026, 1, 1, 12);
        await diary.save(
          _entry(id: 'a', body: '家庭沟通与边界', date: DateTime.utc(2026, 1, 1)),
        );
        await extractionWorker.runOnce();
        final unavailable = ThreadLinkWorkerV2(
          repository: self,
          processor: MemoryThreadLinkJobProcessorV2(
            repository: self,
            candidateRetriever: candidates,
            linker: linker,
            clock: () => now,
          ),
          availability: const _Availability(false),
          clock: () => now,
        );

        expect(await unavailable.runOnce(), SelfEngineRunResultV2.unavailable);
        final job = (await self.getThreadLinkJobs()).single;
        expect(job.status, SelfEngineJobStatusV2.pending);
        expect(job.attemptCount, 0);
      },
    );

    test(
      'historical extraction creates link work that default worker ignores',
      () async {
        await diary.restoreFromBackup(
          _entry(
            id: 'legacy',
            body: '历史家庭沟通与边界',
            date: DateTime.utc(2020, 1, 1),
          ),
        );
        await self.backfillMissingRevisions();
        final sourceJob = await self.claimNextJob(
          now: now,
          origin: SelfEngineJobOriginV2.historical,
        );
        await MemoryAtomJobProcessorV2(
          repository: self,
          extractor: const _OneAtomExtractor(),
          clock: () => now,
        ).process(sourceJob!);

        expect(await linkWorker.runOnce(), SelfEngineRunResultV2.noWork);
        final linkJob = (await self.getThreadLinkJobs()).single;
        expect(linkJob.origin, SelfEngineJobOriginV2.historical);
        expect(linkJob.status, SelfEngineJobStatusV2.pending);
        expect(linkJob.attemptCount, 0);
        expect(linker.calls, 0);
      },
    );

    test(
      'expired link lease is reclaimed and stale owner cannot publish',
      () async {
        await saveExtractLink(
          id: 'a',
          body: '跑步帮助情绪恢复',
          date: DateTime.utc(2026, 1, 1),
        );
        now = DateTime.utc(2026, 2, 1, 12);
        await diary.save(
          _entry(id: 'b', body: '跑步之后情绪恢复', date: DateTime.utc(2026, 2, 1)),
        );
        await extractionWorker.runOnce();
        final old = await self.claimNextThreadLinkJob(
          now: now,
          leaseDuration: const Duration(minutes: 1),
        );
        final reclaimedAt = now.add(const Duration(minutes: 3));
        await self.recoverExpiredThreadLinkLeases(now: reclaimedAt);
        final freshAt = reclaimedAt.add(const Duration(minutes: 2));
        final fresh = await self.claimNextThreadLinkJob(now: freshAt);

        expect(old, isNotNull);
        expect(fresh, isNotNull);
        expect(fresh!.id, old!.id);
        expect(fresh.leaseId, isNot(old.leaseId));
        expect(
          await self.publishThreadLinks(
            old.id,
            leaseId: old.leaseId!,
            publishedAt: reclaimedAt,
            operations: const [],
          ),
          isFalse,
        );
        expect(
          await self.publishThreadLinks(
            fresh.id,
            leaseId: fresh.leaseId!,
            publishedAt: freshAt.add(const Duration(minutes: 1)),
            operations: const [],
          ),
          isTrue,
        );
      },
    );

    test('Thread worker is single-flight during a slow linker call', () async {
      await saveExtractLink(
        id: 'a',
        body: '跑步帮助情绪恢复',
        date: DateTime.utc(2026, 1, 1),
      );
      final started = Completer<void>();
      final release = Completer<void>();
      var active = 0;
      var maxActive = 0;
      linker.handler = (request) async {
        active++;
        if (active > maxActive) maxActive = active;
        if (!started.isCompleted) started.complete();
        await release.future;
        active--;
        return _recurringThemeDecision(request);
      };
      now = DateTime.utc(2026, 2, 1, 12);
      await diary.save(
        _entry(id: 'b', body: '跑步之后情绪恢复', date: DateTime.utc(2026, 2, 1)),
      );
      await extractionWorker.runOnce();

      final first = linkWorker.runOnce();
      await started.future;
      final sameFlight = linkWorker.runOnce();
      release.complete();

      expect(await first, SelfEngineRunResultV2.completed);
      expect(await sameFlight, SelfEngineRunResultV2.completed);
      expect(linker.calls, 1);
      expect(maxActive, 1);
      expect(await database.query('memory_threads'), hasLength(1));
    });

    test(
      'publish rollback and retry cannot duplicate a created Thread',
      () async {
        await saveExtractLink(
          id: 'a',
          body: '努力之后我在意回报',
          date: DateTime.utc(2026, 1, 1),
        );
        now = DateTime.utc(2026, 2, 1, 12);
        await diary.save(
          _entry(id: 'b', body: '努力和回报仍然困扰我', date: DateTime.utc(2026, 2, 1)),
        );
        await extractionWorker.runOnce();
        final job = await self.claimNextThreadLinkJob(now: now);
        final atoms = await candidates.activeAtomsForRevision(job!.revisionId);
        final request = await candidates.retrieve(atoms.single.atom.id);
        final candidateId = request!.atomCandidates.first.atom.id;
        final threadId = 'thread-${job.id}-1-1';
        final create = ThreadLinkOperationV2.create(
          currentAtomId: atoms.single.atom.id,
          threadId: threadId,
          title: '努力与回报感',
          description: '关于努力、结果与回报感受的长期记录。',
          candidateAtomIds: [candidateId],
          derivationAtomIds: [atoms.single.atom.id, candidateId],
        );

        await expectLater(
          self.publishThreadLinks(
            job.id,
            leaseId: job.leaseId!,
            publishedAt: now,
            operations: [
              create,
              ThreadLinkOperationV2.attach(
                currentAtomId: atoms.single.atom.id,
                threadId: 'missing',
              ),
            ],
          ),
          throwsA(anything),
        );
        expect(await database.query('memory_threads'), isEmpty);
        await self.markThreadLinkJobFailed(
          job.id,
          leaseId: job.leaseId!,
          failedAt: now,
          error: 'simulated publish failure',
        );
        final retryAt = (await self.getThreadLinkJobs()).last.nextRetryAt!;
        final retry = await self.claimNextThreadLinkJob(
          now: retryAt.add(const Duration(milliseconds: 1)),
        );
        expect(
          await self.publishThreadLinks(
            retry!.id,
            leaseId: retry.leaseId!,
            publishedAt: retryAt.add(const Duration(milliseconds: 1)),
            operations: [create],
          ),
          isTrue,
        );
        expect(await database.query('memory_threads'), hasLength(1));
        expect(await database.query('thread_memberships'), hasLength(2));
      },
    );

    test('generation change prevents a stale link worker publish', () async {
      await saveExtractLink(
        id: 'a',
        body: '孤独与连接的体验',
        date: DateTime.utc(2026, 1, 1),
      );
      now = DateTime.utc(2026, 2, 1, 12);
      await diary.save(
        _entry(id: 'b', body: '我仍在体验孤独与连接', date: DateTime.utc(2026, 2, 1)),
      );
      await extractionWorker.runOnce();
      final job = await self.claimNextThreadLinkJob(now: now);
      await self.clearAllDerivedDataForGlobalRebuild();

      expect(
        await self.publishThreadLinks(
          job!.id,
          leaseId: job.leaseId!,
          publishedAt: now,
          operations: const [],
        ),
        isFalse,
      );
      expect(await database.query('memory_threads'), isEmpty);
    });

    test(
      'edit invalidates old Thread, preserves history, and requeues survivors',
      () async {
        await saveExtractLink(
          id: 'a',
          body: '家庭沟通需要边界',
          date: DateTime.utc(2026, 1, 1),
        );
        await saveExtractLink(
          id: 'b',
          body: '家庭沟通中的边界让我在意',
          date: DateTime.utc(2026, 2, 1),
        );
        expect(await database.query('memory_threads'), hasLength(1));

        now = DateTime.utc(2026, 3, 1, 12);
        await diary.save(
          _entry(
            id: 'a',
            body: '现在我更关注旅行计划',
            date: DateTime.utc(2026, 1, 1),
            updatedAt: now,
          ),
        );
        await extractionWorker.runOnce();

        expect(await database.query('memory_threads'), isEmpty);
        expect(await database.query('diary_revisions'), hasLength(3));
        final oldAtoms = await database.rawQuery('''
        SELECT a.* FROM memory_atoms a
        JOIN diary_revisions r ON r.id = a.revision_id
        WHERE r.diary_id = 'a' AND a.superseded_at IS NOT NULL
        ''');
        expect(oldAtoms, hasLength(1));
        final pending = await self.getThreadLinkJobs(
          status: SelfEngineJobStatusV2.pending,
        );
        expect(pending.map((job) => job.diaryId), containsAll(['a', 'b']));
      },
    );

    test(
      'permanent deletion removes derived private text and safely rebuilds',
      () async {
        await saveExtractLink(
          id: 'a',
          body: '私人升学线索与去向选择',
          date: DateTime.utc(2026, 1, 1),
        );
        await saveExtractLink(
          id: 'b',
          body: '升学与去向选择仍在继续',
          date: DateTime.utc(2026, 2, 1),
        );
        expect(
          (await database.query('memory_threads')).single['title'],
          '升学与去向选择',
        );

        await diary.deletePermanently('a');

        expect(await database.query('memory_threads'), isEmpty);
        expect(await database.query('thread_memberships'), isEmpty);
        expect(
          await database.rawQuery(
            "SELECT * FROM memory_threads WHERE title LIKE '%私人%' "
            "OR description LIKE '%私人%'",
          ),
          isEmpty,
        );
        final pending = await self.getThreadLinkJobs(
          status: SelfEngineJobStatusV2.pending,
        );
        expect(pending.map((job) => job.diaryId), contains('b'));
        expect(await linkWorker.runOnce(), SelfEngineRunResultV2.completed);
        expect(await database.query('memory_threads'), isEmpty);

        await saveExtractLink(
          id: 'c',
          body: '我的升学去向选择有了新变化',
          date: DateTime.utc(2026, 3, 1),
        );
        expect(await database.query('memory_threads'), hasLength(1));
        expect(await database.query('thread_memberships'), hasLength(2));
      },
    );

    test(
      'deleting prompt-only derivation evidence invalidates the Thread',
      () async {
        for (final (id, month) in [('a', 1), ('b', 2), ('c', 3)]) {
          now = DateTime.utc(2026, month, 1, 12);
          await diary.save(
            _entry(
              id: id,
              body: '共同主题中的私人线索 $id',
              date: DateTime.utc(2026, month, 1),
            ),
          );
          await extractionWorker.runOnce();
        }
        linker.handler = (request) async {
          if (request.currentAtom.diaryId != 'c') {
            return const MemoryThreadLinkDecisionV2();
          }
          return MemoryThreadLinkDecisionV2(
            actions: [
              MemoryThreadLinkActionV2.create(
                title: '共同主题',
                description: '关于共同主题及其私人线索的长期记录。',
                candidateAtomIds: [request.atomCandidates.first.atom.id],
              ),
            ],
          );
        };
        expect(await linkWorker.runOnce(), SelfEngineRunResultV2.completed);
        expect(await linkWorker.runOnce(), SelfEngineRunResultV2.completed);
        expect(await linkWorker.runOnce(), SelfEngineRunResultV2.completed);
        expect(await database.query('memory_threads'), hasLength(1));
        expect(await database.query('thread_derivation_atoms'), hasLength(3));
        final unselected =
            (await database.rawQuery('''
        SELECT DISTINCT r.diary_id
        FROM thread_derivation_atoms source
        JOIN memory_atoms a ON a.id = source.atom_id
        JOIN diary_revisions r ON r.id = a.revision_id
        WHERE NOT EXISTS (
          SELECT 1 FROM thread_memberships m
          WHERE m.thread_id = source.thread_id AND m.atom_id = source.atom_id
        )
        ''')).single['diary_id']!
                as String;

        await diary.deletePermanently(unselected);

        expect(await database.query('memory_threads'), isEmpty);
        expect(await database.query('thread_derivation_atoms'), isEmpty);
      },
    );

    test(
      'bounded pipeline continues extraction into one link opportunity',
      () async {
        final pipeline = SelfEnginePipelineRunnerV2(
          extractionRunner: extractionWorker,
          threadLinkRunner: linkWorker,
        );
        now = DateTime.utc(2026, 1, 1, 12);
        await diary.save(
          _entry(id: 'a', body: '创作个人软件', date: DateTime.utc(2026, 1, 1)),
        );

        expect(await pipeline.runOnce(), SelfEngineRunResultV2.completed);
        expect(
          (await self.getJobs()).single.status,
          SelfEngineJobStatusV2.completed,
        );
        expect(
          (await self.getThreadLinkJobs()).single.status,
          SelfEngineJobStatusV2.completed,
        );
      },
    );

    test(
      'pipeline triggers coalesce into one serial follow-up opportunity',
      () async {
        final extraction = _BlockingRunner();
        final linking = _CountingRunner();
        final pipeline = SelfEnginePipelineRunnerV2(
          extractionRunner: extraction,
          threadLinkRunner: linking,
        );

        final first = pipeline.runOnce();
        await extraction.started.future;
        final coalesced = pipeline.runOnce();
        extraction.release.complete();

        expect(await first, SelfEngineRunResultV2.completed);
        expect(await coalesced, SelfEngineRunResultV2.completed);
        expect(extraction.calls, 2);
        expect(linking.calls, 2);
        expect(extraction.maxActive, 1);
      },
    );
  });

  group('Phase B2 bounded candidates', () {
    late DiaryDatabaseV2 owner;
    late Database database;
    late SqliteDiaryRepositoryV2 diary;

    setUp(() async {
      owner = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => inMemoryDatabasePath,
      );
      database = await owner.open();
      diary = SqliteDiaryRepositoryV2(database);
    });

    tearDown(() async {
      await diary.dispose();
      await owner.close();
    });

    test(
      'hundreds of active Atoms are locally reduced to a hard bound',
      () async {
        for (var index = 0; index < 240; index++) {
          await diary.save(
            _entry(
              id: 'archive-$index',
              body: '跑步情绪记录 $index',
              date: DateTime.utc(2016 + (index ~/ 24), (index % 12) + 1, 1),
            ),
          );
        }
        await diary.save(
          _entry(
            id: 'current',
            body: '跑步帮助情绪恢复',
            date: DateTime.utc(2026, 9, 1),
          ),
        );
        final revisions = await database.query('diary_revisions');
        for (final revision in revisions) {
          await _insertAtom(
            database,
            revisionId: revision['id']! as String,
            id: 'atom-${revision['diary_id']}',
            text: revision['body']! as String,
            generation: 1,
            observedAt: revision['entry_date']! as String,
          );
        }
        final retriever = SqliteMemoryThreadCandidateRetrieverV2(database);
        final result = await retriever.retrieve('atom-current');

        expect(result, isNotNull);
        expect(result!.atomCandidates.length, 16);
        expect(result.atomCandidates.length, lessThan(revisions.length));
        expect(result.threadCandidates.length, lessThanOrEqualTo(8));
      },
    );

    test(
      'superseded, deleted, stale-generation, and archived evidence is excluded',
      () async {
        for (final id in [
          'current',
          'active',
          'deleted',
          'stale-a',
          'stale-b',
          'current-2',
          'active-2',
        ]) {
          await diary.save(
            _entry(id: id, body: '家庭沟通与边界 $id', date: DateTime.utc(2026, 1, 1)),
          );
        }
        final revisions = await database.query('diary_revisions');
        String revisionFor(String id) =>
            revisions.singleWhere((row) => row['diary_id'] == id)['id']!
                as String;
        for (final id in ['current', 'active', 'deleted']) {
          await _insertAtom(
            database,
            revisionId: revisionFor(id),
            id: 'atom-$id',
            text: '家庭沟通与边界 $id',
            generation: 1,
            observedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
          );
        }
        await database.update(
          'memory_atoms',
          {'superseded_at': DateTime.utc(2026, 2, 1).toIso8601String()},
          where: 'id = ?',
          whereArgs: ['atom-active'],
        );
        await diary.moveToTrash('deleted', deletedAt: DateTime.utc(2026, 2, 1));
        await _insertAtom(
          database,
          revisionId: revisionFor('stale-a'),
          id: 'atom-stale-a',
          text: '家庭沟通与边界 stale',
          generation: 1,
          observedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
        );
        await _insertAtom(
          database,
          revisionId: revisionFor('stale-b'),
          id: 'atom-stale-b',
          text: '家庭沟通与边界 stale',
          generation: 1,
          observedAt: DateTime.utc(2026, 1, 2).toIso8601String(),
        );
        final stamp = DateTime.utc(2026, 1, 1).toIso8601String();
        await database.insert('memory_threads', {
          'id': 'archived',
          'title': '家庭沟通与边界',
          'description': 'archived evidence',
          'status': 'archived',
          'first_seen': stamp,
          'last_seen': stamp,
          'pipeline_version': 1,
          'generation': 1,
          'created_at': stamp,
          'updated_at': stamp,
        });
        await database.insert('memory_threads', {
          'id': 'merged',
          'title': '家庭沟通与边界',
          'description': 'merged evidence',
          'status': 'merged',
          'first_seen': stamp,
          'last_seen': stamp,
          'pipeline_version': 1,
          'generation': 1,
          'created_at': stamp,
          'updated_at': stamp,
        });
        for (final threadId in ['archived', 'merged']) {
          for (final atomId in ['atom-stale-a', 'atom-stale-b']) {
            await database.insert('thread_memberships', {
              'thread_id': threadId,
              'atom_id': atomId,
              'relevance': 1.0,
              'origin': 'automatic',
              'generation': 1,
              'created_at': stamp,
            });
          }
        }
        final retriever = SqliteMemoryThreadCandidateRetrieverV2(database);
        final beforeGenerationChange = await retriever.retrieve('atom-current');
        expect(beforeGenerationChange, isNotNull);
        expect(beforeGenerationChange!.atomCandidates, isEmpty);
        expect(beforeGenerationChange.threadCandidates, isEmpty);

        await database.update('self_engine_state', {
          'generation': 2,
        }, where: 'id = 1');
        await _insertAtom(
          database,
          revisionId: revisionFor('current-2'),
          id: 'atom-current-2',
          text: '家庭沟通与边界 current',
          generation: 2,
          observedAt: DateTime.utc(2026, 3, 1).toIso8601String(),
        );
        await _insertAtom(
          database,
          revisionId: revisionFor('active-2'),
          id: 'atom-active-2',
          text: '家庭沟通与边界 active',
          generation: 2,
          observedAt: DateTime.utc(2026, 3, 2).toIso8601String(),
        );
        final afterGenerationChange = await retriever.retrieve(
          'atom-current-2',
        );
        expect(afterGenerationChange, isNotNull);
        expect(
          afterGenerationChange!.atomCandidates.map((item) => item.atom.id),
          ['atom-active-2'],
        );
        expect(afterGenerationChange.threadCandidates, isEmpty);
      },
    );
  });

  group('Phase B2 schema v13', () {
    test('fresh v13 has the durable link queue and strict FK', () async {
      final owner = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => inMemoryDatabasePath,
      );
      final database = await owner.open();
      addTearDown(owner.close);
      expect(await database.query('thread_link_jobs'), isEmpty);
      expect(await database.query('thread_derivation_atoms'), isEmpty);
      expect(
        () => database.insert('thread_link_jobs', {
          'id': 'bad',
          'revision_id': 'missing',
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
    });

    test('v12 upgrades to v13 while preserving source state', () async {
      final temp = await Directory.systemTemp.createTemp('diary-v13-test-');
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
      final diary = SqliteDiaryRepositoryV2(database);
      await diary.save(
        _entry(id: 'kept', body: 'preserved', date: DateTime.utc(2026, 1, 1)),
      );
      final revision = (await database.query('diary_revisions')).single;
      final stamp = DateTime.utc(2026, 1, 1).toIso8601String();
      await _insertAtom(
        database,
        revisionId: revision['id']! as String,
        id: 'preserved-atom',
        text: 'preserved',
        generation: 1,
        observedAt: stamp,
      );
      await database.insert('memory_threads', {
        'id': 'preserved-thread',
        'title': 'Preserved topic',
        'description': 'Preserved v12 derived state.',
        'status': 'active',
        'first_seen': stamp,
        'last_seen': stamp,
        'pipeline_version': 1,
        'generation': 1,
        'created_at': stamp,
        'updated_at': stamp,
      });
      await database.insert('thread_memberships', {
        'thread_id': 'preserved-thread',
        'atom_id': 'preserved-atom',
        'relevance': 1.0,
        'origin': 'automatic',
        'generation': 1,
        'created_at': stamp,
      });
      await diary.dispose();
      await first.close();

      final raw = await databaseFactoryFfi.openDatabase(path);
      await raw.execute('DROP TABLE thread_derivation_atoms');
      await raw.execute('DROP TABLE thread_link_jobs');
      await raw.execute('DROP INDEX memory_atoms_active_candidate_index');
      await raw.execute('PRAGMA user_version = 12');
      await raw.close();

      final upgraded = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => path,
      );
      final opened = await upgraded.open();
      addTearDown(upgraded.close);
      expect(await opened.query('diary_entries'), hasLength(1));
      expect(await opened.query('diary_revisions'), hasLength(1));
      expect(await opened.query('self_engine_jobs'), hasLength(1));
      expect(await opened.query('thread_link_jobs'), isEmpty);
      expect(await opened.query('memory_atoms'), hasLength(1));
      expect(await opened.query('memory_threads'), hasLength(1));
      expect(await opened.query('thread_memberships'), hasLength(1));
      final repository = SqliteSelfEngineRepositoryV2(opened);
      expect(await repository.backfillMissingThreadLinkJobs(limit: 1), 1);
      expect(await repository.backfillMissingThreadLinkJobs(limit: 1), 0);
      final linkJob = (await repository.getThreadLinkJobs()).single;
      expect(linkJob.origin, SelfEngineJobOriginV2.live);
      expect(linkJob.status, SelfEngineJobStatusV2.pending);
    });

    test('v13 onOpen rejects missing link-queue indexes', () async {
      final temp = await Directory.systemTemp.createTemp('diary-v13-drift-');
      final path = '${temp.path}${Platform.pathSeparator}drift.db';
      addTearDown(() async {
        await databaseFactoryFfi.deleteDatabase(path);
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final first = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => path,
      );
      await first.open();
      await first.close();
      final raw = await databaseFactoryFfi.openDatabase(path);
      await raw.execute('DROP INDEX thread_link_jobs_origin_ready_index');
      await raw.close();

      final drifted = DiaryDatabaseV2(
        factory: databaseFactoryFfi,
        databasePath: () async => path,
      );
      await expectLater(drifted.open(), throwsA(isA<StateError>()));
    });
  });

  test(
    'AI linker payload is bounded evidence, not full or unrelated Diaries',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secrets = _SecretStore();
      final store = AiConfigurationStoreV2(secretStore: secrets);
      await store.save(
        enabled: true,
        selfEngineEnabled: true,
        provider: AiProviderV2.gemini,
        model: 'test-model',
        modelStrategy: AiModelStrategyV2.custom,
        apiKey: 'API-SECRET',
      );
      late String body;
      final client = GeminiRestClientV2(
        configurationStore: store,
        httpClient: MockClient((request) async {
          body = request.body;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '{"actions":[]}'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      final current = _evidence(
        'current',
        'current-statement',
        'CURRENT-QUOTE',
      );
      final candidate = _evidence(
        'candidate',
        'candidate-statement',
        'CANDIDATE-QUOTE',
      );

      await AiMemoryThreadLinkerV2(client).link(
        MemoryThreadLinkRequestV2(
          currentAtom: current,
          threadCandidates: const [],
          atomCandidates: [candidate],
        ),
      );

      expect(body, contains('current-statement'));
      expect(body, contains('CURRENT-QUOTE'));
      expect(body, contains('candidate-statement'));
      expect(body, contains('CANDIDATE-QUOTE'));
      expect(body, isNot(contains('UNRELATED-FULL-DIARY')));
      expect(body, isNot(contains('API-SECRET')));
      expect(body, isNot(contains('"confidence":')));
    },
  );
}

Future<MemoryThreadLinkDecisionV2> _recurringThemeDecision(
  MemoryThreadLinkRequestV2 request,
) async {
  if (request.threadCandidates.isNotEmpty) {
    return MemoryThreadLinkDecisionV2(
      actions: [
        MemoryThreadLinkActionV2.attach(
          threadId: request.threadCandidates.first.thread.id,
        ),
      ],
    );
  }
  if (request.atomCandidates.isNotEmpty) {
    final text = request.currentAtom.atom.statement;
    final title = text.contains('升学')
        ? '升学与去向选择'
        : text.contains('家庭')
        ? '家庭沟通与边界'
        : text.contains('努力')
        ? '努力与回报感'
        : '跑步与情绪恢复';
    return MemoryThreadLinkDecisionV2(
      actions: [
        MemoryThreadLinkActionV2.create(
          title: title,
          description: '关于$title的长期记录。',
          candidateAtomIds: [request.atomCandidates.first.atom.id],
        ),
      ],
    );
  }
  return const MemoryThreadLinkDecisionV2();
}

class _OneAtomExtractor implements MemoryExtractorV2 {
  const _OneAtomExtractor();

  @override
  Future<MemoryExtractionBatchV2> extract(DiaryRevisionV2 revision) async =>
      MemoryExtractionBatchV2(
        candidates: [
          MemoryExtractionCandidateV2(
            kind: 'event',
            statement: revision.body,
            sourceQuote: revision.body,
            sourceStart: 0,
            sourceEnd: revision.body.length,
            scope: 'state',
          ),
        ],
        extractorVersion: SelfEnginePipelineV2.extractorVersion,
        promptVersion: SelfEnginePipelineV2.promptVersion,
        modelIdentifier: 'fake:model',
      );
}

class _FakeThreadLinker implements MemoryThreadLinkerV2 {
  _FakeThreadLinker(this.handler);

  Future<MemoryThreadLinkDecisionV2> Function(MemoryThreadLinkRequestV2)
  handler;
  int calls = 0;

  @override
  Future<MemoryThreadLinkDecisionV2> link(MemoryThreadLinkRequestV2 request) {
    calls++;
    return handler(request);
  }
}

class _Availability implements SelfEngineAvailabilityV2 {
  const _Availability(this.value);

  final bool value;

  @override
  Future<bool> canProcess() async => value;
}

class _BlockingRunner implements SelfEngineRunnerV2 {
  final started = Completer<void>();
  final release = Completer<void>();
  int calls = 0;
  int _active = 0;
  int maxActive = 0;

  @override
  Future<SelfEngineRunResultV2> runOnce() async {
    calls++;
    _active++;
    if (_active > maxActive) maxActive = _active;
    if (calls == 1) {
      started.complete();
      await release.future;
    }
    _active--;
    return SelfEngineRunResultV2.completed;
  }
}

class _CountingRunner implements SelfEngineRunnerV2 {
  int calls = 0;

  @override
  Future<SelfEngineRunResultV2> runOnce() async {
    calls++;
    return SelfEngineRunResultV2.completed;
  }
}

DiaryEntryV2 _entry({
  required String id,
  required String body,
  required DateTime date,
  DateTime? updatedAt,
}) => DiaryEntryV2(
  id: id,
  body: body,
  entryDate: date,
  createdAt: date,
  updatedAt: updatedAt ?? date,
);

Future<void> _insertAtom(
  Database database, {
  required String revisionId,
  required String id,
  required String text,
  required int generation,
  required String observedAt,
}) => database.insert('memory_atoms', {
  'id': id,
  'revision_id': revisionId,
  'kind': 'event',
  'statement': text,
  'source_quote': text,
  'source_start': 0,
  'source_end': text.length,
  'observed_at': observedAt,
  'scope': 'state',
  'pipeline_version': 1,
  'generation': generation,
  'created_at': observedAt,
});

ThreadAtomEvidenceV2 _evidence(String id, String statement, String quote) =>
    ThreadAtomEvidenceV2(
      atom: MemoryAtomV2(
        id: id,
        revisionId: 'revision-$id',
        kind: MemoryAtomKindV2.event,
        statement: statement,
        sourceQuote: quote,
        scope: MemoryAtomScopeV2.state,
        pipelineVersion: 1,
        generation: 1,
        createdAt: DateTime.utc(2026),
        observedAt: DateTime.utc(2026),
      ),
      diaryId: 'diary-$id',
      entryDate: DateTime.utc(2026),
    );

class _SecretStore implements AiSecretStoreV2 {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
