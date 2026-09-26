import 'dart:async';

import '../domain/entities/memory_thread_link_v2.dart';
import '../domain/entities/memory_thread_v2.dart';
import '../domain/entities/self_engine_job_v2.dart';
import '../domain/entities/thread_link_job_v2.dart';
import '../domain/repositories/self_engine_repository_v2.dart';
import 'memory_atom_job_processor_v2.dart';
import 'ports/memory_thread_candidate_retriever_v2.dart';
import 'ports/memory_thread_linker_v2.dart';

class MemoryThreadLinkJobProcessorV2 {
  MemoryThreadLinkJobProcessorV2({
    required SelfEngineRepositoryV2 repository,
    required MemoryThreadCandidateRetrieverV2 candidateRetriever,
    required MemoryThreadLinkerV2 linker,
    DateTime Function()? clock,
    this.leaseDuration = const Duration(minutes: 5),
    this.heartbeatInterval = const Duration(minutes: 1),
    this.maxActiveAtomsPerRevision = 6,
  }) : _repository = repository,
       _candidateRetriever = candidateRetriever,
       _linker = linker,
       _clock = clock ?? DateTime.now;

  final SelfEngineRepositoryV2 _repository;
  final MemoryThreadCandidateRetrieverV2 _candidateRetriever;
  final MemoryThreadLinkerV2 _linker;
  final DateTime Function() _clock;
  final Duration leaseDuration;
  final Duration heartbeatInterval;
  final int maxActiveAtomsPerRevision;

  Future<void> process(ThreadLinkJobV2 job) async {
    final leaseId = job.leaseId;
    if (job.status != SelfEngineJobStatusV2.processing || leaseId == null) {
      throw const SelfEngineOwnershipLostV2();
    }
    var ownershipLost = false;
    final stopHeartbeat = Completer<void>();
    final heartbeat = _heartbeat(
      job,
      leaseId,
      stopHeartbeat.future,
      () => ownershipLost = true,
    );
    try {
      final atoms = await _candidateRetriever.activeAtomsForRevision(
        job.revisionId,
      );
      if (atoms.length > maxActiveAtomsPerRevision) {
        throw MemoryThreadLinkValidationFailureV2(
          'Revision has ${atoms.length} active Atoms; maximum is '
          '$maxActiveAtomsPerRevision.',
        );
      }
      final operations = <ThreadLinkOperationV2>[];
      final graph = _ProvisionalThreadGraphV2();
      for (var atomIndex = 0; atomIndex < atoms.length; atomIndex++) {
        final retrieved = await _candidateRetriever.retrieve(
          atoms[atomIndex].atom.id,
        );
        if (retrieved == null) continue;
        final request = graph.apply(retrieved);
        if (request.threadCandidates.isEmpty &&
            request.atomCandidates.isEmpty) {
          continue;
        }
        final decision = await _linker.link(request);
        final resolved = _validateAndResolve(
          job,
          request,
          decision,
          atomIndex: atomIndex,
        );
        operations.addAll(resolved);
        graph.accept(request, resolved, acceptedAt: _clock().toUtc());
      }
      if (ownershipLost) throw const SelfEngineOwnershipLostV2();
      final published = await _repository.publishThreadLinks(
        job.id,
        leaseId: leaseId,
        publishedAt: _clock().toUtc(),
        operations: operations,
      );
      if (!published) throw const SelfEngineOwnershipLostV2();
    } finally {
      if (!stopHeartbeat.isCompleted) stopHeartbeat.complete();
      await heartbeat;
    }
  }

