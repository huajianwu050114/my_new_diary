class SourceComputationV2 {
  const SourceComputationV2({
    required this.id,
    required this.sourceHash,
    required this.fingerprintVersion,
    required this.pipelineVersion,
    required this.jobType,
    required this.createdAt,
  });

  final String id;
  final String sourceHash;
  final int fingerprintVersion;
  final int pipelineVersion;
  final String jobType;
  final DateTime createdAt;
}
