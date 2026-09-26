import 'dart:async';

import '../domain/entities/memory_thread_link_v2.dart';
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
      final operations = <ThreadLinkOperationV2>[];
      for (var atomIndex = 0; atomIndex < atoms.length; atomIndex++) {
        final request = await _candidateRetriever.retrieve(
          atoms[atomIndex].atom.id,
        );
        if (request == null) continue;
        if (request.threadCandidates.isEmpty &&
            request.atomCandidates.isEmpty) {
          continue;
        }
        final decision = await _linker.link(request);
        operations.addAll(
          _validateAndResolve(job, request, decision, atomIndex: atomIndex),
        );
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
              (thread) =>
                  thread.representativeAtoms.map((item) => item.atom.id),
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
