import '../../domain/entities/self_engine_job_v2.dart';

/// Phase A boundary only. No implementation invokes AI yet.
abstract interface class SelfEngineProcessorV2 {
  Future<void> process(SelfEngineJobV2 job);
}
