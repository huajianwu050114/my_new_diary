import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_new_diary/features/ai/application/diary_ai_service_v2.dart';
import 'package:my_new_diary/features/ai/data/ai_configuration_store_v2.dart';
import 'package:my_new_diary/features/ai/data/ai_memory_store_v2.dart';
import 'package:my_new_diary/features/ai/data/gemini_rest_client_v2.dart';
import 'package:my_new_diary/features/ai/data/ai_response_feedback_store_v2.dart';
import 'package:my_new_diary/features/ai/data/ai_response_preferences_store_v2.dart';
import 'package:my_new_diary/features/ai/domain/ai_memory_v2.dart';
import 'package:my_new_diary/features/ai/domain/ai_response_feedback_v2.dart';
import 'package:my_new_diary/features/ai/domain/ai_response_preferences_v2.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('记忆可保存、停用和删除', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AiMemoryStoreV2();
    final memory = AiMemoryV2(
      id: 'one',
      text: '我更希望先被倾听。',
      createdAt: DateTime.utc(2026, 8, 19),
    );
    await store.save(memory);
    expect((await store.load()).single.text, memory.text);

    await store.save(memory.copyWith(enabled: false));
    expect((await store.load()).single.enabled, isFalse);

    await store.delete(memory.id);
    expect(await store.load(), isEmpty);
  });

  test('只把用户启用的记忆加入AI上下文', () async {
    SharedPreferences.setMockInitialValues({});
    final memories = AiMemoryStoreV2();
    await memories.save(
      AiMemoryV2(
        id: 'enabled',
        text: '我更希望先被倾听。',
        createdAt: DateTime.utc(2026, 8, 19),
      ),
    );
    await AiResponsePreferencesStoreV2().save(
      const AiResponsePreferencesV2(
        style: AiCompanionStyleV2.listen,
        length: AiReplyLengthV2.short,
        allowQuestions: false,
      ),
    );
    await AiResponseFeedbackStoreV2().save(
      AiResponseFeedbackV2(
        responseId: 'old-response',
        helpful: false,
        reason: '说教感太强',
        createdAt: DateTime.utc(2026, 8, 19),
      ),
    );
    await memories.save(
      AiMemoryV2(
        id: 'disabled',
        text: '这条内容不允许发送。',
        enabled: false,
        createdAt: DateTime.utc(2026, 8, 19),
      ),
    );
    final secrets = _MemorySecretStore();
    final configuration = AiConfigurationStoreV2(secretStore: secrets);
    await configuration.save(
      enabled: true,
      provider: AiProviderV2.deepSeek,
      model: 'test-model',
      modelStrategy: AiModelStrategyV2.custom,
      apiKey: 'test-key',
    );
    late String requestBody;
    final service = DiaryAiServiceV2(
      GeminiRestClientV2(
        configurationStore: configuration,
        httpClient: MockClient((request) async {
          requestBody = request.body;
          return http.Response(
            '{"choices":[{"message":{"content":"收到"}}]}',
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
      memoryStore: memories,
    );
    final now = DateTime.utc(2026, 8, 19);

    await service.writeFriendReply(
      DiaryEntryV2(
        id: 'diary',
        body: '今天有点累。',
        entryDate: now,
        createdAt: now,
        updatedAt: now,
      ),
    );

    expect(requestBody, contains('我更希望先被倾听'));
    expect(requestBody, isNot(contains('这条内容不允许发送')));
    expect(requestBody, contains('少给建议'));
    expect(requestBody, contains('不要在结尾追问'));
    expect(requestBody, contains('说教感太强'));
    expect(requestBody, contains('并存、矛盾或难以命名的感受'));
    expect(requestBody, contains('system'));
  });
}

class _MemorySecretStore implements AiSecretStoreV2 {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
