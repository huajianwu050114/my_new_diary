import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/ai/domain/ai_memory_suggestions_v2.dart';

void main() {
  test('解析、去重并限制AI记忆建议', () {
    final suggestions = AiMemorySuggestionsV2.parse('''
```json
{"suggestions":["我希望先被倾听。","我希望先被倾听。","我正在准备考试。","重要的人叫小林。","偏好简短回复。","第五条"]}
```
''');

    expect(suggestions, hasLength(5));
    expect(suggestions.first, '我希望先被倾听。');
    expect(suggestions.toSet(), hasLength(5));
  });

  test('拒绝非结构化建议', () {
    expect(
      () => AiMemorySuggestionsV2.parse('我建议记住这件事'),
      throwsFormatException,
    );
  });
}
