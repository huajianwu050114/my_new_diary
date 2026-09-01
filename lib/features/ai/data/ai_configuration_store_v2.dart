import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ai_models_v2.dart';

class AiConfigurationStoreV2 {
  AiConfigurationStoreV2({AiSecretStoreV2? secretStore})
    : _secretStore = secretStore ?? const SecureAiSecretStoreV2();

  static const _apiKeyName = 'v2_gemini_api_key';
  static const _deepSeekApiKeyName = 'v2_deepseek_api_key';
  static const _enabledName = 'v2_ai_enabled';
  static const _providerName = 'v2_ai_provider';
  static const _modelName = 'v2_ai_model';
  static const _deepSeekModelName = 'v2_deepseek_model';
  static const _automaticReplyName = 'v2_ai_automatic_reply';
  static const _fallbackEnabledName = 'v2_ai_fallback_enabled';
  static const _modelStrategyName = 'v2_ai_model_strategy_v3';

  final AiSecretStoreV2 _secretStore;

  Future<AiConfigurationV2> load() async {
    final preferences = await SharedPreferences.getInstance();
    final provider = AiProviderV2.values.firstWhere(
      (value) => value.name == preferences.getString(_providerName),
      orElse: () => AiProviderV2.gemini,
    );
    return _loadFor(preferences, provider);
  }

  Future<AiConfigurationV2> loadFor(AiProviderV2 provider) async {
    final preferences = await SharedPreferences.getInstance();
    return _loadFor(preferences, provider);
  }

  Future<AiConfigurationV2> _loadFor(
    SharedPreferences preferences,
    AiProviderV2 provider,
  ) async {
    final keyName = _keyName(provider);
    final strategy = AiModelStrategyV2.values.firstWhere(
      (value) => value.name == preferences.getString(_modelStrategyName),
      orElse: () => AiModelStrategyV2.quality,
    );
    return AiConfigurationV2(
      enabled: preferences.getBool(_enabledName) ?? false,
      automaticReply: preferences.getBool(_automaticReplyName) ?? false,
      fallbackEnabled: preferences.getBool(_fallbackEnabledName) ?? false,
      hasApiKey: (await _secretStore.read(keyName))?.isNotEmpty == true,
      provider: provider,
      modelStrategy: strategy,
      model:
          preferences.getString(_modelPreferenceName(provider)) ??
          provider.defaultModel,
    );
  }

  Future<String?> readApiKey(AiProviderV2 provider) =>
      _secretStore.read(_keyName(provider));

  Future<void> save({
    required bool enabled,
    required AiProviderV2 provider,
    required String model,
    bool? automaticReply,
    bool? fallbackEnabled,
    AiModelStrategyV2? modelStrategy,
    String? apiKey,
  }) async {
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      await _secretStore.write(_keyName(provider), apiKey.trim());
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledName, enabled);
    if (automaticReply != null) {
      await preferences.setBool(_automaticReplyName, automaticReply);
    }
    if (fallbackEnabled != null) {
      await preferences.setBool(_fallbackEnabledName, fallbackEnabled);
    }
    if (modelStrategy != null) {
      await preferences.setString(_modelStrategyName, modelStrategy.name);
    }
    await preferences.setString(_providerName, provider.name);
    await preferences.setString(_modelPreferenceName(provider), model.trim());
  }

  Future<void> clearApiKey(AiProviderV2 provider) =>
      _secretStore.delete(_keyName(provider));

  String _keyName(AiProviderV2 provider) => switch (provider) {
    AiProviderV2.gemini => _apiKeyName,
    AiProviderV2.deepSeek => _deepSeekApiKeyName,
  };

  String _modelPreferenceName(AiProviderV2 provider) => switch (provider) {
    AiProviderV2.gemini => _modelName,
    AiProviderV2.deepSeek => _deepSeekModelName,
  };
}

abstract interface class AiSecretStoreV2 {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SecureAiSecretStoreV2 implements AiSecretStoreV2 {
  const SecureAiSecretStoreV2({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class AiConfigurationV2 {
  const AiConfigurationV2({
    required this.enabled,
    required this.automaticReply,
    required this.hasApiKey,
    required this.provider,
    required this.model,
    this.modelStrategy = AiModelStrategyV2.quality,
    this.fallbackEnabled = false,
  });

  final bool enabled;
  final bool automaticReply;
  final bool hasApiKey;
  final AiProviderV2 provider;
  final String model;
  final AiModelStrategyV2 modelStrategy;
  final bool fallbackEnabled;

  bool get ready => enabled && hasApiKey;
}

enum AiModelStrategyV2 {
  quality('精细陪伴', '深度任务优先使用更强模型，日常任务兼顾速度'),
  balanced('日常平衡', '统一使用稳定主力模型，速度和质量较均衡'),
  economy('节省模式', '优先低延迟和较低费用'),
  custom('自定义模型', '所有任务使用下方手动填写的模型');

  const AiModelStrategyV2(this.label, this.description);

  final String label;
  final String description;
}

enum AiProviderV2 {
  gemini('Google Gemini', 'gemini-3.7-flash'),
  deepSeek('DeepSeek', 'deepseek-v4-pro');

  const AiProviderV2(this.label, this.defaultModel);

  final String label;
  final String defaultModel;

  String modelFor(AiModelStrategyV2 strategy, AiTaskKindV2 task) {
    if (strategy == AiModelStrategyV2.custom) return defaultModel;
    return switch ((this, strategy, task)) {
      (AiProviderV2.gemini, AiModelStrategyV2.quality, _) => 'gemini-3.7-flash',
      (AiProviderV2.gemini, AiModelStrategyV2.balanced, _) =>
        'gemini-3.6-flash',
      (AiProviderV2.gemini, AiModelStrategyV2.economy, _) =>
        'gemini-3.5-flash-lite',
      (
        AiProviderV2.deepSeek,
        AiModelStrategyV2.quality,
        AiTaskKindV2.companion || AiTaskKindV2.deepReflection,
      ) =>
        'deepseek-v4-pro',
      (AiProviderV2.deepSeek, _, _) => 'deepseek-v4-flash',
      (_, AiModelStrategyV2.custom, _) => defaultModel,
    };
  }
}
