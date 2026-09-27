import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/self_read_model_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/repositories/self_read_repository_v2.dart';
import 'package:my_new_diary/features/self_engine/presentation/self_page_v2.dart';

void main() {
  testWidgets('distinguishes disabled and enabled empty states', (
    tester,
  ) async {
    final repository = _MemorySelfReadRepository();
    await _pumpSelf(tester, repository: repository, enabled: false);
    expect(find.text('Self Engine 尚未启用'), findsOneWidget);
    expect(find.text('这里还没有可以展示的线索。'), findsOneWidget);

    await _pumpSelf(tester, repository: repository, enabled: true);
    expect(find.text('Self Engine 尚未启用'), findsNothing);
    expect(find.text('还没有形成明显的长期线索。'), findsOneWidget);
  });

  testWidgets('renders list, opens detail, and traces evidence to Diary', (
    tester,
  ) async {
    final repository = _MemorySelfReadRepository(
      threads: [_summary()],
      detail: SelfThreadDetailV2(
        summary: _summary(),
        evidence: [
          SelfThreadEvidenceV2(
            atomId: 'atom-2',
            diaryId: 'diary-2',
            occurredAt: _february,
            statement: '跑步后焦虑有所减轻',
            sourceQuote: '今晚跑完步，焦虑减轻了一些。',
          ),
          SelfThreadEvidenceV2(
            atomId: 'atom-1',
            diaryId: 'diary-1',
            occurredAt: _january,
            statement: '跑步后思绪变得安静',
            sourceQuote: '跑步之后脑子安静了很多。',
          ),
        ],
      ),
    );
    String? openedDiary;
    await _pumpSelf(
      tester,
      repository: repository,
      enabled: true,
      onOpenDiary: (id) async => openedDiary = id,
    );

    expect(find.text('跑步与情绪恢复'), findsOneWidget);
    expect(find.text('2026.01 — 02 · 2 篇记录'), findsOneWidget);
    await tester.tap(find.text('跑步与情绪恢复'));
    await tester.pumpAndSettle();

    expect(find.text('记录中的片段'), findsOneWidget);
    expect(find.text('跑步后焦虑有所减轻'), findsOneWidget);
    expect(find.text('“今晚跑完步，焦虑减轻了一些。”'), findsOneWidget);
    await tester.tap(find.text('查看原日记').first);
    await tester.pumpAndSettle();
    expect(openedDiary, 'diary-2');
  });

  testWidgets('long multilingual content survives large text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemorySelfReadRepository(
      threads: [
        _summary(
          title: '这是一个很长很长的中文线索标题 with English and emoji 🌙🌱',
          description: '描述也可能很长，需要在首页克制地截断，同时不能造成任何布局溢出。' * 3,
        ),
      ],
    );
    await _pumpSelf(
      tester,
      repository: repository,
      enabled: true,
      textScaler: const TextScaler.linear(2),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('这是一个很长很长'), findsOneWidget);
  });

  testWidgets('shows quiet processing and incomplete states', (tester) async {
    await _pumpSelf(
      tester,
      repository: _MemorySelfReadRepository(
        state: const SelfEngineReadStateV2(
          hasLiveWork: true,
          hasFailedWork: false,
        ),
      ),
      enabled: true,
    );
    expect(find.text('正在整理最近的记录…'), findsOneWidget);

    await _pumpSelf(
      tester,
      repository: _MemorySelfReadRepository(
        state: const SelfEngineReadStateV2(
          hasLiveWork: false,
          hasFailedWork: true,
        ),
      ),
      enabled: true,
    );
    expect(find.text('有些记录暂时还没整理完成。'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} theme smoke test', (tester) async {
      final repository = _MemorySelfReadRepository(threads: [_summary()]);
      await _pumpSelf(
        tester,
        repository: repository,
        enabled: true,
        brightness: brightness,
      );
      expect(find.text('Self'), findsOneWidget);
      expect(find.text('跑步与情绪恢复'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('opening and refreshing Self performs read-only queries', (
    tester,
  ) async {
    final repository = _MemorySelfReadRepository();
    var settingsReads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelfPageV2(
            repository: repository,
            loadEnabled: () async {
              settingsReads++;
              return true;
            },
            onOpenDiary: (_) async {},
            onOpenSettings: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.overviewReads, 1);
    expect(repository.stateReads, 1);
    expect(repository.detailReads, 0);
    expect(settingsReads, 1);
  });
}

final _january = DateTime.utc(2026, 1, 31);
final _february = DateTime.utc(2026, 2, 20);

SelfThreadSummaryV2 _summary({
  String title = '跑步与情绪恢复',
  String description = '记录跑步之后情绪与思绪的变化。',
}) => SelfThreadSummaryV2(
  id: 'running',
  title: title,
  description: description,
  firstSeen: _january,
  lastSeen: _february,
  distinctDiaryCount: 2,
  evidenceCount: 2,
);

Future<void> _pumpSelf(
  WidgetTester tester, {
  required _MemorySelfReadRepository repository,
  required bool enabled,
  Brightness brightness = Brightness.light,
  TextScaler textScaler = TextScaler.noScaling,
  Future<void> Function(String)? onOpenDiary,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness, useMaterial3: true),
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(
          body: SelfPageV2(
            repository: repository,
            loadEnabled: () async => enabled,
            onOpenDiary: onOpenDiary ?? (_) async {},
            onOpenSettings: () async {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _MemorySelfReadRepository implements SelfReadRepositoryV2 {
  _MemorySelfReadRepository({
    this.threads = const [],
    this.detail,
    this.state = const SelfEngineReadStateV2(
      hasLiveWork: false,
      hasFailedWork: false,
    ),
  });

  final List<SelfThreadSummaryV2> threads;
  final SelfThreadDetailV2? detail;
  final SelfEngineReadStateV2 state;
  int overviewReads = 0;
  int detailReads = 0;
  int stateReads = 0;

  @override
  Future<List<SelfThreadSummaryV2>> getActiveThreads() async {
    overviewReads++;
    return threads;
  }

  @override
  Future<SelfEngineReadStateV2> getSelfEngineState() async {
    stateReads++;
    return state;
  }

  @override
  Future<SelfThreadDetailV2?> getThreadDetail(String threadId) async {
    detailReads++;
    return detail;
  }
}
