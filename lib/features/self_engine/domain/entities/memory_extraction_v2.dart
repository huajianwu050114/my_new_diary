class MemoryExtractionCandidateV2 {
  const MemoryExtractionCandidateV2({
    required this.kind,
    required this.statement,
    required this.sourceQuote,
    required this.scope,
    this.sourceStart,
    this.sourceEnd,
  });

  final String kind;
  final String statement;
  final String sourceQuote;
  final int? sourceStart;
  final int? sourceEnd;
  final String scope;
}

class MemoryExtractionBatchV2 {
  const MemoryExtractionBatchV2({
    required this.candidates,
    required this.extractorVersion,
    required this.promptVersion,
    required this.modelIdentifier,
  });

  final List<MemoryExtractionCandidateV2> candidates;
  final int extractorVersion;
  final int promptVersion;
  final String modelIdentifier;
}

sealed class MemoryExtractionFailureV2 implements Exception {
  const MemoryExtractionFailureV2(this.message);

  final String message;

  @override
  String toString() => message;
}

class MemoryExtractionFormatFailureV2 extends MemoryExtractionFailureV2 {
  const MemoryExtractionFormatFailureV2(super.message);
}

class MemoryExtractionValidationFailureV2 extends MemoryExtractionFailureV2 {
  const MemoryExtractionValidationFailureV2(super.message);
}
