import '../../diary/domain/entities/diary_entry.dart';

class DiaryAnalysisV2 {
  const DiaryAnalysisV2({
    required this.totalEntries,
    required this.totalCharacters,
    required this.activeDays,
    required this.activityByDay,
    required this.moodCounts,
    required this.wordFrequencies,
  });

  final int totalEntries;
  final int totalCharacters;
  final int activeDays;
  final Map<DateTime, int> activityByDay;
  final Map<String, int> moodCounts;
  final Map<String, int> wordFrequencies;
}

class DiaryAnalyzerV2 {
  const DiaryAnalyzerV2();

  static const defaultStopWords = {
    '的',
    '了',
    '我',
    '你',
    '他',
    '她',
    '它',
    '我们',
    '你们',
    '他们',
    '是',
    '在',
    '有',
    '也',
    '还',
    '就',
    '都',
    '不',
    '和',
    '与',
    '或',
    '一个',
    '一些',
    '这个',
    '那个',
    '这',
    '那',
    '被',
    '把',
    '会',
    '能',
    '吗',
    '吧',
    '呢',
    '啊',
    '哦',
    '嗯',
  };

  DiaryAnalysisV2 analyze(
    List<DiaryEntryV2> allEntries, {
    DateTime? from,
    DateTime? to,
    Set<String> customStopWords = const {},
  }) {
    final activity = <DateTime, int>{};
    for (final entry in allEntries) {
      final date = entry.entryDate.toLocal();
      final day = DateTime(date.year, date.month, date.day);
      activity.update(day, (value) => value + 1, ifAbsent: () => 1);
    }

    final entries = allEntries
        .where((entry) {
          final date = entry.entryDate;
          if (from != null && date.isBefore(from)) {
            return false;
          }
          if (to != null && !date.isBefore(to)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    final moods = <String, int>{};
    final words = <String, int>{};
    final stopWords = {...defaultStopWords, ...customStopWords};
    for (final entry in entries) {
      final mood = entry.mood;
      if (mood != null && mood.isNotEmpty) {
        moods.update(mood, (value) => value + 1, ifAbsent: () => 1);
      }
      for (final word in _tokens(entry.body)) {
        if (!stopWords.contains(word)) {
          words.update(word, (value) => value + 1, ifAbsent: () => 1);
        }
      }
    }

    final sortedWords = words.entries.toList()
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        return count == 0 ? a.key.compareTo(b.key) : count;
      });

    return DiaryAnalysisV2(
      totalEntries: entries.length,
      totalCharacters: entries.fold(
        0,
        (sum, entry) => sum + entry.body.runes.length,
      ),
      activeDays: activity.length,
      activityByDay: Map.unmodifiable(activity),
      moodCounts: Map.unmodifiable(moods),
      wordFrequencies: Map.unmodifiable(Map.fromEntries(sortedWords.take(50))),
    );
  }

  Iterable<String> _tokens(String text) sync* {
    final matches = RegExp(
      r'[\u4e00-\u9fff]{2,}|[A-Za-z0-9]{2,}',
    ).allMatches(text.toLowerCase());
    for (final match in matches) {
      final token = match.group(0);
      if (token != null && token.length <= 12) {
        yield token;
      }
    }
  }
}
