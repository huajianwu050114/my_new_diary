import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';

import '../../diary/domain/entities/diary_entry.dart';
import '../../diary/presentation/widgets/diary_mood_text_v2.dart';
import '../../diary/domain/repositories/diary_repository_v2.dart';
import '../data/stop_words_store_v2.dart';
import '../domain/diary_analysis_v2.dart';
import 'stop_words_page_v2.dart';

class AnalysisPageV2 extends StatefulWidget {
  const AnalysisPageV2({required this.repository, super.key});

  final DiaryRepositoryV2 repository;

  @override
  State<AnalysisPageV2> createState() => _AnalysisPageV2State();
}

class _AnalysisPageV2State extends State<AnalysisPageV2> {
  final _stopWordsStore = StopWordsStoreV2();
  DateTimeRange? _range;
  Set<String> _stopWords = const {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: DateTime(now.year, 1), end: now);
    _loadStopWords();
  }

  Future<void> _loadStopWords() async {
    final words = await _stopWordsStore.load();
    if (mounted) {
      setState(() => _stopWords = words);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('统计分析'),
        actions: [
          IconButton(
            tooltip: '停用词',
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => StopWordsPageV2(store: _stopWordsStore),
                ),
              );
              await _loadStopWords();
            },
            icon: const Icon(Icons.filter_alt_outlined),
          ),
        ],
      ),
      body: StreamBuilder<List<DiaryEntryV2>>(
        stream: widget.repository.watchEntries(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final range = _range;
          final analysis = const DiaryAnalyzerV2().analyze(
            snapshot.data!,
            from: range?.start,
            to: range?.end.add(const Duration(days: 1)),
            customStopWords: _stopWords,
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Summary(analysis: analysis),
              const SizedBox(height: 24),
              Text('写作热力图', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: HeatMap(
                  datasets: analysis.activityByDay,
                  startDate: DateTime.now().subtract(const Duration(days: 364)),
                  endDate: DateTime.now(),
                  size: 16,
                  margin: const EdgeInsets.all(3),
                  scrollable: false,
                  showColorTip: false,
                  defaultColor: Theme.of(context).colorScheme.surfaceContainer,
                  colorsets: {
                    1: Theme.of(context).colorScheme.primaryContainer,
                    2: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.45),
                    4: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.7),
                    6: Theme.of(context).colorScheme.primary,
                  },
                ),
              ),
              const SizedBox(height: 28),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.date_range_outlined),
                  title: const Text('分析时间范围'),
                  subtitle: Text(_rangeText()),
                  onTap: _pickRange,
                ),
              ),
              const SizedBox(height: 24),
              _MoodDistribution(analysis: analysis),
              const SizedBox(height: 28),
              _WordCloud(analysis: analysis),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _range = picked);
    }
  }

  String _rangeText() {
    final range = _range!;
    return '${range.start.year}/${range.start.month}/${range.start.day} - '
        '${range.end.year}/${range.end.month}/${range.end.day}';
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.analysis});

  final DiaryAnalysisV2 analysis;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Metric(label: '日记', value: '${analysis.totalEntries}'),
        _Metric(label: '活跃天数', value: '${analysis.activeDays}'),
        _Metric(label: '总字数', value: '${analysis.totalCharacters}'),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoodDistribution extends StatelessWidget {
  const _MoodDistribution({required this.analysis});

  final DiaryAnalysisV2 analysis;

  @override
  Widget build(BuildContext context) {
    final maximum = analysis.moodCounts.values.fold(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('心情分布', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (analysis.moodCounts.isEmpty)
          const Text('这个时间范围内还没有心情记录')
        else
          ...analysis.moodCounts.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  DiaryMoodTextV2(mood: entry.key, maxWidth: 104, maxLines: 2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: maximum == 0 ? 0 : entry.value / maximum,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${entry.value}'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _WordCloud extends StatelessWidget {
  const _WordCloud({required this.analysis});

  final DiaryAnalysisV2 analysis;

  @override
  Widget build(BuildContext context) {
    final words = analysis.wordFrequencies.entries.toList();
    final maximum = words.isEmpty ? 1 : words.first.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('高频词云', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (words.isEmpty)
          const Text('当前内容不足以生成词云')
        else
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: words
                .map((entry) {
                  final scale = entry.value / maximum;
                  return Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 14 + scale * 20,
                      color: Color.lerp(
                        Theme.of(context).colorScheme.secondary,
                        Theme.of(context).colorScheme.primary,
                        scale,
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
      ],
    );
  }
}
