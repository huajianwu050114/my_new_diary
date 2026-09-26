import '../../domain/entities/memory_thread_link_v2.dart';

abstract interface class MemoryThreadCandidateRetrieverV2 {
  Future<List<ThreadAtomEvidenceV2>> activeAtomsForRevision(String revisionId);

  Future<MemoryThreadLinkRequestV2?> retrieve(String atomId);
}
