import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/ai_models_v2.dart';
import 'ai_configuration_store_v2.dart';

/// Unified client for Gemini and DeepSeek.
///
/// The historical filename is kept to avoid breaking existing imports.
class GeminiRestClientV2 {
  GeminiRestClientV2({
    required this.configurationStore,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final AiConfigurationStoreV2 configurationStore;
  final http.Client _httpClient;

  Future<AiResponseV2> generate(
    List<AiChatMessageV2> messages, {
    AiGenerationOptionsV2 options = const AiGenerationOptionsV2(),
  }) async {
    final configuration = await configurationStore.load();
    if (!configuration.enabled) {
      throw const AiNotConfiguredV2();
    }
    if (messages.isEmpty) {
      throw const AiRequestFailureV2('没有可发送给 AI 的内容');
    }

    try {
      return await _generateWith(configuration, messages, options);
    } on AiFailureV2 {
      if (!configuration.fallbackEnabled) rethrow;
      final fallbackProvider = configuration.provider == AiProviderV2.gemini
          ? AiProviderV2.deepSeek
          : AiProviderV2.gemini;
      final fallback = await configurationStore.loadFor(fallbackProvider);
      if (!fallback.hasApiKey) rethrow;
      try {
        return await _generateWith(fallback, messages, options);
      } on AiFailureV2 {
        throw const AiRequestFailureV2('首选和备用 AI 服务均不可用，请稍后重试');
      }
    }
  }

  Future<AiResponseV2> _generateWith(
    AiConfigurationV2 configuration,
    List<AiChatMessageV2> messages,
    AiGenerationOptionsV2 options,
  ) async {
    final apiKey = await configurationStore.readApiKey(configuration.provider);
    if (apiKey == null || apiKey.isEmpty) throw const AiNotConfiguredV2();
    final model = _selectedModel(configuration, options);

    final stopwatch = Stopwatch()..start();
    try {
      final request = _buildRequest(
        configuration,
        apiKey,
        model,
        messages,
        options,
      );
      final response = await _httpClient
          .post(
            request.uri,
            headers: request.headers,
            body: jsonEncode(request.body),
          )
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AiRequestFailureV2('API Key 无效或没有模型访问权限');
      }
      if (response.statusCode == 429) {
        throw const AiRequestFailureV2('请求过于频繁或配额已用完，请稍后再试');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiRequestFailureV2('AI 服务暂时不可用（${response.statusCode}）');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const AiRequestFailureV2('AI 返回了无法识别的数据');
      }
      final text = switch (configuration.provider) {
        AiProviderV2.gemini => _geminiText(decoded),
        AiProviderV2.deepSeek => _deepSeekText(decoded),
      };
      if (text.trim().isEmpty) {
        throw const AiRequestFailureV2('AI 返回了空内容');
      }
      return AiResponseV2(
        text: text.trim(),
        elapsed: stopwatch.elapsed,
        provider: configuration.provider.name,
        model: model,
      );
    } on AiFailureV2 {
      rethrow;
    } catch (_) {
      throw const AiRequestFailureV2('无法连接 AI 服务，请检查网络后重试');
    } finally {
      stopwatch.stop();
    }
  }

  _AiHttpRequestV2 _buildRequest(
    AiConfigurationV2 configuration,
    String apiKey,
    String model,
    List<AiChatMessageV2> messages,
    AiGenerationOptionsV2 options,
  ) {
    final thinkingLevel = options.thinkingLevel.name;
    final deepSeekThinking = switch (options.thinkingLevel) {
      AiThinkingLevelV2.minimal || AiThinkingLevelV2.low => false,
      AiThinkingLevelV2.medium || AiThinkingLevelV2.high => true,
    };
    return switch (configuration.provider) {
      AiProviderV2.gemini => _AiHttpRequestV2(
        uri: Uri.https(
          'generativelanguage.googleapis.com',
          '/v1beta/models/$model:generateContent',
          {'key': apiKey},
        ),
        headers: const {'content-type': 'application/json'},
        body: {
          if (options.systemInstruction case final instruction?)
            'systemInstruction': {
              'parts': [
                {'text': instruction},
              ],
            },
          'contents': _geminiContents(model, messages),
          'generationConfig': {
            'maxOutputTokens': options.maxOutputTokens,
            'thinkingConfig': {'thinkingLevel': thinkingLevel},
            if (options.jsonOutput) 'responseMimeType': 'application/json',
          },
        },
      ),
      AiProviderV2.deepSeek => _AiHttpRequestV2(
        uri: Uri.https('api.deepseek.com', '/chat/completions'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $apiKey',
        },
        body: {
          'model': model,
          'messages': [
            if (options.systemInstruction case final instruction?)
              {'role': 'system', 'content': instruction},
            ...messages.map(
              (message) => {
                'role': message.role == AiChatRoleV2.user
                    ? 'user'
                    : 'assistant',
                'content': message.text,
              },
            ),
          ],
          'thinking': {'type': deepSeekThinking ? 'enabled' : 'disabled'},
          if (deepSeekThinking)
            'reasoning_effort': options.thinkingLevel == AiThinkingLevelV2.high
                ? 'max'
                : 'high',
          if (options.jsonOutput) 'response_format': {'type': 'json_object'},
          'max_tokens': options.maxOutputTokens,
          'stream': false,
        },
      ),
    };
  }

  String _selectedModel(
    AiConfigurationV2 configuration,
    AiGenerationOptionsV2 options,
  ) => configuration.modelStrategy == AiModelStrategyV2.custom
      ? configuration.model
      : configuration.provider.modelFor(
          configuration.modelStrategy,
          options.task,
        );

  String _geminiText(Map<String, dynamic> decoded) {
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const AiRequestFailureV2('AI 没有返回内容，可能触发了安全过滤');
    }
    final firstCandidate = candidates.first;
    if (firstCandidate is! Map<String, dynamic>) {
      throw const AiRequestFailureV2('AI 返回了无法识别的数据');
    }
    final content = firstCandidate['content'];
    if (content is! Map<String, dynamic>) {
      throw const AiRequestFailureV2('AI 返回了无法识别的数据');
    }
    final parts = content['parts'];
    if (parts is! List) {
      throw const AiRequestFailureV2('AI 返回了无法识别的数据');
    }
    return parts
        .whereType<Map>()
        .map((part) => part['text'])
        .whereType<String>()
        .join();
  }

