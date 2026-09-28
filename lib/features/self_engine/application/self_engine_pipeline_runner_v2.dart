import 'ports/self_engine_runner_v2.dart';

/// Runs one bounded source-extraction opportunity and one bounded Thread-link
/// opportunity. It intentionally does not drain either durable queue.
class SelfEnginePipelineRunnerV2 implements SelfEngineRunnerV2 {
  SelfEnginePipelineRunnerV2({
    required SelfEngineRunnerV2 extractionRunner,
    required SelfEngineRunnerV2 threadLinkRunner,
    SelfEngineRunnerV2? thesisRunner,
  }) : _extractionRunner = extractionRunner,
       _threadLinkRunner = threadLinkRunner,
       _thesisRunner = thesisRunner ?? const _NoWorkRunnerV2();

  final SelfEngineRunnerV2 _extractionRunner;
  final SelfEngineRunnerV2 _threadLinkRunner;
  final SelfEngineRunnerV2 _thesisRunner;
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
    final thesis = await _thesisRunner.runOnce();
    for (final result in [thesis, linking, extraction]) {
      if (result != SelfEngineRunResultV2.noWork &&
          result != SelfEngineRunResultV2.unavailable) {
        return result;
      }
    }
    if (thesis == SelfEngineRunResultV2.unavailable ||
        linking == SelfEngineRunResultV2.unavailable ||
        extraction == SelfEngineRunResultV2.unavailable) {
      return SelfEngineRunResultV2.unavailable;
    }
    return SelfEngineRunResultV2.noWork;
  }
}

class _NoWorkRunnerV2 implements SelfEngineRunnerV2 {
  const _NoWorkRunnerV2();

  @override
  Future<SelfEngineRunResultV2> runOnce() async => SelfEngineRunResultV2.noWork;
}
