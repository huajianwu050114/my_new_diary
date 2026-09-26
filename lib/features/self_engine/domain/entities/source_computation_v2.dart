import 'memory_atom_v2.dart';

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

class SourceComputationResultV2 {
  const SourceComputationResultV2({
    required this.computationId,
    required this.atoms,
    required this.extractorVersion,
    required this.promptVersion,
    required this.modelIdentifier,
    required this.createdAt,
  });

  final String computationId;
  final List<MemoryAtomDraftV2> atoms;
  final int extractorVersion;
  final int promptVersion;
  final String modelIdentifier;
  final DateTime createdAt;
}
