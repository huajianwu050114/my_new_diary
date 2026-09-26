import 'dart:async';

import '../domain/entities/memory_atom_v2.dart';
import '../domain/entities/self_engine_derived_result_v2.dart';
import '../domain/entities/self_engine_job_v2.dart';
import '../domain/entities/source_computation_v2.dart';
import '../domain/repositories/self_engine_repository_v2.dart';
import 'memory_atom_validator_v2.dart';
import 'ports/memory_extractor_v2.dart';
import 'ports/self_engine_processor_v2.dart';

class MemoryAtomJobProcessorV2 implements SelfEngineProcessorV2 {
  MemoryAtomJobProcessorV2({
    required SelfEngineRepositoryV2 repository,
    required MemoryExtractorV2 extractor,
    MemoryAtomValidatorV2 validator = const MemoryAtomValidatorV2(),
    DateTime Function()? clock,
    this.leaseDuration = const Duration(minutes: 5),
    this.heartbeatInterval = const Duration(minutes: 1),
  }) : _repository = repository,
       _extractor = extractor,
       _validator = validator,
       _clock = clock ?? DateTime.now;

  final SelfEngineRepositoryV2 _repository;
  final MemoryExtractorV2 _extractor;
  final MemoryAtomValidatorV2 _validator;
  final DateTime Function() _clock;
  final Duration leaseDuration;
  final Duration heartbeatInterval;

  @override
  Future<void> process(SelfEngineJobV2 job) async {
    final leaseId = job.leaseId;
    if (job.status != SelfEngineJobStatusV2.processing || leaseId == null) {
      throw const SelfEngineOwnershipLostV2();
    }
    final revision = await _repository.getRevisionById(job.revisionId);
    if (revision == null ||
        revision.sourceHash != job.sourceHash ||
        revision.fingerprintVersion != job.fingerprintVersion) {
      throw StateError('Job ${job.id} has no matching revision.');
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
      final cached = await _repository.getComputationResult(job.computationId);
      late final List<MemoryAtomDraftV2> drafts;
      SourceComputationResultV2? newComputationResult;
      if (cached != null) {
        drafts = _validator.validateCached(revision, cached.atoms);
      } else {
        final batch = await _extractor.extract(revision);
        drafts = _validator.validate(revision, batch);
        newComputationResult = SourceComputationResultV2(
          computationId: job.computationId,
          atoms: drafts,
          extractorVersion: batch.extractorVersion,
          promptVersion: batch.promptVersion,
          modelIdentifier: batch.modelIdentifier,
          createdAt: _clock().toUtc(),
        );
      }
      if (ownershipLost) throw const SelfEngineOwnershipLostV2();

      final publishedAt = _clock().toUtc();
      final atoms = <MemoryAtomV2>[
        for (var index = 0; index < drafts.length; index++)
          MemoryAtomV2(
            id: '${revision.id}-atom-${index + 1}',
            revisionId: revision.id,
            kind: drafts[index].kind,
            statement: drafts[index].statement,
            sourceQuote: drafts[index].sourceQuote,
            sourceStart: drafts[index].sourceStart,
            sourceEnd: drafts[index].sourceEnd,
            observedAt: revision.entryDate,
            scope: drafts[index].scope,
            pipelineVersion: job.pipelineVersion,
            generation: job.generation,
            createdAt: publishedAt,
          ),
      ];
      final published = await _repository.publishResult(
        job.id,
        leaseId: leaseId,
        publishedAt: publishedAt,
        result: SelfEngineDerivedResultV2(
          atoms: atoms,
          computationResult: newComputationResult,
        ),
      );
      if (!published) throw const SelfEngineOwnershipLostV2();
    } finally {
      if (!stopHeartbeat.isCompleted) stopHeartbeat.complete();
      await heartbeat;
    }
  }

  Future<void> _heartbeat(
    SelfEngineJobV2 job,
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
      final renewed = await _repository.renewLease(
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

class SelfEngineOwnershipLostV2 implements Exception {
  const SelfEngineOwnershipLostV2();
}
