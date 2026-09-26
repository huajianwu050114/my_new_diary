import '../../ai/data/ai_configuration_store_v2.dart';
import 'ports/self_engine_availability_v2.dart';

class ConfiguredSelfEngineAvailabilityV2 implements SelfEngineAvailabilityV2 {
  const ConfiguredSelfEngineAvailabilityV2(this._configurationStore);

  final AiConfigurationStoreV2 _configurationStore;

  @override
  Future<bool> canProcess() async {
    final configuration = await _configurationStore.load();
    return configuration.selfEngineEnabled && configuration.ready;
  }
}
