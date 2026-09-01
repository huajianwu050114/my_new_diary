import '../../diary/domain/entities/diary_entry.dart';
import '../../diary/domain/repositories/diary_repository_v2.dart';
import '../data/ai_configuration_store_v2.dart';
import '../data/ai_reply_task_store_v2.dart';
import '../domain/ai_reply_task_v2.dart';

typedef AiReplyGeneratorV2 = Future<String> Function(DiaryEntryV2 entry);
typedef AiConfigurationLoaderV2 = Future<AiConfigurationV2> Function();

class AutomaticDiaryReplyCoordinatorV2 {
  AutomaticDiaryReplyCoordinatorV2({
    required DiaryRepositoryV2 repository,
    required AiReplyTaskStoreV2 taskStore,
    required AiConfigurationLoaderV2 loadConfiguration,
    required AiReplyGeneratorV2 generateReply,
    DateTime Function()? clock,
  }) : _repository = repository,
       _taskStore = taskStore,
       _loadConfiguration = loadConfiguration,
       _generateReply = generateReply,
       _clock = clock ?? DateTime.now;

  static const replyPrefix = '【AI 悄悄话】';
  static const _staleGeneratingAfter = Duration(minutes: 2);
  static const _retryDelays = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 30),
    Duration(hours: 2),
    Duration(hours: 12),
  ];

  final DiaryRepositoryV2 _repository;
  final AiReplyTaskStoreV2 _taskStore;
  final AiConfigurationLoaderV2 _loadConfiguration;
  final AiReplyGeneratorV2 _generateReply;
  final DateTime Function() _clock;
  final Set<String> _running = {};

  Future<AiReplyTaskV2> schedule(DiaryEntryV2 entry) async {
    final now = _clock().toUtc();
    final fingerprint = contentFingerprint(entry);
    final existing = await _taskStore.read(entry.id);
    if (existing != null && existing.contentFingerprint == fingerprint) {
      return existing;
    }

    final hasLegacyReply = existing == null && _hasReply(entry);
    final task = AiReplyTaskV2(
      entryId: entry.id,
      contentFingerprint: fingerprint,
      status: hasLegacyReply
          ? AiReplyTaskStatusV2.completed
          : AiReplyTaskStatusV2.pending,
      attempts: 0,
      updatedAt: now,
    );
    await _taskStore.write(task);
    return task;
  }

  Future<AiReplyTaskV2?> scheduleAndRun(DiaryEntryV2 entry) async {
    await schedule(entry);
    return runIfDue(entry.id);
  }

  Future<AiReplyTaskV2?> retryIfNeeded(String entryId) => runIfDue(entryId);

  Future<void> markCompleted(DiaryEntryV2 entry) async {
    await _taskStore.write(
      AiReplyTaskV2(
        entryId: entry.id,
        contentFingerprint: contentFingerprint(entry),
        status: AiReplyTaskStatusV2.completed,
        attempts: 0,
        updatedAt: _clock().toUtc(),
      ),
    );
  }

  Future<AiReplyTaskV2?> runIfDue(String entryId) async {
    if (!_running.add(entryId)) return _taskStore.read(entryId);
    try {
      final entry = await _repository.getById(entryId);
      if (entry == null || entry.isDeleted) {
        await _taskStore.delete(entryId);
        return null;
      }

      var task = await schedule(entry);
      final now = _clock().toUtc();
      if (task.status == AiReplyTaskStatusV2.completed) return task;
      if (task.status == AiReplyTaskStatusV2.generating &&
          now.difference(task.updatedAt) < _staleGeneratingAfter) {
        return task;
      }
      if (task.status == AiReplyTaskStatusV2.failed && !task.isDue(now)) {
        return task;
      }

      final configuration = await _loadConfiguration();
      if (!configuration.ready || !configuration.automaticReply) return task;

      task = task.copyWith(
        status: AiReplyTaskStatusV2.generating,
        updatedAt: now,
        clearNextAttemptAt: true,
      );
      await _taskStore.write(task);
      try {
        final replyCountBeforeRequest = _replyCount(entry);
        final reply = (await _generateReply(entry)).trim();
        if (reply.isEmpty) throw StateError('AI returned an empty reply');
        final latest = await _repository.getById(entryId);
        if (latest == null || latest.isDeleted) {
          await _taskStore.delete(entryId);
          return null;
        }
        if (contentFingerprint(latest) != task.contentFingerprint) {
          final rescheduled = await schedule(latest);
          return rescheduled;
        }
        if (_replyCount(latest) <= replyCountBeforeRequest) {
          await _repository.save(
            latest.copyWith(
              aiAnalyses: [...latest.aiAnalyses, '$replyPrefix\n$reply'],
            ),
          );
        }
        final completed = task.copyWith(
          status: AiReplyTaskStatusV2.completed,
          updatedAt: _clock().toUtc(),
          clearNextAttemptAt: true,
        );
        await _taskStore.write(completed);
        return completed;
      } catch (_) {
        final attempts = task.attempts + 1;
        final delay =
            _retryDelays[(attempts - 1).clamp(0, _retryDelays.length - 1)];
        final failed = task.copyWith(
          status: AiReplyTaskStatusV2.failed,
          attempts: attempts,
          updatedAt: _clock().toUtc(),
          nextAttemptAt: _clock().toUtc().add(delay),
        );
        await _taskStore.write(failed);
        return failed;
      }
    } finally {
      _running.remove(entryId);
    }
  }

  static String contentFingerprint(DiaryEntryV2 entry) {
    final source = [
      entry.body.trim(),
      entry.mood ?? '',
      ...entry.tags.map((tag) => tag.trim()).toList()..sort(),
      entry.entryDate.toUtc().toIso8601String(),
    ].join('\u001f');
    var hash = 0xcbf29ce484222325;
    for (final unit in source.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static bool _hasReply(DiaryEntryV2 entry) => entry.aiAnalyses.any(
    (analysis) =>
        analysis.startsWith(replyPrefix) || analysis.startsWith('【AI 总结】'),
  );

  static int _replyCount(DiaryEntryV2 entry) => entry.aiAnalyses
      .where(
        (analysis) =>
            analysis.startsWith(replyPrefix) || analysis.startsWith('【AI 总结】'),
      )
      .length;
}
