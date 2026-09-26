import '../domain/repositories/self_engine_repository_v2.dart';

class SelfEngineJobRecoveryV2 {
  const SelfEngineJobRecoveryV2(this._repository);

  final SelfEngineRepositoryV2 _repository;

  Future<int> afterColdStart({DateTime? now}) =>
      _repository.recoverExpiredLeases(now: (now ?? DateTime.now()).toUtc());

  Future<int> afterResume({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    return _repository.recoverExpiredLeases(now: current);
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
}
