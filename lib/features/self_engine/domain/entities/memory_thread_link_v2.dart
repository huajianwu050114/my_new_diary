// ignore_for_file: prefer_initializing_formals

import 'memory_atom_v2.dart';
import 'memory_thread_v2.dart';

class ThreadAtomEvidenceV2 {
  const ThreadAtomEvidenceV2({
    required this.atom,
    required this.diaryId,
    required this.entryDate,
  });

  final MemoryAtomV2 atom;
  final String diaryId;
  final DateTime entryDate;
}

class MemoryThreadCandidateV2 {
  const MemoryThreadCandidateV2({
    required this.thread,
    required this.representativeAtoms,
  });

  final MemoryThreadV2 thread;
  final List<ThreadAtomEvidenceV2> representativeAtoms;
}

class MemoryThreadLinkRequestV2 {
  const MemoryThreadLinkRequestV2({
    required this.currentAtom,
    required this.threadCandidates,
    required this.atomCandidates,
  });

  final ThreadAtomEvidenceV2 currentAtom;
  final List<MemoryThreadCandidateV2> threadCandidates;
  final List<ThreadAtomEvidenceV2> atomCandidates;
}

enum MemoryThreadLinkActionTypeV2 { attach, create }

/// A semantic decision only. It is deliberately not reusable by source hash:
/// the answer depends on the current Thread and active-Atom graph.
class MemoryThreadLinkActionV2 {
  // The public parameters intentionally remain non-nullable although this
  // compact discriminated value stores fields for both action shapes.
  const MemoryThreadLinkActionV2.attach({required String threadId})
    : type = MemoryThreadLinkActionTypeV2.attach,
      threadId = threadId,
      title = null,
      description = null,
      candidateAtomIds = const [];

  const MemoryThreadLinkActionV2.create({
    required String title,
    required String description,
    required List<String> candidateAtomIds,
  }) : type = MemoryThreadLinkActionTypeV2.create,
       threadId = null,
       title = title,
       description = description,
       candidateAtomIds = candidateAtomIds;

  final MemoryThreadLinkActionTypeV2 type;
  final String? threadId;
  final String? title;
  final String? description;
  final List<String> candidateAtomIds;
}

class MemoryThreadLinkDecisionV2 {
  const MemoryThreadLinkDecisionV2({this.actions = const []});

  final List<MemoryThreadLinkActionV2> actions;
}

class ThreadLinkOperationV2 {
  const ThreadLinkOperationV2.attach({
    required this.currentAtomId,
    required String threadId,
  }) : type = MemoryThreadLinkActionTypeV2.attach,
       threadId = threadId,
       title = null,
       description = null,
       candidateAtomIds = const [],
       derivationAtomIds = const [];

  const ThreadLinkOperationV2.create({
    required this.currentAtomId,
    required String threadId,
    required String title,
    required String description,
    required List<String> candidateAtomIds,
    required List<String> derivationAtomIds,
  }) : type = MemoryThreadLinkActionTypeV2.create,
       threadId = threadId,
       title = title,
       description = description,
       candidateAtomIds = candidateAtomIds,
       derivationAtomIds = derivationAtomIds;

  final String currentAtomId;
  final MemoryThreadLinkActionTypeV2 type;
  final String threadId;
  final String? title;
  final String? description;
  final List<String> candidateAtomIds;
  final List<String> derivationAtomIds;
}