  List<ThreadLinkOperationV2> _validateAndResolve(
    ThreadLinkJobV2 job,
    MemoryThreadLinkRequestV2 request,
    MemoryThreadLinkDecisionV2 decision, {
    required int atomIndex,
  }) {
    if (decision.actions.length > 2) {
      throw const MemoryThreadLinkValidationFailureV2(
        'An Atom can receive at most two automatic Thread memberships.',
      );
    }
    final allowedThreads = {
      for (final candidate in request.threadCandidates)
        candidate.thread.id: candidate,
    };
    final allowedAtoms = {
      for (final candidate in request.atomCandidates)
        candidate.atom.id: candidate,
    };
    final identities = <String>{};
    final consumedCandidateIds = <String>{};
    final resolved = <ThreadLinkOperationV2>[];
    for (
      var actionIndex = 0;
      actionIndex < decision.actions.length;
      actionIndex++
    ) {
      final action = decision.actions[actionIndex];
      if (action.type == MemoryThreadLinkActionTypeV2.attach) {
        final threadId = action.threadId;
        if (threadId == null || !allowedThreads.containsKey(threadId)) {
          throw const MemoryThreadLinkValidationFailureV2(
            'Attach references a Thread outside the candidate set.',
          );
        }
        if (!identities.add('attach:$threadId')) {
          throw const MemoryThreadLinkValidationFailureV2(
            'Duplicate Thread action.',
          );
        }
        resolved.add(
          ThreadLinkOperationV2.attach(
            currentAtomId: request.currentAtom.atom.id,
            threadId: threadId,
          ),
        );
        continue;
      }
      final candidateIds = action.candidateAtomIds;
      if (candidateIds.isEmpty ||
          candidateIds.toSet().length != candidateIds.length) {
        throw const MemoryThreadLinkValidationFailureV2(
          'Create requires distinct candidate Atoms.',
        );
      }
      for (final atomId in candidateIds) {
        final candidate = allowedAtoms[atomId];
        if (candidate == null ||
            candidate.diaryId == request.currentAtom.diaryId) {
          throw const MemoryThreadLinkValidationFailureV2(
            'Create references an Atom outside the candidate set.',
          );
        }
        if (!consumedCandidateIds.add(atomId)) {
          throw const MemoryThreadLinkValidationFailureV2(
            'A candidate Atom cannot seed multiple Threads in one decision.',
          );
        }
      }
      final title = action.title?.trim() ?? '';
      final description = action.description?.trim() ?? '';
      if (title.isEmpty || description.isEmpty) {
        throw const MemoryThreadLinkValidationFailureV2(
          'Create requires a title and description.',
        );
      }
      final threadId = 'thread-${job.id}-${atomIndex + 1}-${actionIndex + 1}';
      if (!identities.add('create:$threadId')) {
        throw const MemoryThreadLinkValidationFailureV2(
          'Duplicate Thread action.',
        );
      }
      resolved.add(
        ThreadLinkOperationV2.create(
          currentAtomId: request.currentAtom.atom.id,
          threadId: threadId,
          title: title,
          description: description,
          candidateAtomIds: List.unmodifiable(candidateIds),
          derivationAtomIds: List.unmodifiable({
            request.currentAtom.atom.id,
            ...request.atomCandidates.map((item) => item.atom.id),
            ...request.threadCandidates.expand(
              (thread) => <String>{
                ...thread.derivationAtomIds,
                ...thread.representativeAtoms.map((item) => item.atom.id),
              },
            ),
          }),
        ),
      );
    }
    return resolved;
  }

  Future<void> _heartbeat(
    ThreadLinkJobV2 job,
    String leaseId,
    Future<void> stop,
    void Function() onOwnershipLost,
  ) async {
    while (true) {
      final stopped = await Future.any<bool>([
        Future<void>.delayed(heartbeatInterval).then((_) => false),
        stop.then((_) => true),
      ]);
      if (stopped) return;
      final renewed = await _repository.renewThreadLinkLease(
        job.id,
        leaseId: leaseId,
        now: _clock().toUtc(),
        leaseDuration: leaseDuration,
      );
      if (!renewed) {
        onOwnershipLost();
        return;
      }
    }
  }
}

/// An in-memory overlay for one revision-level job. Nothing is durable until
/// the final repository transaction succeeds, but each later Atom observes all
/// accepted Thread and membership decisions made for earlier Atoms.
class _ProvisionalThreadGraphV2 {
  static const int _maxRequestThreadCandidates = 18;
  static const int _maxRepresentativeAtoms = 3;

  final Map<String, MemoryThreadCandidateV2> _threads = {};
  final Set<String> _consumedCandidateAtomIds = {};

