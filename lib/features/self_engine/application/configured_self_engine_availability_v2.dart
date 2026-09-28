import '../../ai/data/ai_configuration_store_v2.dart';
import 'ports/self_engine_availability_v2.dart';

class ConfiguredSelfEngineAvailabilityV2 implements SelfEngineAvailabilityV2 {
  const ConfiguredSelfEngineAvailabilityV2(this._configurationStore);

  final AiConfigurationStoreV2 _configurationStore;

  Future<SelfEngineAvailabilityStatusV2> loadStatus() async {
    final configuration = await _configurationStore.load();
    if (!configuration.selfEngineEnabled) {
      return SelfEngineAvailabilityStatusV2.disabled;
    }
    if (!configuration.ready) {
      return SelfEngineAvailabilityStatusV2.unavailable;
    }
    return SelfEngineAvailabilityStatusV2.available;
  }

  @override
  Future<bool> canProcess() async =>
      await loadStatus() == SelfEngineAvailabilityStatusV2.available;
}
