// file: libs/analysis_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:word_cloud/word_cloud.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart'; // VVV 1. 导入 shared_preferences VVV
import 'diary_service.dart';
import 'package:my_new_diary/diary_model.dart';

// AnalysisPage 类保持不变
class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}


// VVV 将整个 _AnalysisPageState 类替换为以下内容 VVV
// 文件位置: libs/analysis_page.dart

class _AnalysisPageState extends State<AnalysisPage> {
  DateTimeRange? _selectedDateRange;

  // 为新图表准备的状态变量
  Map<DateTime, int> _moodCalendarData = {};
  List<FlSpot> _moodLineChartData = [];
  DateTime? _minDate;
  DateTime? _maxDate;
  List<Map> _wordCloudData = [];
  Map<DateTime, int> _activityData = {};
  DateTime? _selectedHeatmapDate;
  String? _selectedCalendarDateInfo;

  // 心情代码到 “名称” 和 “颜色” 的映射
  final Map<String, Map<String, dynamic>> moodDetails = {
    '1': {'name': '特别开心', 'color': Colors.orange[500]!, 'value': 8.0},
    '2': {'name': '很开心', 'color': Colors.amber[600]!, 'value': 7.0},
    '3': {'name': '有点开心', 'color': Colors.yellow[600]!, 'value': 6.0},
    '4': {'name': '一般', 'color': Colors.grey[500]!, 'value': 5.0},
    '5': {'name': '有点伤心', 'color': Colors.lightBlue[400]!, 'value': 4.0},
    '6': {'name': '伤心', 'color': Colors.blue[600]!, 'value': 3.0},
    '7': {'name': '很伤心', 'color': Colors.indigo[400]!, 'value': 2.0},
    '8': {'name': '崩溃', 'color': Colors.deepPurple[700]!, 'value': 1.0},
    '0': {'name': '生病', 'color': Colors.teal[400]!, 'value': 4.5},
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

    // 1. 热力图需要全年的数据，所以我们先获取所有日记
    final allEntries = await diaryService.getAllEntriesSorted();
    final activityData = _prepareActivityData(allEntries);

    // 2. 其他图表只使用选定范围内的数据
    final filteredEntries = allEntries.where((entry) {
      if (_selectedDateRange == null) return true;
      return !entry.date.isBefore(_selectedDateRange!.start) &&
          entry.date.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
    }).toList();

    final calendarData = _prepareMoodCalendarData(filteredEntries);
    final lineChartData = _prepareMoodLineChartData(filteredEntries);
    final wordCloudData = await _prepareWordCloudData(filteredEntries);

    setState(() {
      _activityData = activityData; // 更新热力图数据
      _moodCalendarData = calendarData;
      _moodLineChartData = lineChartData['spots'];
      _minDate = lineChartData['minDate'];
      _maxDate = lineChartData['maxDate'];
      _wordCloudData = wordCloudData;
    });
  }

  Map<DateTime, int> _prepareActivityData(List<DiaryEntry> allEntries) {
    final Map<DateTime, int> datasets = {};
    for (var entry in allEntries) {
      final dateOnly = DateTime(entry.date.year, entry.date.month, entry.date.day);
      // 这里的 value 是日记篇数
      datasets.update(dateOnly, (value) => value + 1, ifAbsent: () => 1);
    }
    return datasets;
  }

  // --- 全新的数据准备方法 ---

  Map<DateTime, int> _prepareMoodCalendarData(List<DiaryEntry> entries) {
    final Map<DateTime, int> datasets = {};
    for (var entry in entries) {
      if (entry.mood != null) {
        final dateOnly = DateTime(entry.date.year, entry.date.month, entry.date.day);
        final moodValue = (moodDetails[entry.mood!]?['value'] as double?)?.toInt() ?? 5;
        datasets[dateOnly] = moodValue;
      }
    }
    return datasets;
  }