  List<Map<String, Object>> _geminiContents(
    String model,
    List<AiChatMessageV2> messages,
  ) {
    final hasModelHistory = messages.any(
      (message) => message.role == AiChatRoleV2.model,
    );
    if (model.startsWith('gemini-3') && hasModelHistory) {
      final transcript = messages
          .map(
            (message) =>
                '${message.role == AiChatRoleV2.user ? '用户' : '助手此前回复'}：${message.text}',
          )
          .join('\n');
      return [
        {
          'role': 'user',
          'parts': [
            {
              'text':
                  '以下是连续对话记录。助手此前回复只用于理解上下文，请回应最后一条用户消息。\n<conversation>\n$transcript\n</conversation>',
            },
          ],
        },
      ];
    }
    return messages
        .map(
          (message) => <String, Object>{
            'role': message.role == AiChatRoleV2.user ? 'user' : 'model',
            'parts': [
              {'text': message.text},
            ],
          },
        )
        .toList(growable: false);
  }

  String _deepSeekText(Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiRequestFailureV2('AI 没有返回内容，可能触发了安全过滤');
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      throw const AiRequestFailureV2('AI 返回了无法识别的数据');
    }
    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      throw const AiRequestFailureV2('AI 返回了无法识别的数据');
    }
    return message['content'] is String ? message['content'] as String : '';
  }
}

class _AiHttpRequestV2 {
  const _AiHttpRequestV2({
    required this.uri,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final Map<String, String> headers;
  final Map<String, Object?> body;
}
