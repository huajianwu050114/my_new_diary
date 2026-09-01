import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/ai/data/ai_response_feedback_store_v2.dart';
import 'package:my_new_diary/features/ai/data/ai_response_preferences_store_v2.dart';
import 'package:my_new_diary/features/ai/domain/ai_response_feedback_v2.dart';
import 'package:my_new_diary/features/ai/domain/ai_response_preferences_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('回复偏好保存后可以恢复', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AiResponsePreferencesStoreV2();
    await store.save(
      const AiResponsePreferencesV2(
        style: AiCompanionStyleV2.listen,
        length: AiReplyLengthV2.short,
        allowQuestions: false,
        avoidPlatitudes: true,
      ),
    );
    final restored = await store.load();
    expect(restored.style, AiCompanionStyleV2.listen);
    expect(restored.length, AiReplyLengthV2.short);
    expect(restored.allowQuestions, isFalse);
    expect(restored.avoidPlatitudes, isTrue);
  });

  test('同一回复的新反馈会覆盖旧反馈', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AiResponseFeedbackStoreV2();
    final now = DateTime.utc(2026, 8, 20);
    await store.save(
      AiResponseFeedbackV2(
        responseId: 'reply',
        helpful: false,
        reason: '太空泛',
        createdAt: now,
      ),
    );
    await store.save(
      AiResponseFeedbackV2(
        responseId: 'reply',
        helpful: true,
        reason: '',
        createdAt: now,
      ),
    );
    final values = await store.load();
    expect(values, hasLength(1));
    expect(values.single.helpful, isTrue);
  });
}
