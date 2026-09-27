import '../entities/self_read_model_v2.dart';

abstract interface class SelfReadRepositoryV2 {
  Future<List<SelfThreadSummaryV2>> getActiveThreads();

  Future<SelfThreadDetailV2?> getThreadDetail(String threadId);

  Future<SelfEngineReadStateV2> getSelfEngineState();
}
