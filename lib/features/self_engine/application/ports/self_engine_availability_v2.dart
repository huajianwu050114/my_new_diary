enum SelfEngineAvailabilityStatusV2 { disabled, unavailable, available }

abstract interface class SelfEngineAvailabilityV2 {
  Future<bool> canProcess();
}
