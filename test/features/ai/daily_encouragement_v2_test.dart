import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/ai/application/daily_encouragement_coordinator_v2.dart';
import 'package:my_new_diary/features/ai/data/daily_encouragement_store_v2.dart';
import 'package:my_new_diary/features/ai/domain/daily_encouragement_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同一天只生成一次并直接读取缓存', () async {
    final store = _MemoryDailyEncouragementStore();
    var requests = 0;
    final coordinator = DailyEncouragementCoordinatorV2(
      store: store,
      clock: () => DateTime(2026, 8, 1, 9),
      generate: ({required dateKey, required recentTexts}) async {
        requests++;
        return _draft('慢一点也没关系，今天仍有属于你的从容。');
      },
    );

    final first = await coordinator.loadToday();
    final second = await coordinator.loadToday();

    expect(requests, 1);
    expect(first?.dateKey, '2026-08-01');
    expect(second?.text, first?.text);
  });

  test('跨天生成新内容并带上最近历史用于避重', () async {
    var now = DateTime(2026, 8, 1, 9);
    final store = _MemoryDailyEncouragementStore();
    List<String> receivedHistory = const [];
    var requests = 0;
    final coordinator = DailyEncouragementCoordinatorV2(
      store: store,
      clock: () => now,
      generate: ({required dateKey, required recentTexts}) async {
        requests++;
        receivedHistory = recentTexts;
        return _draft(
          dateKey == '2026-08-01'
              ? '先照顾好眼前的一小步，远方会慢慢靠近。'
              : '窗边的新光已经到了，你也可以按自己的速度开始。',
        );
      },
    );

    final first = await coordinator.loadToday();
    now = DateTime(2026, 8, 2, 8);
    final second = await coordinator.loadToday();

    expect(requests, 2);
    expect(second?.dateKey, '2026-08-02');
    expect(second?.text, isNot(first?.text));
    expect(receivedHistory, contains(first?.text));
  });

  test('生成失败时回退到最近一次内容且不伪装成今日内容', () async {
    final store = _MemoryDailyEncouragementStore();
    await store.write(
      DailyEncouragementV2(
        dateKey: '2026-07-31',
        text: '昨天留下的温柔，今天也仍然有效。',
        createdAt: DateTime.utc(2026, 7, 31),
      ),
    );
    final coordinator = DailyEncouragementCoordinatorV2(
      store: store,
      clock: () => DateTime(2026, 8, 1),
      generate: ({required dateKey, required recentTexts}) async {
        throw Exception('offline');
      },
    );

    final value = await coordinator.loadToday();

    expect(value?.dateKey, '2026-07-31');
    expect(await store.read('2026-08-01'), isNull);
  });

  test('并发加载只发出一次生成请求', () async {
    final completer = Completer<DailyEncouragementDraftV2>();
    var requests = 0;
    final coordinator = DailyEncouragementCoordinatorV2(
      store: _MemoryDailyEncouragementStore(),
      clock: () => DateTime(2026, 8, 1),
      generate: ({required dateKey, required recentTexts}) {
        requests++;
        return completer.future;
      },
    );

    final first = coordinator.loadToday();
    final second = coordinator.loadToday();
    completer.complete(_draft('每日一句：“给自己留一点空白，也是在认真生活。”'));

    final values = await Future.wait([first, second]);
    expect(requests, 1);
    expect(identical(first, second), isTrue);
    expect(values.first?.text, '给自己留一点空白，也是在认真生活。');
  });

  test('本地存储可恢复内容并只保留最近 30 天', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesDailyEncouragementStoreV2();
    for (var day = 1; day <= 31; day++) {
      final date = DateTime.utc(2026, 7, day);
      await store.write(
        DailyEncouragementV2(
          dateKey: DailyEncouragementCoordinatorV2.keyFor(date),
          text: '第 $day 天',
          createdAt: date,
        ),
      );
    }

    final restored = SharedPreferencesDailyEncouragementStoreV2();
    expect(await restored.read('2026-07-01'), isNull);
    expect((await restored.recent(limit: 40)), hasLength(30));
    expect((await restored.read('2026-07-31'))?.text, '第 31 天');
  });

  test('本地存储保留作者、出处与来源', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesDailyEncouragementStoreV2();
    await store.write(
      DailyEncouragementV2(
        dateKey: '2026-08-01',
        text: '行到水穷处，坐看云起时。',
        createdAt: DateTime.utc(2026, 8, 1),
        author: '王维',
        work: '终南别业',
        provider: '今日诗词',
        sourceUrl: 'https://www.jinrishici.com',
      ),
    );

    final restored = await store.read('2026-08-01');
    expect(restored?.attribution, '王维 · 《终南别业》');
    expect(restored?.provider, '今日诗词');
    expect(restored?.sourceUrl, 'https://www.jinrishici.com');
  });
}

DailyEncouragementDraftV2 _draft(String text) =>
    DailyEncouragementDraftV2(text: text);

class _MemoryDailyEncouragementStore implements DailyEncouragementStoreV2 {
  final Map<String, DailyEncouragementV2> values = {};

  @override
  Future<DailyEncouragementV2?> read(String dateKey) async => values[dateKey];

  @override
  Future<List<DailyEncouragementV2>> recent({int limit = 14}) async {
    final result = values.values.toList()
      ..sort((a, b) => b.dateKey.compareTo(a.dateKey));
    return result.take(limit).toList(growable: false);
  }

  @override
  Future<void> write(DailyEncouragementV2 value) async {
    values[value.dateKey] = value;
  }
}
