import 'ports/self_engine_runner_v2.dart';
import 'self_engine_job_recovery_v2.dart';

class SelfEngineLifecycleMaintenanceV2 {
  const SelfEngineLifecycleMaintenanceV2({required this.recovery, this.runner});

  final SelfEngineJobRecoveryV2 recovery;
  final SelfEngineRunnerV2? runner;

  Future<int> afterResume() async {
    final recovered = await recovery.afterResume();
    await recovery.reconcileLegacyDiaries();
    await recovery.reconcileThreadLinkJobs();
    await runner?.runOnce();
    return recovered;
  }
}
