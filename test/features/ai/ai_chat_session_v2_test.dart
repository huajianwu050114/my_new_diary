import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/ai/domain/ai_chat_session_v2.dart';
import 'package:my_new_diary/features/ai/domain/ai_models_v2.dart';

void main() {
  test('完整 AI Chat 会话可以写入日记字段并恢复', () {
    final createdAt = DateTime.utc(2026, 7, 29, 9);
    final session = AiChatSessionV2(
      id: 'chat-1',
      title: '聊聊今天的决定',
      createdAt: createdAt,
      updatedAt: createdAt.add(const Duration(minutes: 2)),
      messages: [
        AiSessionMessageV2(
          role: AiChatRoleV2.user,
          text: '我今天做了一个决定',
          createdAt: createdAt,
        ),
        AiSessionMessageV2(
          role: AiChatRoleV2.model,
          text: '听起来这件事对你很重要。',
          createdAt: createdAt.add(const Duration(minutes: 1)),
        ),
      ],
    );

    final restored = AiChatSessionV2.tryDecode(session.encode());

    expect(restored, isNotNull);
    expect(restored!.id, 'chat-1');
    expect(restored.title, '聊聊今天的决定');
    expect(restored.messages, hasLength(2));
    expect(restored.messages.last.role, AiChatRoleV2.model);
    expect(restored.messages.last.text, '听起来这件事对你很重要。');
  });

  test('普通 AI 总结和旧版记录不会被误判为 Chat 会话', () {
    expect(AiChatSessionV2.tryDecode('【AI 总结】内容'), isNull);
    expect(AiChatSessionV2.tryDecode('【AI 伴聊】旧回复'), isNull);
  });
}
