enum SelfEngineRunResultV2 {
  unavailable,
  noWork,
  completed,
  retryScheduled,
  terminalFailure,
  ownershipLost,
}

abstract interface class SelfEngineRunnerV2 {
  Future<SelfEngineRunResultV2> runOnce();
}