  final Set<String> _defaultStopWords = const {
    '的', '了', '我', '你', '他', '她', '它', '我们', '你们', '他们',
    '是', '在', '有', '也', '还', '就', '都', '不', '和', '与', '或',
    '一个', '一些', '这个', '那个', '这', '那', '被', '把', '会', '能',
    '吗', '吧', '呢', '啊', '哦', '嗯', '!', '?', '.', ',', '，', '。',
    '：', '“', '”', '（', '）', '《', '》', ' '
  };

  Map<String, dynamic> _prepareMoodLineChartData(List<DiaryEntry> entries) {
    if (entries.isEmpty) {
      return {'spots': <FlSpot>[], 'minDate': null, 'maxDate': null};
    }
    // 按日期正序排列，以便绘制折线图
    entries.sort((a, b) => a.date.compareTo(b.date));

    final List<FlSpot> spots = entries.where((e) => e.mood != null).map((entry) {
      final x = entry.date.millisecondsSinceEpoch.toDouble();
      final y = moodDetails[entry.mood!]?['value'] as double? ?? 5.0;
      return FlSpot(x, y);
    }).toList();

    return {
      'spots': spots,
      'minDate': entries.first.date,
      'maxDate': entries.last.date,
    };
  }

  Future<List<Map>> _prepareWordCloudData(List<DiaryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final customStopWords = prefs.getStringList('custom_stop_words') ?? [];
    final combinedStopWords = {..._defaultStopWords, ...customStopWords};
    final Map<String, int> wordFrequencies = {};
    final allText = entries.map((e) => e.text).join(' ');
    final words = allText.split(RegExp(r"[^\u4e00-\u9fa5]+"));

    for (var word in words) {
      if (word.isNotEmpty && !combinedStopWords.contains(word) && word.length > 1) {
        wordFrequencies.update(word, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    final sortedWords = wordFrequencies.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (sortedWords.length < 3) return [];
    if (sortedWords.first.value == sortedWords.last.value) return [];

    return sortedWords.take(50).map((e) => {'word': e.key, 'value': e.value}).toList();
  }

  // 文件位置: libs/analysis_page.dart -> _AnalysisPageState

  // 文件位置: libs/analysis_page.dart -> _AnalysisPageState

  Widget _buildActivityHeatmap() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('年度写作热力图', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('展示过去一年的写作活跃度', style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        HeatMap(
          datasets: _activityData,
          startDate: DateTime.now().subtract(const Duration(days: 365)),
          endDate: DateTime.now().add(const Duration(days: 40)),
          scrollable: true,
          colorMode: ColorMode.opacity,
          showColorTip: false,
          size: 20,
          colorsets: {
            1: theme.colorScheme.primary,
          },
          defaultColor: theme.dividerColor.withOpacity(0.1),

          // VVVV 核心修改 1: 添加 onClick 回调 VVVV
          onClick: (date) {
            setState(() {
              _selectedHeatmapDate = date;
            });
          },
        ),
        // VVVV 核心修改 2: 增加一个容器来显示点击后的信息 VVVV
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

  // --- 全新的UI构建方法 ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('统计分析')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildActivityHeatmap(),
          const Divider(height: 48),

          _buildDateRangeSelector(),
          const SizedBox(height: 24),
          _buildMoodCalendar(),
          const Divider(height: 48),
          _buildMoodLineChart(),
          const Divider(height: 48),
          _buildWordCloud(),
        ],
      ),
    );
  }



  Widget _buildDateRangeSelector() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.calendar_today),
        title: const Text('选择分析时段'),
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

  // 文件位置: libs/analysis_page.dart -> _AnalysisPageState

