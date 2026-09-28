import 'self_engine_job_v2.dart';

class ThesisJobV2 {
  const ThesisJobV2({
    required this.id,
    required this.threadId,
    required this.triggerRevisionId,
    required this.origin,
    required this.status,
    required this.attemptCount,
    required this.pipelineVersion,
    required this.generation,
    required this.createdAt,
    required this.updatedAt,
    this.nextRetryAt,
    this.error,
    this.leaseId,
    this.leaseExpiresAt,
  });

  final String id;
  final String threadId;
  final String triggerRevisionId;
  final SelfEngineJobOriginV2 origin;
  final SelfEngineJobStatusV2 status;
  final int attemptCount;
  final int pipelineVersion;
  final int generation;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? nextRetryAt;
  final String? error;
  final String? leaseId;
  final DateTime? leaseExpiresAt;
}