  MemoryThreadLinkRequestV2 apply(MemoryThreadLinkRequestV2 persisted) {
    final candidatesById = <String, MemoryThreadCandidateV2>{
      for (final candidate in persisted.threadCandidates)
        candidate.thread.id: _threads[candidate.thread.id] ?? candidate,
      ..._threads,
    };
    if (candidatesById.length > _maxRequestThreadCandidates) {
      throw const MemoryThreadLinkValidationFailureV2(
        'Intra-revision Thread candidate bound was exceeded.',
      );
    }
    return MemoryThreadLinkRequestV2(
      currentAtom: persisted.currentAtom,
      threadCandidates: List.unmodifiable(candidatesById.values),
      atomCandidates: List.unmodifiable(
        persisted.atomCandidates.where(
          (candidate) => !_consumedCandidateAtomIds.contains(candidate.atom.id),
        ),
      ),
    );
  }

  void accept(
    MemoryThreadLinkRequestV2 request,
    List<ThreadLinkOperationV2> operations, {
    required DateTime acceptedAt,
  }) {
    final evidenceById = <String, ThreadAtomEvidenceV2>{
      request.currentAtom.atom.id: request.currentAtom,
      for (final candidate in request.atomCandidates)
        candidate.atom.id: candidate,
    };
    final candidatesById = {
      for (final candidate in request.threadCandidates)
        candidate.thread.id: candidate,
    };
    for (final operation in operations) {
      if (operation.type == MemoryThreadLinkActionTypeV2.attach) {
        final target = candidatesById[operation.threadId]!;
        _threads[operation.threadId] = _withEvidence(target, [
          request.currentAtom,
        ], acceptedAt);
        continue;
      }

      final members = <ThreadAtomEvidenceV2>[
        request.currentAtom,
        for (final atomId in operation.candidateAtomIds) evidenceById[atomId]!,
      ];
      _consumedCandidateAtomIds.addAll(operation.candidateAtomIds);
      final observed = members.map(_observedAt).toList(growable: false)..sort();
      final thread = MemoryThreadV2(
        id: operation.threadId,
        title: operation.title!,
        description: operation.description!,
        status: MemoryThreadStatusV2.active,
        firstSeen: observed.first,
        lastSeen: observed.last,
        pipelineVersion: request.currentAtom.atom.pipelineVersion,
        generation: request.currentAtom.atom.generation,
        createdAt: acceptedAt,
        updatedAt: acceptedAt,
      );
      _threads[thread.id] = MemoryThreadCandidateV2(
        thread: thread,
        representativeAtoms: _representatives(members),
        derivationAtomIds: List.unmodifiable(operation.derivationAtomIds),
      );
    }
  }

  MemoryThreadCandidateV2 _withEvidence(
    MemoryThreadCandidateV2 candidate,
    List<ThreadAtomEvidenceV2> added,
    DateTime acceptedAt,
  ) {
    final evidence = <String, ThreadAtomEvidenceV2>{
      for (final item in candidate.representativeAtoms) item.atom.id: item,
      for (final item in added) item.atom.id: item,
    }.values.toList(growable: false);
    final observed = added.map(_observedAt).toList(growable: false)..sort();
    final original = candidate.thread;
    final firstSeen = observed.first.isBefore(original.firstSeen)
        ? observed.first
        : original.firstSeen;
    final lastSeen = observed.last.isAfter(original.lastSeen)
        ? observed.last
        : original.lastSeen;
    return MemoryThreadCandidateV2(
      thread: MemoryThreadV2(
        id: original.id,
        title: original.title,
        description: original.description,
        status: original.status,
        firstSeen: firstSeen,
        lastSeen: lastSeen,
        mergedIntoId: original.mergedIntoId,
        pipelineVersion: original.pipelineVersion,
        generation: original.generation,
        createdAt: original.createdAt,
        updatedAt: acceptedAt,
      ),
      representativeAtoms: _representatives(evidence),
      derivationAtomIds: candidate.derivationAtomIds,
    );
  }

  List<ThreadAtomEvidenceV2> _representatives(
    Iterable<ThreadAtomEvidenceV2> evidence,
  ) {
    final sorted = evidence.toList(growable: false)
      ..sort((left, right) {
        final byDate = _observedAt(right).compareTo(_observedAt(left));
        if (byDate != 0) return byDate;
        return left.atom.id.compareTo(right.atom.id);
      });
    return List.unmodifiable(sorted.take(_maxRepresentativeAtoms));
  }

  static DateTime _observedAt(ThreadAtomEvidenceV2 evidence) =>
      evidence.atom.observedAt ?? evidence.entryDate;
}
