// file: lib/analysis_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:word_cloud/word_cloud.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart'; // VVV 1. 导入 shared_preferences VVV
import 'diary_service.dart';

// AnalysisPage 类保持不变
class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}


// VVV 将整个 _AnalysisPageState 类替换为以下内容 VVV
class _AnalysisPageState extends State<AnalysisPage> {
  // State for date range selection
  DateTimeRange? _selectedDateRange;
  // State for mood chart
  Map<String, int> _moodCounts = {};
  int _totalEntriesInDateRange = 0;
  // State for word cloud
  List<Map> _wordCloudData = [];

  // State for heatmap
  Map<DateTime, int> _activityData = {};
  DateTime? _selectedHeatmapDate;

  // Data maps
  final Map<String, Map<String, dynamic>> moodDetails = {
    '1': {'name': '特别开心', 'color': Colors.amber[600]!},
    '2': {'name': '很开心', 'color': Colors.orange[500]!},
    '3': {'name': '有点开心', 'color': Colors.yellow[600]!},
    '4': {'name': '一般', 'color': Colors.grey[500]!},
    '5': {'name': '有点伤心', 'color': Colors.lightBlue[400]!},
    '6': {'name': '伤心', 'color': Colors.blue[600]!},
    '7': {'name': '很伤心', 'color': Colors.indigo[400]!},
    '8': {'name': '崩溃', 'color': Colors.deepPurple[700]!},
    '0': {'name': '生病', 'color': Colors.teal[400]!},
  };
  // 默认停用词现在作为基础
  final Set<String> _defaultStopWords = const {
    '的', '了', '我', '你', '他', '她', '它', '我们', '你们', '他们',
    '是', '在', '有', '也', '还', '就', '都', '不', '和', '与', '或',
    '一个', '一些', '这个', '那个', '这', '那', '被', '把', '会', '能',
    '吗', '吧', '呢', '啊', '哦', '嗯', '!', '?', '.', ',', '，', '。',
    '：', '“', '”', '（', '）', '《', '》', ' '
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchAndAnalyzeData();
    });
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDateRange,
      firstDate: DateTime(2022),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
      _fetchAndAnalyzeData();
    }
  }

  Future<void> _fetchAndAnalyzeData() async {
    if (!mounted) return;
    final diaryService = context.read<DiaryService>();
    final allEntries = await diaryService.getAllEntriesSorted();

    // Prepare data for heatmap (uses all entries)
    final activityData = _prepareActivityData(allEntries);
    // Filter entries for date-range specific charts
    final List<DiaryEntry> filteredEntries = [];
    if (_selectedDateRange != null) {
      for (var entry in allEntries) {
        if (!entry.date.isBefore(_selectedDateRange!.start) &&
            entry.date.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)))) {
          filteredEntries.add(entry);
        }
      }
    }

    final moodCounts = _prepareMoodData(filteredEntries);
    // VVV 2. 此处增加 await，因为 _generateWordCloudData 变为异步 VVV
    final wordCloudData = await _generateWordCloudData(filteredEntries);

    setState(() {
      _activityData = activityData;
      _moodCounts = moodCounts;
      _totalEntriesInDateRange = filteredEntries.length;
      _wordCloudData = wordCloudData;
    });
  }

  Map<DateTime, int> _prepareActivityData(List<DiaryEntry> allEntries) {
    final Map<DateTime, int> datasets = {};
    for (var entry in allEntries) {
      final dateOnly = DateTime(entry.date.year, entry.date.month, entry.date.day);
      datasets.update(dateOnly, (value) => value + 1, ifAbsent: () => 1);
    }
    return datasets;
  }

  Map<String, int> _prepareMoodData(List<DiaryEntry> filteredEntries) {
    final Map<String, int> counts = {};
    for (var entry in filteredEntries) {
      if (entry.mood != null && moodDetails.containsKey(entry.mood)) {
        counts.update(entry.mood!, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  // VVV 3. 这是核心修改：此方法变为异步，并加载自定义停用词 VVV
  Future<List<Map>> _generateWordCloudData(List<DiaryEntry> entries) async {
    // 加载自定义停用词
    final prefs = await SharedPreferences.getInstance();
    final customStopWords = prefs.getStringList('custom_stop_words') ?? [];

    // 合并默认停用词和自定义停用词
    final combinedStopWords = {..._defaultStopWords, ...customStopWords};

    final Map<String, int> wordFrequencies = {};
    final allText = entries.map((e) => e.text).join(' ');
    final words = allText.split(RegExp(r"[^\u4e00-\u9fa5]+"));

    for (var word in words) {
      // 使用合并后的停用词列表进行过滤
      if (word.isNotEmpty && !combinedStopWords.contains(word) && word.length > 1) {
        wordFrequencies.update(word, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    final sortedWords = wordFrequencies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sortedWords.length < 3) return [];
    if (sortedWords.first.value == sortedWords.last.value) return [];

    return sortedWords.take(50).map((e) => {'word': e.key, 'value': e.value}).toList();
  }

  // 所有 build UI 的方法保持不变...
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('统计分析'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildActivityHeatmap(),
          const Divider(height: 48),
          _buildDateRangeSelector(),
          const SizedBox(height: 24),
          _buildMoodChart(),
          const Divider(height: 48),
          _buildWordCloud(),
        ],
      ),
    );
  }

  Widget _buildActivityHeatmap() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('写作热力图', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        // 使用 SingleChildScrollView 包裹 HeatMap，使其可以水平滚动
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true, // 视图默认显示右侧（即当前日期）
          child: HeatMap(
            datasets: _activityData,
            startDate: DateTime.now().subtract(const Duration(days: 364)),
            endDate: DateTime.now(),
            // 增大了格子尺寸和边距，解决拥挤问题
            size: 20.0,
            margin: const EdgeInsets.all(4.0),
            scrollable: false, // 由外部的 SingleChildScrollView 控制滚动
            showColorTip: false,
            // 修复白天模式下格子不可见的问题
            defaultColor: theme.dividerColor.withOpacity(0.1),
            colorsets: {
              1: theme.colorScheme.primary.withOpacity(0.2),
              3: theme.colorScheme.primary.withOpacity(0.4),
              5: theme.colorScheme.primary.withOpacity(0.6),
              7: theme.colorScheme.primary.withOpacity(0.8),
              9: theme.colorScheme.primary,
            },
            onClick: (date) {
              setState(() {
                _selectedHeatmapDate = date;
              });
            },
          ),
        ),
        const SizedBox(height: 16),
        // 点击后显示详情的容器保持不变
        Container(
          height: 50,
          alignment: Alignment.center,
          child: _selectedHeatmapDate != null
              ? Text(
            '${DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(_selectedHeatmapDate!)}: ${_activityData[_selectedHeatmapDate] ?? 0} 篇日记',
            style: theme.textTheme.bodyMedium,
          )
              : Text(
            '点击热力图中的方块查看详情',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekdayLabels() {
    final style = Theme.of(context).textTheme.bodySmall;
    const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: labels.map((label) => Text(label, style: style)).toList(),
    );
  }

  Widget _buildDateRangeSelector() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.calendar_today),
        title: const Text('心情与词云分析时段'),
        subtitle: Text(
          _selectedDateRange == null
              ? '请选择一个时间范围'
              : '${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.start)} - ${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.end)}',
        ),
        trailing: const Icon(Icons.arrow_drop_down),
        onTap: _selectDateRange,
      ),
    );
  }

  Widget _buildMoodChart() {
    final List<PieChartSectionData> sections = _moodCounts.entries.map((entry) {
      final moodInfo = moodDetails[entry.key]!;
      final percentage = (_totalEntriesInDateRange > 0) ? (entry.value / _totalEntriesInDateRange) * 100 : 0.0;
      return PieChartSectionData(
        color: moodInfo['color'],
        value: entry.value.toDouble(),
        title: '${percentage.toStringAsFixed(1)}%',
        radius: 100,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          shadows: [Shadow(color: Colors.black, blurRadius: 2)],
        ),
      );
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('心情分布', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (_moodCounts.isEmpty)
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40.0),
            child: Text('该时段内没有带心情的日记。'),
          ))
        else
          AspectRatio(
            aspectRatio: 1.5,
            child: PieChart(
              PieChartData(
                sections: sections,
                sectionsSpace: 2,
                centerSpaceRadius: 40,
              ),
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: moodDetails.keys.map((moodKey) {
            final moodInfo = moodDetails[moodKey]!;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 16, height: 16, color: moodInfo['color']),
                const SizedBox(width: 8),
                Text(moodInfo['name']),
              ],
            );
          }).toList(),
        )
      ],
    );
  }

  Widget _buildWordCloud() {
    if (_wordCloudData.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('高频词汇', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40.0),
            child: Text('该时段内没有足够的数据生成词云。'),
          )),
        ],
      );
    }

    WordCloudData wcData = WordCloudData(data: _wordCloudData);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('高频词汇', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Container(
          height: 300,
          width: double.infinity,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor)),
          child: WordCloudView(
            data: wcData,
            mapwidth: 500,
            mapheight: 500,
            colorlist: const [
              Colors.blue, Colors.green, Colors.indigo,
              Colors.amber, Colors.deepOrange, Colors.lightBlue,
              Colors.redAccent, Colors.teal
            ],
            shape: WordCloudCircle(radius: 200),
            fontWeight: FontWeight.bold,
            fontFamily: 'MiSans',
          ),
        )
      ],
    );
  }
}