  Widget _buildMoodCalendar() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('心情日历', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        HeatMapCalendar(
          datasets: _moodCalendarData,
          colorMode: ColorMode.color,
          showColorTip: false,
          colorsets: {
            1: moodDetails['8']!['color'], 2: moodDetails['7']!['color'],
            3: moodDetails['6']!['color'], 4: moodDetails['5']!['color'],
            5: moodDetails['4']!['color'], 6: moodDetails['3']!['color'],
            7: moodDetails['2']!['color'], 8: moodDetails['1']!['color'],
          },
          defaultColor: theme.colorScheme.surfaceVariant,
          textColor: theme.colorScheme.onSurfaceVariant,
          monthFontSize: 16,
          weekTextColor: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
          onClick: (date) {
            final dayData = _moodCalendarData[DateTime(date.year, date.month, date.day)];
            if (dayData != null) {
              final moodName = moodDetails.values.firstWhere(
                    (m) => m['value'] == dayData, orElse: () => {'name': ''},
              )['name'];
              setState(() {
                _selectedCalendarDateInfo = '${DateFormat('M月d日').format(date)}: $moodName';
              });
            }
          },
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            _selectedCalendarDateInfo ?? '点击日历上的方块查看当天心情',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
          ),
        ),

        // VVVV  新增的颜色图例 VVVV
        const SizedBox(height: 24),
        Wrap(
          spacing: 16.0,
          runSpacing: 8.0,
          alignment: WrapAlignment.center,
          children: moodDetails.entries.map((entry) {
            final color = entry.value['color'] as Color;
            final name = entry.value['name'] as String;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 12, height: 12, color: color),
                const SizedBox(width: 6),
                Text(name, style: theme.textTheme.bodySmall),
              ],
            );
          }).toList(),
        ),
        // ^^^^ 图例结束 ^^^^
      ],
    );
  }

  // 文件位置: libs/analysis_page.dart -> _AnalysisPageState

  Widget _buildMoodLineChart() {
    final theme = Theme.of(context);
    if (_moodLineChartData.isEmpty || _minDate == null || _maxDate == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('心情趋势图', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40.0),
            child: Text('该时段内没有足够的心情数据生成趋势图。'),
          )),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('心情趋势图', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 24),
        SizedBox(
          height: 250,
          child: LineChart(
            LineChartData(
              // VVVV  核心修改：美化样式 VVVV
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                getDrawingHorizontalLine: (value) => FlLine(color: theme.dividerColor.withOpacity(0.1), strokeWidth: 1),
                getDrawingVerticalLine: (value) => FlLine(color: theme.dividerColor.withOpacity(0.1), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: true, border: Border.all(color: theme.dividerColor.withOpacity(0.2))),
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true, // 启用内置的触摸交互
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (LineBarSpot spot) => theme.colorScheme.primary,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                      final moodName = moodDetails.values.firstWhere((m) => m['value'] == spot.y, orElse: () => {'name': '未知'})['name'];
                      return LineTooltipItem(
                        '${DateFormat('M/d').format(date)}\n$moodName',
                        TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold),
                      );
                    }).toList();
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) {
                  final moodName = moodDetails.values.firstWhere((m) => m['value'] == value, orElse: () => {'name': ''})['name'];
                  return Text(moodName, style: theme.textTheme.bodySmall, textAlign: TextAlign.center);
                })),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: (_maxDate!.millisecondsSinceEpoch - _minDate!.millisecondsSinceEpoch) / 4, getTitlesWidget: (value, meta) {
                  final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                  return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(DateFormat('M/d').format(date), style: theme.textTheme.bodySmall));
                })),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              minY: 1, maxY: 8,
              lineBarsData: [
                LineChartBarData(
                  spots: _moodLineChartData,
                  isCurved: true,
                  gradient: LinearGradient(colors: [theme.colorScheme.secondary, theme.colorScheme.primary]),
                  barWidth: 4,
                  dotData: const FlDotData(show: true), // <--- 让数据点显示出来
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [theme.colorScheme.secondary.withOpacity(0.3), theme.colorScheme.primary.withOpacity(0.0)],
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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