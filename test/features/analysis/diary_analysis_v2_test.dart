import 'package:flutter_test/flutter_test.dart';

import 'package:my_new_diary/features/analysis/domain/diary_analysis_v2.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';

void main() {
  test('calculates activity, moods, characters, and filtered words', () {
    final entries = [
      _entry(
        id: '1',
        body: '今天散步 今天散步',
        mood: '😊',
        date: DateTime(2026, 7, 1),
      ),
      _entry(id: '2', body: '今天读书', mood: '😌', date: DateTime(2026, 7, 1)),
      _entry(
        id: '3',
        body: 'Weekend walk',
        mood: '😊',
        date: DateTime(2026, 7, 2),
      ),
    ];

    final analysis = const DiaryAnalyzerV2().analyze(
      entries,
      customStopWords: const {'今天读书'},
    );

    expect(analysis.totalEntries, 3);
    expect(analysis.activeDays, 2);
    expect(analysis.activityByDay[DateTime(2026, 7, 1)], 2);
    expect(analysis.moodCounts['😊'], 2);
    expect(analysis.wordFrequencies, isNot(contains('今天读书')));
    expect(analysis.wordFrequencies, contains('weekend'));
  });

  test('applies a half-open date range', () {
    final entries = [
      _entry(id: '1', body: 'one', date: DateTime(2026, 7, 1)),
      _entry(id: '2', body: 'two', date: DateTime(2026, 8, 1)),
    ];

    final analysis = const DiaryAnalyzerV2().analyze(
      entries,
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 8, 1),
    );

    expect(analysis.totalEntries, 1);
  });
}

DiaryEntryV2 _entry({
  required String id,
  required String body,
  required DateTime date,
  String? mood,
}) {
  return DiaryEntryV2(
    id: id,
    body: body,
    entryDate: date,
    createdAt: date,
    updatedAt: date,
    mood: mood,
  );
}
