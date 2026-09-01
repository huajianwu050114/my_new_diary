import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_new_diary/features/ai/data/ai_configuration_store_v2.dart';
import 'package:my_new_diary/features/ai/data/gemini_rest_client_v2.dart';
import 'package:my_new_diary/features/ai/domain/ai_models_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('未启用时不会发起网络请求', () async {
    var requested = false;
    final store = AiConfigurationStoreV2(secretStore: _MemorySecretStore());
    final client = GeminiRestClientV2(
      configurationStore: store,
      httpClient: MockClient((_) async {
        requested = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      client.generate(const [
        AiChatMessageV2(role: AiChatRoleV2.user, text: '你好'),
      ]),
      throwsA(isA<AiNotConfiguredV2>()),
    );
    expect(requested, isFalse);
  });

  test('发送 Gemini REST 请求并解析回答', () async {
    final secrets = _MemorySecretStore();
    final store = AiConfigurationStoreV2(secretStore: secrets);
    await store.save(
      enabled: true,
      provider: AiProviderV2.gemini,
      model: 'gemini-test',
      modelStrategy: AiModelStrategyV2.custom,
      apiKey: 'secret-key',
    );
    late http.Request captured;
    final client = GeminiRestClientV2(
      configurationStore: store,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '温柔的回答'},
                  ],
                },
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await client.generate(const [
      AiChatMessageV2(role: AiChatRoleV2.user, text: '今天很开心'),
    ]);

    expect(result.text, '温柔的回答');
    expect(captured.url.path, '/v1beta/models/gemini-test:generateContent');
    expect(captured.url.queryParameters['key'], 'secret-key');
    expect(captured.body, contains('今天很开心'));
  });

  test('保存后自动回信开关会持久化', () async {
    final store = AiConfigurationStoreV2(secretStore: _MemorySecretStore());
    await store.save(
      enabled: true,
      automaticReply: true,
      fallbackEnabled: true,
      modelStrategy: AiModelStrategyV2.economy,
      provider: AiProviderV2.deepSeek,
      model: 'deepseek-test',
      apiKey: 'secret-key',
    );

    final restored = await store.load();

    expect(restored.automaticReply, isTrue);
    expect(restored.fallbackEnabled, isTrue);
    expect(restored.modelStrategy, AiModelStrategyV2.economy);
    expect(restored.ready, isTrue);
  });

  test('首选服务失败后自动使用已配置的备用服务商', () async {
    final secrets = _MemorySecretStore();
    final store = AiConfigurationStoreV2(secretStore: secrets);
    await store.save(
      enabled: true,
      provider: AiProviderV2.deepSeek,
      model: 'deepseek-test',
      modelStrategy: AiModelStrategyV2.custom,
      apiKey: 'deepseek-key',
    );
    await store.save(
      enabled: true,
      fallbackEnabled: true,
      provider: AiProviderV2.gemini,
      model: 'gemini-test',
      modelStrategy: AiModelStrategyV2.custom,
      apiKey: 'gemini-key',
    );
    final requestedHosts = <String>[];
    final client = GeminiRestClientV2(
      configurationStore: store,
      httpClient: MockClient((request) async {
        requestedHosts.add(request.url.host);
        if (request.url.host.contains('googleapis')) {
          return http.Response('{}', 503);
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '备用服务已接手'},
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await client.generate(const [
      AiChatMessageV2(role: AiChatRoleV2.user, text: '你好'),
    ]);

    expect(result.text, '备用服务已接手');
    expect(requestedHosts, [
      'generativelanguage.googleapis.com',
      'api.deepseek.com',
    ]);
  });

  test('发送 DeepSeek Chat Completions 请求并解析回答', () async {
    final store = AiConfigurationStoreV2(secretStore: _MemorySecretStore());
    await store.save(
      enabled: true,
      provider: AiProviderV2.deepSeek,
      model: 'deepseek-v4-flash',
      modelStrategy: AiModelStrategyV2.custom,
      apiKey: 'deepseek-key',
    );
    late http.Request captured;
    final client = GeminiRestClientV2(
      configurationStore: store,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': '无需 VPN 的回答'},
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await client.generate(const [
      AiChatMessageV2(role: AiChatRoleV2.user, text: '回顾今天'),
    ]);

    expect(result.text, '无需 VPN 的回答');
    expect(
      captured.url.toString(),
      'https://api.deepseek.com/chat/completions',
    );
    expect(captured.headers['authorization'], 'Bearer deepseek-key');
    expect(captured.body, contains('deepseek-v4-flash'));
    expect(captured.body, contains('回顾今天'));
  });

  test('精细陪伴策略为DeepSeek深度任务选择V4 Pro和最高思考', () async {
    final store = AiConfigurationStoreV2(secretStore: _MemorySecretStore());
    await store.save(
      enabled: true,
      provider: AiProviderV2.deepSeek,
      model: 'ignored-in-auto-mode',
      modelStrategy: AiModelStrategyV2.quality,
      apiKey: 'deepseek-key',
    );
    late http.Request captured;
    final client = GeminiRestClientV2(
      configurationStore: store,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          '{"choices":[{"message":{"content":"细腻回应"}}]}',
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await client.generate(
      const [AiChatMessageV2(role: AiChatRoleV2.user, text: '分析这段感受')],
      options: const AiGenerationOptionsV2(
        task: AiTaskKindV2.deepReflection,
        thinkingLevel: AiThinkingLevelV2.high,
        systemInstruction: '区分事实与推测',
      ),
    );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'deepseek-v4-pro');
    expect(body['thinking'], {'type': 'enabled'});
    expect(body['reasoning_effort'], 'max');
    expect(body, isNot(contains('temperature')));
    expect((body['messages'] as List).first, {
      'role': 'system',
      'content': '区分事实与推测',
    });
  });

  test('精细陪伴策略为DeepSeek轻量任务保留V4 Flash', () async {
    final store = AiConfigurationStoreV2(secretStore: _MemorySecretStore());
    await store.save(
      enabled: true,
      provider: AiProviderV2.deepSeek,
      model: 'ignored-in-auto-mode',
      modelStrategy: AiModelStrategyV2.quality,
      apiKey: 'deepseek-key',
    );
    late http.Request captured;
    final client = GeminiRestClientV2(
      configurationStore: store,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          '{"choices":[{"message":{"content":"完成"}}]}',
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await client.generate(const [
      AiChatMessageV2(role: AiChatRoleV2.user, text: '整理语音'),
    ]);

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'deepseek-v4-flash');
    expect(body['thinking'], {'type': 'disabled'});
    expect(body, isNot(contains('reasoning_effort')));
  });

  test('Gemini精细模式使用3.7 Flash和任务级思考参数', () async {
    final store = AiConfigurationStoreV2(secretStore: _MemorySecretStore());
    await store.save(
      enabled: true,
      provider: AiProviderV2.gemini,
      model: 'ignored-in-auto-mode',
      modelStrategy: AiModelStrategyV2.quality,
      apiKey: 'gemini-key',
    );
    late http.Request request;
    final client = GeminiRestClientV2(
      configurationStore: store,
      httpClient: MockClient((value) async {
        request = value;
        return http.Response(
          '{"candidates":[{"content":{"parts":[{"text":"完成"}]}}]}',
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await client.generate(
      const [AiChatMessageV2(role: AiChatRoleV2.user, text: '回顾')],
      options: const AiGenerationOptionsV2(
        task: AiTaskKindV2.deepReflection,
        thinkingLevel: AiThinkingLevelV2.high,
        systemInstruction: '谨慎理解情绪',
      ),
    );

    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(request.url.path, '/v1beta/models/gemini-3.7-flash:generateContent');
    expect((body['generationConfig'] as Map)['thinkingConfig'], {
      'thinkingLevel': 'high',
    });
    expect(body['generationConfig'], isNot(contains('temperature')));
    expect(body['systemInstruction'], isNotNull);
  });

  test('Gemini 3多轮文字对话会展平以避免缺失思考签名', () async {
    final store = AiConfigurationStoreV2(secretStore: _MemorySecretStore());
    await store.save(
      enabled: true,
      provider: AiProviderV2.gemini,
      model: 'ignored-in-auto-mode',
      modelStrategy: AiModelStrategyV2.quality,
      apiKey: 'gemini-key',
    );
    late http.Request captured;
    final client = GeminiRestClientV2(
      configurationStore: store,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          '{"candidates":[{"content":{"parts":[{"text":"怎么认识的？"}]}}]}',
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await client.generate(const [
      AiChatMessageV2(role: AiChatRoleV2.user, text: '想到一个女生'),
      AiChatMessageV2(role: AiChatRoleV2.model, text: '嗯，怎么了？'),
      AiChatMessageV2(role: AiChatRoleV2.user, text: '她一出现我就慌不择路'),
    ]);

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    final contents = body['contents'] as List;
    expect(contents, hasLength(1));
    expect((contents.single as Map)['role'], 'user');
    expect(captured.body, contains('助手此前回复'));
    expect(captured.body, contains('她一出现我就慌不择路'));
  });

  test('配额错误会返回可理解的提示', () async {
    final store = AiConfigurationStoreV2(secretStore: _MemorySecretStore());
    await store.save(
      enabled: true,
      provider: AiProviderV2.gemini,
      model: 'gemini-test',
      modelStrategy: AiModelStrategyV2.custom,
      apiKey: 'key',
    );
    final client = GeminiRestClientV2(
      configurationStore: store,
      httpClient: MockClient((_) async => http.Response('{}', 429)),
    );

    await expectLater(
      client.generate(const [
        AiChatMessageV2(role: AiChatRoleV2.user, text: '你好'),
      ]),
      throwsA(
        isA<AiRequestFailureV2>().having(
          (failure) => failure.message,
          'message',
          contains('配额'),
        ),
      ),
    );
  });
}

class _MemorySecretStore implements AiSecretStoreV2 {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
