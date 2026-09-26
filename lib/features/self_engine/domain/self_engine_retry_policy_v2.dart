class SelfEngineRetryPolicyV2 {
  const SelfEngineRetryPolicyV2({
    this.maxAttempts = 5,
    this.baseDelay = const Duration(minutes: 1),
    this.maxDelay = const Duration(hours: 1),
  }) : assert(maxAttempts > 0);

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  Duration delayAfterAttempt(int attemptCount) {
    var milliseconds = baseDelay.inMilliseconds;
    for (var attempt = 1; attempt < attemptCount; attempt++) {
      milliseconds *= 2;
      if (milliseconds >= maxDelay.inMilliseconds) return maxDelay;
    }
    return Duration(
      milliseconds: milliseconds.clamp(0, maxDelay.inMilliseconds).toInt(),
    );
  }
}
