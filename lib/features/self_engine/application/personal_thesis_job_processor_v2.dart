import 'dart:async';

import '../domain/entities/personal_thesis_synthesis_v2.dart';
import '../domain/entities/personal_thesis_v2.dart';
import '../domain/entities/self_engine_job_v2.dart';
import '../domain/entities/thesis_job_v2.dart';
import '../domain/repositories/self_engine_repository_v2.dart';
import 'memory_atom_job_processor_v2.dart';
import 'ports/personal_thesis_candidate_retriever_v2.dart';
import 'ports/personal_thesis_synthesizer_v2.dart';

class PersonalThesisJobProcessorV2 {
  PersonalThesisJobProcessorV2({
    required SelfEngineRepositoryV2 repository,
    required PersonalThesisCandidateRetrieverV2 candidateRetriever,
    required PersonalThesisSynthesizerV2 synthesizer,
    DateTime Function()? clock,
    this.leaseDuration = const Duration(minutes: 5),
    this.heartbeatInterval = const Duration(minutes: 1),
  }) : _repository = repository,
       _candidateRetriever = candidateRetriever,
       _synthesizer = synthesizer,
       _clock = clock ?? DateTime.now;

  final SelfEngineRepositoryV2 _repository;
  final PersonalThesisCandidateRetrieverV2 _candidateRetriever;
  final PersonalThesisSynthesizerV2 _synthesizer;
  final DateTime Function() _clock;
  final Duration leaseDuration;
  final Duration heartbeatInterval;

  Future<void> process(ThesisJobV2 job) async {
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
      final request = await _candidateRetriever.retrieve(job.threadId);
      if (request == null) {
        if (ownershipLost) throw const SelfEngineOwnershipLostV2();
        final published = await _repository.publishThesis(
          job.id,
          leaseId: leaseId,
          publishedAt: _clock().toUtc(),
          result: const PersonalThesisPublishV2.none(),
        );
        if (!published) throw const SelfEngineOwnershipLostV2();
        return;
      }
      if (request.supportCandidates.length > 12 ||
          request.counterCandidates.length > 16) {
        throw const PersonalThesisValidationFailureV2(
          'Thesis candidate bounds were exceeded.',
        );
      }
      final decision = await _synthesizer.synthesize(request);
      final result = _validateAndResolve(request, decision);
      if (ownershipLost) throw const SelfEngineOwnershipLostV2();
      final published = await _repository.publishThesis(
        job.id,
        leaseId: leaseId,
        publishedAt: _clock().toUtc(),
        result: result,
      );
      if (!published) throw const SelfEngineOwnershipLostV2();
    } finally {
      if (!stopHeartbeat.isCompleted) stopHeartbeat.complete();
      await heartbeat;
    }
  }

  PersonalThesisPublishV2 _validateAndResolve(
    PersonalThesisSynthesisRequestV2 request,
    PersonalThesisSynthesisDecisionV2 decision,
  ) {
    if (decision.action == PersonalThesisSynthesisActionV2.none) {
      if (decision.statement != null ||
          decision.rationale != null ||
          decision.maturity != null ||
          decision.supportAtomIds.isNotEmpty ||
          decision.counterAtomIds.isNotEmpty) {
        throw const PersonalThesisValidationFailureV2(
          'None decision contains unexpected data.',
        );
      }
      return const PersonalThesisPublishV2.none();
    }
    final supportById = {
      for (final item in request.supportCandidates) item.atom.id: item,
    };
    final counterById = {
      for (final item in request.counterCandidates) item.atom.id: item,
    };
    final supportIds = decision.supportAtomIds;
    final counterIds = decision.counterAtomIds;
    if (decision.maturity != PersonalThesisMaturityV2.candidate ||
        supportIds.length < 2 ||
        supportIds.toSet().length != supportIds.length ||
        counterIds.toSet().length != counterIds.length ||
        supportIds.toSet().intersection(counterIds.toSet()).isNotEmpty ||
        supportIds.any((id) => !supportById.containsKey(id)) ||
        counterIds.any((id) => !counterById.containsKey(id)) ||
        supportIds.map((id) => supportById[id]!.diaryId).toSet().length < 2) {
      throw const PersonalThesisValidationFailureV2(
        'Thesis evidence selection is invalid.',
      );
    }
    _validateWording(
      decision.statement?.trim() ?? '',
      decision.rationale?.trim() ?? '',
    );
    return PersonalThesisPublishV2.create(
      decision: PersonalThesisSynthesisDecisionV2.create(
        statement: decision.statement!.trim(),
        rationale: decision.rationale!.trim(),
        maturity: PersonalThesisMaturityV2.candidate,
        supportAtomIds: List.unmodifiable(supportIds),
        counterAtomIds: List.unmodifiable(counterIds),
      ),
      derivationAtomIds: List.unmodifiable({
        ...request.threadDerivationAtomIds,
        ...request.supportCandidates.map((item) => item.atom.id),
        ...request.counterCandidates.map((item) => item.atom.id),
      }),
    );
  }

  void _validateWording(String statement, String rationale) {
    const forbidden = [
      '你',
      '本质',
      '天生',
      '永远',
      '注定',
      '人格障碍',
      '抑郁症',
      '焦虑症',
      '我是一个',
      '我是那种',
    ];
    if (statement.isEmpty ||
        statement.length > 240 ||
        rationale.isEmpty ||
        rationale.length > 300 ||
        !statement.contains('我') ||
        forbidden.any(
          (term) => statement.contains(term) || rationale.contains(term),
        )) {
      throw const PersonalThesisValidationFailureV2(
        'Thesis wording is not tentative and bounded.',
      );
    }
  }

  Future<void> _heartbeat(
    ThesisJobV2 job,
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
      final renewed = await _repository.renewThesisLease(
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
