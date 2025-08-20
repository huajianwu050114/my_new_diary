// 文件位置: lib/statistics_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  // 使用 Future 来处理异步加载的数据
  late Future<Map<String, dynamic>> _statsFuture;

  // 心情代码到名称的映射
  final Map<String, String> _moodMap = {
    '1': '特别开心', '2': '很开心', '3': '有点开心', '4': '一般',
    '5': '有点伤心', '6': '伤心', '7': '很伤心', '8': '崩溃', '0': '生病',
  };

  @override
  void initState() {
    super.initState();
    // 页面加载时，开始获取统计数据
    _statsFuture = context.read<DiaryService>().getStatistics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的数据统计'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载统计数据失败: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('暂无数据'));
          }

          final stats = snapshot.data!;
          final moodCounts = stats['moodCounts'] as Map<String, int>;
          final timeOfDayCounts = stats['timeOfDayCounts'] as Map<String, int>;

          // 找到最常出现的心情
          String mostFrequentMood = "暂无";
          if (moodCounts.isNotEmpty) {
            final sortedMoods = moodCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            mostFrequentMood = _moodMap[sortedMoods.first.key] ?? "未知";
          }

          // 找到最常见的写作时段
          String mostFrequentTime = "暂无";
          if (timeOfDayCounts.isNotEmpty) {
            final sortedTimes = timeOfDayCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            if (sortedTimes.first.value > 0) {
              mostFrequentTime = sortedTimes.first.key;
            }
          }

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // 使用辅助方法构建卡片，让代码更整洁
              _buildStatGrid(stats),
              const SizedBox(height: 24),
              _buildStatCard(
                icon: Icons.favorite_border,
                title: '最常记录的心情',
                value: mostFrequentMood,
                color: Colors.pinkAccent,
              ),
              const SizedBox(height: 16),
              _buildStatCard(
                icon: Icons.access_time,
                title: '最常写作的时段',
                value: mostFrequentTime,
                color: Colors.orangeAccent,
              ),
            ],
          );
        },
      ),
    );
  }

  // 一个用于构建网格布局的辅助方法
  Widget _buildStatGrid(Map<String, dynamic> stats) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.2,
      children: [
        _buildStatCard(icon: Icons.book_outlined, title: '总日记篇数', value: '${stats['totalEntries']}', color: Colors.blue),
        _buildStatCard(icon: Icons.text_fields, title: '累计写作字数', value: '${stats['totalWordCount']}', color: Colors.green),
        _buildStatCard(icon: Icons.check_circle_outline, title: '累计签到天数', value: '${stats['totalCheckIns']}', color: Colors.purple),
        _buildStatCard(icon: Icons.local_fire_department_outlined, title: '最长连写天数', value: '${stats['longestStreak']}', color: Colors.red),
      ],
    );
  }

  // 一个用于构建单个数据卡片的辅助方法
  // 文件位置: lib/statistics_page.dart -> _StatisticsPageState

  Widget _buildStatCard({required IconData icon, required String title, required String value, required Color color}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      shadowColor: color.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              // VVVV 主要修改区域 VVVV
              crossAxisAlignment: CrossAxisAlignment.start, // 让图标和文字顶部对齐
              children: [
                // 1. 将标题文字用 Expanded 包裹，使其能自动换行
                Expanded(
                  child: Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)
                  ),
                ),
                // 2. 增加一点间距，避免文字和图标贴得太近
                const SizedBox(width: 8),
                Icon(icon, color: color),
              ],
              // ^^^^ 主要修改区域结束 ^^^^
            ),
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}