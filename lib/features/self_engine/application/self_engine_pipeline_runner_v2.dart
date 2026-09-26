import 'ports/self_engine_runner_v2.dart';

/// Runs one bounded source-extraction opportunity and one bounded Thread-link
/// opportunity. It intentionally does not drain either durable queue.
class SelfEnginePipelineRunnerV2 implements SelfEngineRunnerV2 {
  SelfEnginePipelineRunnerV2({
    required SelfEngineRunnerV2 extractionRunner,
    required SelfEngineRunnerV2 threadLinkRunner,
  }) : _extractionRunner = extractionRunner,
       _threadLinkRunner = threadLinkRunner;

  final SelfEngineRunnerV2 _extractionRunner;
  final SelfEngineRunnerV2 _threadLinkRunner;
  Future<SelfEngineRunResultV2>? _activeRun;
  bool _rerunRequested = false;

  @override
  Future<SelfEngineRunResultV2> runOnce() {
    final active = _activeRun;
    if (active != null) {
      _rerunRequested = true;
      return active;
    }
    late final Future<SelfEngineRunResultV2> run;
    run = _runCoalesced().whenComplete(() {
      if (identical(_activeRun, run)) _activeRun = null;
    });
    _activeRun = run;
    return run;
  }

  Future<SelfEngineRunResultV2> _runCoalesced() async {
    late SelfEngineRunResultV2 result;
    do {
      _rerunRequested = false;
      result = await _runBounded();
    } while (_rerunRequested);
    return result;
  }

  Future<SelfEngineRunResultV2> _runBounded() async {
    final extraction = await _extractionRunner.runOnce();
    final linking = await _threadLinkRunner.runOnce();
    if (linking != SelfEngineRunResultV2.noWork &&
        linking != SelfEngineRunResultV2.unavailable) {
      return linking;
    }
    return extraction == SelfEngineRunResultV2.noWork ? linking : extraction;
  }
}
