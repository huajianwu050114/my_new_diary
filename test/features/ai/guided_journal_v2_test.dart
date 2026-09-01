import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_new_diary/features/ai/application/diary_ai_service_v2.dart';
import 'package:my_new_diary/features/ai/data/ai_configuration_store_v2.dart';
import 'package:my_new_diary/features/ai/data/gemini_rest_client_v2.dart';
import 'package:my_new_diary/features/ai/domain/ai_chat_session_v2.dart';
import 'package:my_new_diary/features/ai/domain/ai_models_v2.dart';
import 'package:my_new_diary/features/ai/domain/guided_journal_v2.dart';
import 'package:my_new_diary/features/ai/presentation/guided_journal_page_v2.dart';
import 'package:my_new_diary/features/diary/application/ports/diary_image_store_v2.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';
import 'package:my_new_diary/features/diary/domain/repositories/diary_repository_v2.dart';
import 'package:my_new_diary/features/diary/presentation/pages/diary_editor_page_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('解析陪写AI的回应或继续倾听决定', () {
    final reply = GuidedJournalReplyDecisionV2.parse(
      '{"respond":true,"reply":"你还记得当时的夕阳吗？"}',
    );
    expect(reply.respond, isTrue);
    expect(reply.reply, contains('夕阳'));

    final quiet = GuidedJournalReplyDecisionV2.parse(
      '{"respond":false,"reply":""}',
    );
    expect(quiet.respond, isFalse);
  });

  test('陪写回应使用低思考并限制为聊天长度', () async {
    final store = AiConfigurationStoreV2(secretStore: _MemorySecretStore());
    await store.save(
      enabled: true,
      provider: AiProviderV2.deepSeek,
      model: 'deepseek-test',
      modelStrategy: AiModelStrategyV2.custom,
      apiKey: 'key',
    );
    late Map<String, dynamic> requestBody;
    final service = DiaryAiServiceV2(
      GeminiRestClientV2(
        configurationStore: store,
        httpClient: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'respond': true,
                      'reply':
                          '听起来你当时的心情既热烈又带着告别感，这种复杂的感受一定持续了很久，你愿意继续讲讲当时发生了什么吗？',
                    }),
                  },
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final decision = await service.guidedJournalReply(
      conversation: const [
        AiChatMessageV2(role: AiChatRoleV2.user, text: '遇到她我就慌不择路'),
      ],
      cadence: GuidedJournalCadenceV2.natural,
    );

    expect(decision.reply.length, lessThanOrEqualTo(40));
    expect(requestBody['thinking'], {'type': 'disabled'});
    expect(requestBody['max_tokens'], 1024);
    final roles = (requestBody['messages'] as List)
        .whereType<Map>()
        .map((message) => message['role'])
        .toList();
    expect(roles.where((role) => role == 'assistant'), isEmpty);
  });

  testWidgets('连续记下内容、按需回应并整理成日记草稿', (tester) async {
    final store = AiConfigurationStoreV2(secretStore: _MemorySecretStore());
    await store.save(
      enabled: true,
      provider: AiProviderV2.deepSeek,
      model: 'deepseek-test',
      modelStrategy: AiModelStrategyV2.custom,
      apiKey: 'key',
    );
    var requests = 0;
    final service = DiaryAiServiceV2(
      GeminiRestClientV2(
        configurationStore: store,
        httpClient: MockClient((request) async {
          requests++;
          final content = requests == 1
              ? jsonEncode({
                  'respond': true,
                  'reply': '你说那句话温暖了整个早上，还记得当时是什么感觉吗？',
                })
              : '那句微不足道的话，却温暖了我整个早上。多年后想起，我怀念的不只是她，也是在一点回应里就能看见希望的自己。';
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': content},
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    GuidedJournalDraftV2? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await Navigator.of(context).push(
                    MaterialPageRoute<GuidedJournalDraftV2>(
                      builder: (_) => GuidedJournalPageV2(service: service),
                    ),
                  );
                },
                child: const Text('开始陪写'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('开始陪写'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '她一出现，我就慌不择路');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(requests, 0);
    expect(find.text('她一出现，我就慌不择路'), findsOneWidget);
    expect(find.text('我在听，你可以继续说'), findsOneWidget);

    await tester.tap(find.text('请回应'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.textContaining('温暖了整个早上'), findsOneWidget);

    await tester.tap(find.text('整理成日记'));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(result, isNotNull);
    expect(result!.body, contains('微不足道的话'));
    expect(result!.session.messages, hasLength(2));
  });

  testWidgets('陪写草稿保存时附带首个Chat', (tester) async {
    final now = DateTime.utc(2026, 8, 21);
    final session = AiChatSessionV2(
      id: 'guided-session',
      title: '陪我写 · 青春',
      createdAt: now,
      updatedAt: now,
      messages: [
        AiSessionMessageV2(
          role: AiChatRoleV2.user,
          text: '我的青春有很多伤痕',
          createdAt: now,
        ),
      ],
    );
    final repository = _MemoryDiaryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: DiaryEditorPageV2(
          repository: repository,
          imageStore: _MemoryImageStore(),
          initialBody: '整理后的日记正文',
          initialAiSession: session,
          skipAutomaticReply: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(repository.entries, hasLength(1));
    expect(repository.entries.single.body, '整理后的日记正文');
    final restored = AiChatSessionV2.tryDecode(
      repository.entries.single.aiAnalyses.single,
    );
    expect(restored?.id, 'guided-session');
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

class _MemoryDiaryRepository implements DiaryRepositoryV2 {
  final List<DiaryEntryV2> entries = [];

  @override
  Stream<List<DiaryEntryV2>> watchEntries({
    DiaryQuery query = const DiaryQuery(),
  }) => Stream.value(List.unmodifiable(entries));

  @override
  Future<DiaryEntryV2?> getById(String id) async =>
      entries.where((entry) => entry.id == id).firstOrNull;

  @override
  Future<void> save(DiaryEntryV2 entry) async {
    entries.removeWhere((value) => value.id == entry.id);
    entries.add(entry);
  }

  @override
  Future<void> deletePermanently(String id) async =>
      entries.removeWhere((entry) => entry.id == id);

  @override
  Future<void> moveToTrash(String id, {required DateTime deletedAt}) async {}

  @override
  Future<void> restore(String id) async {}

  @override
  Future<void> setFavorite(String id, {required bool isFavorite}) async {}
}

class _MemoryImageStore implements DiaryImageStoreV2 {
  @override
  Future<void> delete(String imageId) async {}

  @override
  Future<Uint8List?> read(String imageId) async => null;

  @override
  Future<String> save({
    required Uint8List bytes,
    required String extension,
  }) async => 'image';
}
