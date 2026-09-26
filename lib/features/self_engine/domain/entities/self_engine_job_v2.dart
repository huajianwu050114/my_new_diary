enum SelfEngineJobTypeV2 { sourceChanged }

enum SelfEngineJobStatusV2 { pending, processing, completed, retryable, failed }

enum SelfEngineJobOriginV2 { live, historical }

class SelfEngineJobV2 {
  const SelfEngineJobV2({
    required this.id,
    required this.diaryId,
    required this.revisionId,
    required this.computationId,
    required this.sourceHash,
    required this.fingerprintVersion,
    required this.type,
    required this.status,
    required this.origin,
    required this.attemptCount,
    required this.pipelineVersion,
    required this.createdAt,
    required this.updatedAt,
    required this.generation,
    this.nextRetryAt,
    this.error,
    this.leaseId,
    this.leaseExpiresAt,
  });

  final String id;
  final String diaryId;
  final String revisionId;
  final String computationId;
  final String sourceHash;
  final int fingerprintVersion;
  final SelfEngineJobTypeV2 type;
  final SelfEngineJobStatusV2 status;
  final SelfEngineJobOriginV2 origin;
  final int attemptCount;
  final int pipelineVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int generation;
  final DateTime? nextRetryAt;
  final String? error;
  final String? leaseId;
  final DateTime? leaseExpiresAt;
}
