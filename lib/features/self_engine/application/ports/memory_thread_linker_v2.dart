import '../../domain/entities/memory_thread_link_v2.dart';

abstract interface class MemoryThreadLinkerV2 {
  Future<MemoryThreadLinkDecisionV2> link(MemoryThreadLinkRequestV2 request);
}

class MemoryThreadLinkFormatFailureV2 implements Exception {
  const MemoryThreadLinkFormatFailureV2(this.message);

  final String message;

  @override
  String toString() => 'MemoryThreadLinkFormatFailureV2: $message';
}

class MemoryThreadLinkValidationFailureV2 implements Exception {
  const MemoryThreadLinkValidationFailureV2(this.message);

  final String message;

  @override
  String toString() => 'MemoryThreadLinkValidationFailureV2: $message';
}
