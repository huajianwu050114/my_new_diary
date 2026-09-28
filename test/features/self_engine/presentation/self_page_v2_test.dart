import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/self_engine/application/ports/self_engine_availability_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/entities/self_read_model_v2.dart';
import 'package:my_new_diary/features/self_engine/domain/repositories/self_read_repository_v2.dart';
import 'package:my_new_diary/features/self_engine/presentation/self_page_v2.dart';

void main() {
  testWidgets('distinguishes disabled and enabled empty states', (
    tester,
  ) async {
    final repository = _MemorySelfReadRepository();
    await _pumpSelf(
      tester,
      repository: repository,
      availability: SelfEngineAvailabilityStatusV2.disabled,
    );
    expect(find.text('Self Engine 尚未启用'), findsOneWidget);
    expect(find.text('这里还没有可以展示的线索。'), findsOneWidget);

    await _pumpSelf(tester, repository: repository);
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
    );
    expect(find.text('有些记录暂时还没整理完成。'), findsOneWidget);
  });

  testWidgets(
    'unavailable engine keeps historical Threads visible without processing',
    (tester) async {
      final repository = _MemorySelfReadRepository(
        threads: [_summary()],
        state: const SelfEngineReadStateV2(
          hasLiveWork: true,
          hasFailedWork: false,
        ),
      );
      await _pumpSelf(
        tester,
        repository: repository,
        availability: SelfEngineAvailabilityStatusV2.unavailable,
      );

      expect(find.text('Self Engine 当前无法整理新记录，已有线索仍可查看。'), findsOneWidget);
      expect(find.text('正在整理最近的记录…'), findsNothing);
      expect(find.text('跑步与情绪恢复'), findsOneWidget);

      await _pumpSelf(
        tester,
        repository: repository,
        availability: SelfEngineAvailabilityStatusV2.disabled,
      );
      expect(find.text('Self Engine 当前已暂停，已有线索仍可查看。'), findsOneWidget);
      expect(find.text('Self Engine 尚未启用'), findsNothing);
    },
  );

  testWidgets(
    'settings unavailable-to-available transition wakes once then refreshes',
    (tester) async {
      final repository = _MemorySelfReadRepository();
      var availability = SelfEngineAvailabilityStatusV2.unavailable;
      var runnerCalls = 0;
      await _pumpSelf(
        tester,
        repository: repository,
        loadAvailability: () async => availability,
        onOpenSettings: () async {
          availability = SelfEngineAvailabilityStatusV2.available;
        },
        onSelfEngineBecameAvailable: () async {
          runnerCalls++;
        },
      );

      expect(runnerCalls, 0);
      expect(repository.overviewReads, 1);
      await tester.tap(find.text('前往设置'));
      await tester.pumpAndSettle();

      expect(runnerCalls, 1);
      expect(repository.overviewReads, 3);
      expect(find.text('还没有形成明显的长期线索。'), findsOneWidget);
    },
  );

  testWidgets('settings return without availability transition does not wake', (
    tester,
  ) async {
    final repository = _MemorySelfReadRepository();
    var runnerCalls = 0;
    await _pumpSelf(
      tester,
      repository: repository,
      availability: SelfEngineAvailabilityStatusV2.unavailable,
      onOpenSettings: () async {},
      onSelfEngineBecameAvailable: () async {
        runnerCalls++;
      },
    );

    await tester.tap(find.text('前往设置'));
    await tester.pumpAndSettle();

    expect(runnerCalls, 0);
    expect(repository.overviewReads, 2);
  });

  testWidgets('loads bounded overview pages without duplicate requests', (
    tester,
  ) async {
    final repository = _MemorySelfReadRepository(
      threads: List.generate(
        55,
        (index) => _summary(id: 'thread-$index', title: 'Thread $index'),
      ),
    );
    await _pumpSelf(tester, repository: repository);

    expect(repository.overviewRequests, [(50, 0)]);
    await tester.scrollUntilVisible(
      find.text('查看更多'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pump();
    await tester.tap(find.text('查看更多'));
    await tester.pumpAndSettle();

    expect(repository.overviewRequests, [(50, 0), (50, 50)]);
    expect(find.text('查看更多'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Thread 54'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Thread 54'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} theme smoke test', (tester) async {
      final repository = _MemorySelfReadRepository(threads: [_summary()]);
      await _pumpSelf(tester, repository: repository, brightness: brightness);
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
    var runnerCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelfPageV2(
            repository: repository,
            loadAvailability: () async {
              settingsReads++;
              return SelfEngineAvailabilityStatusV2.available;
            },
            onOpenDiary: (_) async {},
            onOpenSettings: () async {},
            onSelfEngineBecameAvailable: () async {
              runnerCalls++;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.overviewReads, 1);
    expect(repository.stateReads, 1);
    expect(repository.detailReads, 0);
    expect(settingsReads, 1);
    expect(runnerCalls, 0);

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(repository.overviewReads, 2);
    expect(repository.stateReads, 2);
    expect(runnerCalls, 0);
  });
}

final _january = DateTime.utc(2026, 1, 31);
final _february = DateTime.utc(2026, 2, 20);

SelfThreadSummaryV2 _summary({
  String id = 'running',
  String title = '跑步与情绪恢复',
  String description = '记录跑步之后情绪与思绪的变化。',
}) => SelfThreadSummaryV2(
  id: id,
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
  SelfEngineAvailabilityStatusV2 availability =
      SelfEngineAvailabilityStatusV2.available,
  Brightness brightness = Brightness.light,
  TextScaler textScaler = TextScaler.noScaling,
  Future<void> Function(String)? onOpenDiary,
  Future<SelfEngineAvailabilityStatusV2> Function()? loadAvailability,
  Future<void> Function()? onOpenSettings,
  Future<void> Function()? onSelfEngineBecameAvailable,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness, useMaterial3: true),
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(
          body: SelfPageV2(
            repository: repository,
            loadAvailability: loadAvailability ?? () async => availability,
            onOpenDiary: onOpenDiary ?? (_) async {},
            onOpenSettings: onOpenSettings ?? () async {},
            onSelfEngineBecameAvailable: onSelfEngineBecameAvailable,
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
  final List<(int, int)> overviewRequests = [];

  @override
  Future<List<SelfThreadSummaryV2>> getActiveThreads({
    int limit = 50,
    int offset = 0,
  }) async {
    overviewReads++;
    overviewRequests.add((limit, offset));
    return threads.skip(offset).take(limit).toList(growable: false);
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
