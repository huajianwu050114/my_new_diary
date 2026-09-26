import '../../domain/entities/self_engine_job_v2.dart';

/// Processes one already-claimed job while its lease remains valid.
abstract interface class SelfEngineProcessorV2 {
  Future<void> process(SelfEngineJobV2 job);
}
