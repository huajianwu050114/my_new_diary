import '../entities/diary_revision_v2.dart';
import '../entities/self_engine_derived_result_v2.dart';
import '../entities/self_engine_job_v2.dart';
import '../entities/memory_atom_v2.dart';
import '../entities/source_computation_v2.dart';

abstract interface class SelfEngineRepositoryV2 {
  Future<DiaryRevisionV2?> getLatestRevision(String diaryId);

  Future<DiaryRevisionV2?> getRevisionById(String revisionId);

  Future<List<DiaryRevisionV2>> getAllRevisions();

  Future<List<DiaryRevisionV2>> getRevisionsForDiary(String diaryId);

  Future<void> restoreRevision(DiaryRevisionV2 revision);

  Future<void> restoreRevisionsForDiary(
    String diaryId,
    List<DiaryRevisionV2> revisions,
  );

  Future<List<SelfEngineJobV2>> getJobs({SelfEngineJobStatusV2? status});

  Future<SourceComputationResultV2?> getComputationResult(String computationId);

  Future<List<MemoryAtomV2>> getAtomsForRevision(String revisionId);

  Future<SelfEngineJobV2?> claimNextJob({
    required DateTime now,
    SelfEngineJobOriginV2 origin = SelfEngineJobOriginV2.live,
    Duration leaseDuration = const Duration(minutes: 5),
  });

  Future<bool> renewLease(
    String id, {
    required String leaseId,
    required DateTime now,
    Duration leaseDuration = const Duration(minutes: 5),
  });

  Future<bool> publishResult(
    String jobId, {
    required String leaseId,
    required DateTime publishedAt,
    required SelfEngineDerivedResultV2 result,
  });

  Future<bool> markJobFailed(
    String id, {
    required String leaseId,
    required DateTime failedAt,
    required String error,
  });

  Future<int> recoverExpiredLeases({required DateTime now});

  Future<void> clearAllDerivedDataForGlobalRebuild();

  Future<void> rebuildDerivedDataForDiary(String diaryId);

  Future<int> backfillMissingRevisions({int limit = 50});
}
