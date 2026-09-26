import '../domain/repositories/self_engine_repository_v2.dart';

class SelfEngineJobRecoveryV2 {
  const SelfEngineJobRecoveryV2(this._repository);

  final SelfEngineRepositoryV2 _repository;

  Future<int> afterColdStart({DateTime? now}) async {
    final current = (now ?? DateTime.now()).toUtc();
    return await _repository.recoverExpiredLeases(now: current) +
        await _repository.recoverExpiredThreadLinkLeases(now: current);
  }

  Future<int> afterResume({DateTime? now}) async {
    final current = (now ?? DateTime.now()).toUtc();
    return await _repository.recoverExpiredLeases(now: current) +
        await _repository.recoverExpiredThreadLinkLeases(now: current);
  }

  Future<int> reconcileLegacyDiaries({int limit = 50}) async {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    var total = 0;
    while (true) {
      final count = await _repository.backfillMissingRevisions(limit: limit);
      total += count;
      if (count < limit) return total;
      // Each batch commits independently. Yield between batches so a large
      // legacy database is resumable and does not monopolize the event loop.
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<int> reconcileThreadLinkJobs({int limit = 50}) async {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    var total = 0;
    while (true) {
      final count = await _repository.backfillMissingThreadLinkJobs(
        limit: limit,
      );
      total += count;
      if (count < limit) return total;
      await Future<void>.delayed(Duration.zero);
    }
  }
}
