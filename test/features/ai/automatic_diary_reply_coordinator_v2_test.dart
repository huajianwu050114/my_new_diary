import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/ai/application/automatic_diary_reply_coordinator_v2.dart';
import 'package:my_new_diary/features/ai/data/ai_configuration_store_v2.dart';
import 'package:my_new_diary/features/ai/data/ai_reply_task_store_v2.dart';
import 'package:my_new_diary/features/ai/domain/ai_reply_task_v2.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';
import 'package:my_new_diary/features/diary/domain/repositories/diary_repository_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const readyConfiguration = AiConfigurationV2(
    enabled: true,
    automaticReply: true,
    hasApiKey: true,
    provider: AiProviderV2.deepSeek,
    model: 'test-model',
  );

  test('生成成功后保存回信并标记 completed', () async {
    final repository = _MemoryRepository(_entry());
    final store = _MemoryTaskStore();
    var requests = 0;
    final coordinator = AutomaticDiaryReplyCoordinatorV2(
      repository: repository,
      taskStore: store,
      loadConfiguration: () async => readyConfiguration,
      generateReply: (_) async {
        requests++;
        return '今天辛苦了。';
      },
    );

    final task = await coordinator.scheduleAndRun(repository.entry);

    expect(task?.status, AiReplyTaskStatusV2.completed);
    expect(requests, 1);
    expect(repository.entry.aiAnalyses.single, '【AI 悄悄话】\n今天辛苦了。');
  });

  test('相同内容不会重复请求', () async {
    final repository = _MemoryRepository(_entry());
    final store = _MemoryTaskStore();
    var requests = 0;
    final coordinator = AutomaticDiaryReplyCoordinatorV2(
      repository: repository,
      taskStore: store,
      loadConfiguration: () async => readyConfiguration,
      generateReply: (_) async {
        requests++;
        return '收到。';
      },
    );

    await coordinator.scheduleAndRun(repository.entry);
    await coordinator.scheduleAndRun(repository.entry);

    expect(requests, 1);
    expect(repository.entry.aiAnalyses, hasLength(1));
  });

  test('失败后按退避时间重试', () async {
    var now = DateTime.utc(2026, 8, 1, 10);
    final repository = _MemoryRepository(_entry());
    final store = _MemoryTaskStore();
    var requests = 0;
    final coordinator = AutomaticDiaryReplyCoordinatorV2(
      repository: repository,
      taskStore: store,
      loadConfiguration: () async => readyConfiguration,
      generateReply: (_) async {
        requests++;
        if (requests == 1) throw Exception('offline');
        return '重试成功。';
      },
      clock: () => now,
    );

    final failed = await coordinator.scheduleAndRun(repository.entry);
    expect(failed?.status, AiReplyTaskStatusV2.failed);
    expect(failed?.attempts, 1);
    expect(failed?.nextAttemptAt, now.add(const Duration(minutes: 1)));

    await coordinator.retryIfNeeded(repository.entry.id);
    expect(requests, 1);

    now = now.add(const Duration(minutes: 1));
    final completed = await coordinator.retryIfNeeded(repository.entry.id);
    expect(completed?.status, AiReplyTaskStatusV2.completed);
    expect(requests, 2);
  });

  test('正文修改后使用新指纹生成新回信', () async {
    final repository = _MemoryRepository(_entry());
    final store = _MemoryTaskStore();
    var requests = 0;
    final coordinator = AutomaticDiaryReplyCoordinatorV2(
      repository: repository,
      taskStore: store,
      loadConfiguration: () async => readyConfiguration,
      generateReply: (entry) async => '回应 ${++requests}：${entry.body}',
    );

    await coordinator.scheduleAndRun(repository.entry);
    repository.entry = repository.entry.copyWith(body: '修改后的正文');
    await repository.save(repository.entry);
    await coordinator.scheduleAndRun(repository.entry);

    expect(requests, 2);
    expect(repository.entry.aiAnalyses, hasLength(2));
    expect(repository.entry.aiAnalyses.last, contains('修改后的正文'));
  });

  test('仅修改收藏状态不会改变内容指纹', () {
    final entry = _entry();
    expect(
      AutomaticDiaryReplyCoordinatorV2.contentFingerprint(entry),
      AutomaticDiaryReplyCoordinatorV2.contentFingerprint(
        entry.copyWith(isFavorite: true),
      ),
    );
  });

  test('任务状态可从本地偏好恢复', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesAiReplyTaskStoreV2();
    final task = AiReplyTaskV2(
      entryId: 'persisted',
      contentFingerprint: 'fingerprint',
      status: AiReplyTaskStatusV2.failed,
      attempts: 2,
      updatedAt: DateTime.utc(2026, 8, 1, 10),
      nextAttemptAt: DateTime.utc(2026, 8, 1, 10, 5),
    );

    await store.write(task);
    final restored = await SharedPreferencesAiReplyTaskStoreV2().read(
      task.entryId,
    );

    expect(restored?.status, AiReplyTaskStatusV2.failed);
    expect(restored?.attempts, 2);
    expect(restored?.nextAttemptAt, task.nextAttemptAt);
  });
}

DiaryEntryV2 _entry() {
  final now = DateTime.utc(2026, 8, 1, 9);
  return DiaryEntryV2(
    id: 'entry-1',
    body: '今天完成了一件小事',
    entryDate: now,
    createdAt: now,
    updatedAt: now,
    mood: '😊',
    tags: const ['生活'],
  );
}

class _MemoryTaskStore implements AiReplyTaskStoreV2 {
  final Map<String, AiReplyTaskV2> values = {};

  @override
  Future<void> delete(String entryId) async => values.remove(entryId);

  @override
  Future<AiReplyTaskV2?> read(String entryId) async => values[entryId];

  @override
  Future<void> write(AiReplyTaskV2 task) async {
    values[task.entryId] = task;
  }
}

class _MemoryRepository implements DiaryRepositoryV2 {
  _MemoryRepository(this.entry);

  DiaryEntryV2 entry;

  @override
  Future<DiaryEntryV2?> getById(String id) async =>
      id == entry.id ? entry : null;

  @override
  Future<void> save(DiaryEntryV2 entry) async => this.entry = entry;

  @override
  Stream<List<DiaryEntryV2>> watchEntries({
    DiaryQuery query = const DiaryQuery(),
  }) => Stream.value([entry]);

  @override
  Future<void> deletePermanently(String id) async {}

  @override
  Future<void> moveToTrash(String id, {required DateTime deletedAt}) async {
    entry = entry.copyWith(deletedAt: deletedAt);
  }

  @override
  Future<void> restore(String id) async =>
      entry = entry.copyWith(restore: true);

  @override
  Future<void> setFavorite(String id, {required bool isFavorite}) async {
    entry = entry.copyWith(isFavorite: isFavorite);
  }
}
