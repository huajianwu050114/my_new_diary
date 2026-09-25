import '../data/daily_encouragement_store_v2.dart';
import '../domain/daily_encouragement_v2.dart';

typedef DailyEncouragementGeneratorV2 =
    Future<DailyEncouragementDraftV2> Function({
      required String dateKey,
      required List<String> recentTexts,
    });

class DailyEncouragementCoordinatorV2 {
  DailyEncouragementCoordinatorV2({
    required DailyEncouragementStoreV2 store,
    required DailyEncouragementGeneratorV2 generate,
    DateTime Function()? clock,
  }) : _store = store,
       _generate = generate,
       _clock = clock ?? DateTime.now;

  final DailyEncouragementStoreV2 _store;
  final DailyEncouragementGeneratorV2 _generate;
  final DateTime Function() _clock;
  Future<DailyEncouragementV2?>? _running;

  Future<DailyEncouragementV2?> loadToday() {
    return _running ??= _loadToday().whenComplete(() => _running = null);
  }

  Future<DailyEncouragementV2?> _loadToday() async {
    final now = _clock();
    final dateKey = keyFor(now);
    final cached = await _store.read(dateKey);
    if (cached != null) return cached;

    final recent = await _store.recent(limit: 14);
    try {
      final draft = await _generate(
        dateKey: dateKey,
        recentTexts: recent.map((value) => value.text).toList(),
      );
      final generated = _clean(draft.text);
      if (generated.isEmpty) return recent.firstOrNull;
      final value = DailyEncouragementV2(
        dateKey: dateKey,
        text: generated,
        createdAt: now.toUtc(),
        author: draft.author,
        work: draft.work,
        provider: draft.provider,
        sourceUrl: draft.sourceUrl,
      );
      await _store.write(value);
      return value;
    } catch (_) {
      return recent.firstOrNull;
    }
  }

  static String keyFor(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  static String _clean(String value) {
    var text = value.trim();
    text = text.replaceFirst(RegExp(r'^(今日小笺|每日一句)\s*[:：]\s*'), '');
    if ((text.startsWith('“') && text.endsWith('”')) ||
        (text.startsWith('"') && text.endsWith('"'))) {
      text = text.substring(1, text.length - 1).trim();
    }
    return text;
  }
}
