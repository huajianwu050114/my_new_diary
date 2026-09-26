import 'package:flutter/material.dart';

import '../data/ai_configuration_store_v2.dart';
import '../data/gemini_rest_client_v2.dart';
import '../domain/ai_models_v2.dart';
import 'ai_memory_page_v2.dart';
import 'ai_response_preferences_page_v2.dart';

class AiSettingsPageV2 extends StatefulWidget {
  const AiSettingsPageV2({super.key, AiConfigurationStoreV2? store})
    : _store = store;

  final AiConfigurationStoreV2? _store;

  @override
  State<AiSettingsPageV2> createState() => _AiSettingsPageV2State();
}

class _AiSettingsPageV2State extends State<AiSettingsPageV2> {
  late final AiConfigurationStoreV2 _store;
  final _keyController = TextEditingController();
  final _modelController = TextEditingController();
  AiConfigurationV2? _configuration;
  bool _enabled = false;
  bool _automaticReply = false;
  bool _selfEngineEnabled = false;
  bool _fallbackEnabled = false;
  AiProviderV2 _provider = AiProviderV2.gemini;
  AiModelStrategyV2 _modelStrategy = AiModelStrategyV2.quality;
  bool _saving = false;
  bool _obscureKey = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _store = widget._store ?? AiConfigurationStoreV2();
    _load();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final configuration = await _store.load();
    if (!mounted) return;
    setState(() {
      _configuration = configuration;
      _enabled = configuration.enabled;
      _automaticReply = configuration.automaticReply;
      _selfEngineEnabled = configuration.selfEngineEnabled;
      _fallbackEnabled = configuration.fallbackEnabled;
      _provider = configuration.provider;
      _modelStrategy = configuration.modelStrategy;
      _modelController.text =
          configuration.modelStrategy == AiModelStrategyV2.custom
          ? configuration.model
          : configuration.provider.modelFor(
              configuration.modelStrategy,
              AiTaskKindV2.utility,
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 设置')),
      body: _configuration == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: SwitchListTile(
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                    secondary: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('启用 AI 功能'),
                    subtitle: Text(
                      _configuration!.hasApiKey
                          ? '已安全保存 API Key'
                          : '尚未配置 API Key',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: SwitchListTile(
                    value: _selfEngineEnabled,
                    onChanged: _enabled
                        ? (value) => setState(() => _selfEngineEnabled = value)
                        : null,
                    secondary: const Icon(Icons.account_tree_outlined),
                    title: const Text('启用 Self Engine'),
                    subtitle: const Text('允许 AI 从日记中提取有原文证据的 Memory Atom；默认关闭'),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.psychology_alt_outlined),
                    title: const Text('AI 记忆'),
                    subtitle: const Text('管理你明确允许AI长期记住的内容'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const AiMemoryPageV2()),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.tune_rounded),
                    title: const Text('回复偏好'),
                    subtitle: const Text('选择倾听方式、长度、提问和表达风格'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const AiResponsePreferencesPageV2(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: SwitchListTile(
                    value: _fallbackEnabled,
                    onChanged: _enabled
                        ? (value) => setState(() => _fallbackEnabled = value)
                        : null,
                    secondary: const Icon(Icons.swap_horiz_rounded),
                    title: const Text('首选不可用时尝试备用服务商'),
                    subtitle: const Text('仅在另一个服务商也保存了 API Key 时生效'),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: SwitchListTile(
                    value: _automaticReply,
                    onChanged: _enabled
                        ? (value) => setState(() => _automaticReply = value)
                        : null,
                    secondary: const Icon(Icons.mark_unread_chat_alt_outlined),
                    title: const Text('保存后自动生成 AI 悄悄话'),
                    subtitle: const Text('保存日记后静默分析，生成成功才会出现在日记详情中'),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<AiProviderV2>(
                  value: _provider,
                  decoration: const InputDecoration(
                    labelText: 'AI 服务商',
                    prefixIcon: Icon(Icons.hub_outlined),
                  ),
                  items: AiProviderV2.values
                      .map(
                        (provider) => DropdownMenuItem(
                          value: provider,
                          child: Text(provider.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _saving
                      ? null
                      : (provider) {
                          if (provider != null) _changeProvider(provider);
                        },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _keyController,
                  obscureText: _obscureKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: _configuration!.hasApiKey
                        ? '替换 ${_provider.label} API Key（留空则不变）'
                        : '${_provider.label} API Key',
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<AiModelStrategyV2>(
                  value: _modelStrategy,
                  decoration: const InputDecoration(
                    labelText: '模型策略',
                    prefixIcon: Icon(Icons.psychology_outlined),
                  ),
                  items: AiModelStrategyV2.values
                      .map(
                        (strategy) => DropdownMenuItem(
                          value: strategy,
                          child: Text(strategy.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _saving
                      ? null
                      : (strategy) {
                          if (strategy != null) {
                            setState(() {
                              _modelStrategy = strategy;
                              if (strategy != AiModelStrategyV2.custom) {
                                _modelController.text = _provider.modelFor(
                                  strategy,
                                  AiTaskKindV2.utility,
                                );
                              }
                            });
                          }
                        },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
                  child: Text(
                    _modelStrategy.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _modelController,
                  enabled: _modelStrategy == AiModelStrategyV2.custom,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: _modelStrategy == AiModelStrategyV2.custom
                        ? '自定义模型'
                        : '当前基础模型（由策略自动选择）',
                    helperText: _modelStrategy == AiModelStrategyV2.custom
                        ? '按账号权限填写模型名称'
                        : '深度任务可能自动使用更高等级模型',
                    prefixIcon: const Icon(Icons.memory_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存 AI 设置'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _saving || _testing ? null : _saveAndTest,
                  icon: _testing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded),
                  label: Text(_testing ? '正在测试…' : '保存并测试连接'),
                ),
                if (_configuration!.hasApiKey)
                  TextButton(
                    onPressed: _saving ? null : _clearKey,
                    child: const Text('删除已保存的 API Key'),
                  ),
              ],
            ),
    );
  }

  Future<void> _save() async {
    final model = _modelController.text.trim();
    final hasNewKey = _keyController.text.trim().isNotEmpty;
    if (_modelStrategy == AiModelStrategyV2.custom && model.isEmpty) {
      _message('请填写模型名称');
      return;
    }
    if (_enabled && !_configuration!.hasApiKey && !hasNewKey) {
      _message('启用 AI 前请填写 API Key');
      return;
    }
    setState(() => _saving = true);
    await _store.save(
      enabled: _enabled,
      provider: _provider,
      model: model,
      automaticReply: _automaticReply,
      selfEngineEnabled: _selfEngineEnabled,
      fallbackEnabled: _fallbackEnabled,
      modelStrategy: _modelStrategy,
      apiKey: hasNewKey ? _keyController.text : null,
    );
    _keyController.clear();
    await _load();
    if (mounted) {
      setState(() => _saving = false);
      _message('AI 设置已保存');
    }
  }

  Future<void> _clearKey() async {
    await _store.clearApiKey(_provider);
    await _store.save(
      enabled: false,
      provider: _provider,
      model: _modelController.text.trim(),
      automaticReply: false,
      selfEngineEnabled: false,
      fallbackEnabled: _fallbackEnabled,
      modelStrategy: _modelStrategy,
    );
    await _load();
    if (mounted) {
      setState(() => _enabled = false);
      _message('API Key 已删除，AI 功能已关闭');
    }
  }

  Future<void> _saveAndTest() async {
    final model = _modelController.text.trim();
    final hasNewKey = _keyController.text.trim().isNotEmpty;
    if ((_modelStrategy == AiModelStrategyV2.custom && model.isEmpty) ||
        (!_configuration!.hasApiKey && !hasNewKey)) {
      _message(
        _modelStrategy == AiModelStrategyV2.custom && model.isEmpty
            ? '请填写模型名称'
            : '请先填写 API Key',
      );
      return;
    }
    setState(() {
      _saving = true;
      _testing = true;
    });
    try {
      await _store.save(
        enabled: true,
        provider: _provider,
        model: model,
        automaticReply: _automaticReply,
        selfEngineEnabled: _selfEngineEnabled,
        fallbackEnabled: _fallbackEnabled,
        modelStrategy: _modelStrategy,
        apiKey: hasNewKey ? _keyController.text : null,
      );
      _keyController.clear();
      final response = await GeminiRestClientV2(configurationStore: _store)
          .generate(
            const [
              AiChatMessageV2(role: AiChatRoleV2.user, text: '只回复“连接成功”四个字。'),
            ],
            options: const AiGenerationOptionsV2(
              task: AiTaskKindV2.utility,
              thinkingLevel: AiThinkingLevelV2.low,
              systemInstruction: '这是连接测试。严格按用户要求回复。',
            ),
          );
      if (mounted) _message('连接成功，用时 ${response.elapsed.inMilliseconds} ms');
      await _load();
    } on AiFailureV2 catch (error) {
      if (mounted) _message('连接失败：${error.message}');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _testing = false;
        });
      }
    }
  }

  Future<void> _changeProvider(AiProviderV2 provider) async {
    final configuration = await _store.loadFor(provider);
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _configuration = configuration;
      _modelStrategy = configuration.modelStrategy;
      _modelController.text =
          configuration.modelStrategy == AiModelStrategyV2.custom
          ? configuration.model
          : configuration.provider.modelFor(
              configuration.modelStrategy,
              AiTaskKindV2.utility,
            );
      _keyController.clear();
    });
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
