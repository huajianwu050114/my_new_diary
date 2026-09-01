import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/life_guide/domain/life_fragment_v2.dart';

void main() {
  test('补充既有碎片时保留原文并合并来源和标签', () {
    final existing = _fragment(
      id: 'existing',
      insight: '我不必一次解决全部问题。',
      diaryId: 'diary-1',
      tags: const ['低谷'],
      isRope: true,
    );
    final addition = _fragment(
      id: 'addition',
      insight: '先完成今天能完成的一小步。',
      diaryId: 'diary-2',
      tags: const ['行动', '低谷'],
    );

    final merged = mergeLifeFragmentsV2(
      existing,
      addition,
      updatedAt: DateTime.utc(2026, 8, 18),
    );

    expect(merged.id, 'existing');
    expect(merged.coreInsight, contains(existing.coreInsight));
    expect(merged.coreInsight, contains(addition.coreInsight));
    expect(merged.sourceDiaryIds, ['diary-1', 'diary-2']);
    expect(merged.tags, ['低谷', '行动']);
    expect(merged.isRope, isTrue);
    expect(merged.status, LifeFragmentStatusV2.confirmed);
  });
}

LifeFragmentV2 _fragment({
  required String id,
  required String insight,
  required String diaryId,
  required List<String> tags,
  bool isRope = false,
}) {
  final time = DateTime.utc(2026, 8, 1);
  return LifeFragmentV2(
    id: id,
    title: '给未来的提醒',
    coreInsight: insight,
    context: '一段经历',
    evidence: '真实发生过',
    futureUse: '再次低落时',
    messageToFutureSelf: '慢慢来',
    theme: '对我有用的方法',
    tags: tags,
    sourceDiaryIds: [diaryId],
    isRope: isRope,
    status: LifeFragmentStatusV2.confirmed,
    createdAt: time,
    updatedAt: time,
  );
}
