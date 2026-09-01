import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/life_guide/domain/life_fragment_draft_v2.dart';

void main() {
  test('解析 AI 返回的人生碎片结构化草稿', () {
    final draft = LifeFragmentDraftV2.parse('''
```json
{
  "suitable": true,
  "reason": "包含由真实经历支持的新认识",
  "title": "写给未来自己的提醒",
  "coreInsight": "相信自己不是因为永远成功",
  "context": "面对不确定时重读过去的日记",
  "evidence": "曾经在低谷里仍未放弃自己",
  "futureUse": "再次因为失败怀疑自己时",
  "messageToFutureSelf": "永远期待朝霞",
  "theme": "uncertainty",
  "tags": ["希望", "低谷"]
}
```
''');

    expect(draft.suitable, isTrue);
    expect(draft.title, '写给未来自己的提醒');
    expect(draft.tags, ['希望', '低谷']);
  });

  test('允许 AI 判断一篇日记暂时不必提炼', () {
    final draft = LifeFragmentDraftV2.parse('''
{
  "suitable": false,
  "reason": "目前更像一次事件记录",
  "title": "",
  "coreInsight": "",
  "context": "",
  "evidence": "",
  "futureUse": "",
  "messageToFutureSelf": "",
  "theme": "identity",
  "tags": []
}
''');

    expect(draft.suitable, isFalse);
    expect(draft.reason, '目前更像一次事件记录');
  });

  test('拒绝非 JSON 的模型输出', () {
    expect(
      () => LifeFragmentDraftV2.parse('这是一段普通文字'),
      throwsA(isA<FormatException>()),
    );
  });
}
