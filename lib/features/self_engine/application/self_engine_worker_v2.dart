import '../domain/entities/self_engine_job_v2.dart';
import '../domain/repositories/self_engine_repository_v2.dart';
import 'memory_atom_job_processor_v2.dart';
import 'ports/self_engine_availability_v2.dart';
import 'ports/self_engine_processor_v2.dart';
import 'ports/self_engine_runner_v2.dart';

class SelfEngineWorkerV2 implements SelfEngineRunnerV2 {
  SelfEngineWorkerV2({
    required SelfEngineRepositoryV2 repository,
    required SelfEngineProcessorV2 processor,
    required SelfEngineAvailabilityV2 availability,
    DateTime Function()? clock,
    this.leaseDuration = const Duration(minutes: 5),
  }) : _repository = repository,
       _processor = processor,
       _availability = availability,
       _clock = clock ?? DateTime.now;

  final SelfEngineRepositoryV2 _repository;
  final SelfEngineProcessorV2 _processor;
  final SelfEngineAvailabilityV2 _availability;
  final DateTime Function() _clock;
  final Duration leaseDuration;
  Future<SelfEngineRunResultV2>? _activeRun;

  @override
  Future<SelfEngineRunResultV2> runOnce() {
    final active = _activeRun;
    if (active != null) return active;
    late final Future<SelfEngineRunResultV2> run;
    run = _runOnce().whenComplete(() {
      if (identical(_activeRun, run)) _activeRun = null;
    });
    _activeRun = run;
    return run;
  }

  Future<SelfEngineRunResultV2> _runOnce() async {
    if (!await _availability.canProcess()) {
      return SelfEngineRunResultV2.unavailable;
    }
    final job = await _repository.claimNextJob(
      now: _clock().toUtc(),
      leaseDuration: leaseDuration,
    );
    if (job == null) return SelfEngineRunResultV2.noWork;
    try {
      await _processor.process(job);
      return SelfEngineRunResultV2.completed;
    } on SelfEngineOwnershipLostV2 {
      return SelfEngineRunResultV2.ownershipLost;
    } catch (error) {
      final failed = await _repository.markJobFailed(
        job.id,
        leaseId: job.leaseId!,
        failedAt: _clock().toUtc(),
        error: error.toString(),
      );
      if (!failed) return SelfEngineRunResultV2.ownershipLost;
      final current = (await _repository.getJobs()).firstWhere(
        (value) => value.id == job.id,
      );
      return current.status == SelfEngineJobStatusV2.failed
          ? SelfEngineRunResultV2.terminalFailure
          : SelfEngineRunResultV2.retryScheduled;
    }
  }
}
