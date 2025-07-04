import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'diary_service.dart';
import 'main.dart'; // 我们需要跳转到日历页，所以导入旧的main.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:carousel_slider/carousel_slider.dart' as cs;
import 'dart:io';
import 'diary_view_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

// 在 home_page.dart 文件顶部，添加新的导入


// home_page.dart

// home_page.dart

class _HomePageState extends State<HomePage> {
  //============================================================================
  // 1. 状态变量
  //============================================================================
  final DiaryService _diaryService = DiaryService();
  late Future<List<DiaryEntry>> _carouselEntriesFuture;
  late Future<List<DiaryEntry>> _allEntriesFuture;

  final List<List<Color>> _gradientColors = [
    [const Color(0xffff9a9e), const Color(0xfffad0c4)], // 珊瑚粉 -> 杏色
    [const Color(0xffa18cd1), const Color(0xfffbc2eb)], // 薰衣草紫 -> 淡粉
    [const Color(0xff84fab0), const Color(0xff8fd3f4)], // 青草绿 -> 天空蓝
    [const Color(0xfffccb90), const Color(0xffd57eeb)], // 暖阳橙 -> 兰花紫
    [const Color(0xffa6c0fe), const Color(0xfff68084)], // 宁静蓝 -> 活力红
    [const Color(0xfff6d365), const Color(0xfffda085)], // 金色 -> 橙红
  ];

  String _dailyQuote = "正在获取今日份的灵感...";
  bool _isLoadingQuote = true;

  //============================================================================
  // 2. 初始化与数据获取方法
  //============================================================================
  @override
  void initState() {
    super.initState();
    _refreshData();
    _fetchDailyQuote();
  }

  void _refreshData() {
    setState(() {
      _carouselEntriesFuture = _diaryService.getRecentEntriesWithImages();
      _allEntriesFuture = _diaryService.getAllEntriesSorted();
    });
  }

  Future<void> _fetchDailyQuote() async {
    try {
      final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final url = Uri.parse('https://sentence.iciba.com/index.php?c=dailysentence&m=getdetail&title=$today');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _dailyQuote = "${data['content']}\n${data['note']}";
          _isLoadingQuote = false;
        });
      } else {
        throw Exception('Failed to load daily sentence');
      }
    } catch (e) {
      setState(() {
        _dailyQuote = "获取句子失败，请检查网络连接。";
        _isLoadingQuote = false;
      });
    }
  }

  //============================================================================
  // 3. UI 构建辅助方法 (这里补上了缺失的方法)
  //============================================================================

  // --- 构建顶部区域的方法 ---
  Widget _buildHeader(BuildContext context) {
    final now = DateTime.now();
    final dayOfWeek = DateFormat('EEEE', 'zh_CN').format(now);
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade200, Colors.pink.shade100],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.pink.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${now.day}',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dayOfWeek,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${now.year} / ${now.month}',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _dailyQuote,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              if (_isLoadingQuote)
                const SizedBox(width: 10),
              if (_isLoadingQuote)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // --- 构建轮播图的方法 ---
  Widget _buildCarousel() {
    return FutureBuilder<List<DiaryEntry>>(
      future: _carouselEntriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const SizedBox(
            height: 200,
            child: Center(child: Text('加载精彩瞬间失败')),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final carouselEntries = snapshot.data!;
        return cs.CarouselSlider.builder(
          itemCount: carouselEntries.length,
          itemBuilder: (context, index, realIndex) {
            final entry = carouselEntries[index];
            return _buildCarouselItem(entry);
          },
          options: cs.CarouselOptions(
            aspectRatio: 16 / 9,
            viewportFraction: 0.85,
            enlargeCenterPage: true,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 5),
          ),
        );
      },
    );
  }

  // --- 构建单张轮播卡片UI的方法 ---
  Widget _buildCarouselItem(DiaryEntry entry) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5.0),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(12.0)),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.file(
              File(entry.imagePath!),
              fit: BoxFit.cover,
            ),
            Positioned(
              bottom: 0.0,
              left: 0.0,
              right: 0.0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color.fromARGB(200, 0, 0, 0),
                      Color.fromARGB(0, 0, 0, 0)
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('yyyy-MM-dd HH:mm').format(entry.creationTime),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 构建历史日记列表的方法 ---
  Widget _buildHistoryList() {
    return FutureBuilder<List<DiaryEntry>>(
      future: _allEntriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 50.0),
              child: Text('还没有任何日记，开始记录第一篇吧！'),
            ),
          );
        }

        final entries = snapshot.data!;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final currentEntry = entries[index];
            bool showMonthSeparator = false;

            if (index == 0) {
              showMonthSeparator = true;
            } else {
              final previousEntry = entries[index - 1];
              if (currentEntry.creationTime.year != previousEntry.creationTime.year ||
                  currentEntry.creationTime.month != previousEntry.creationTime.month) {
                showMonthSeparator = true;
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showMonthSeparator) _buildMonthSeparator(currentEntry.creationTime),
                _buildHistoryCard(currentEntry, index),
              ],
            );
          },
        );
      },
    );
  }

  // --- 构建月份分割条的方法 ---
  Widget _buildMonthSeparator(DateTime date) {
    return Padding(
      padding: const EdgeInsets.only(left: 20.0, top: 24.0, bottom: 10.0),
      child: Text(
        DateFormat('yyyy年 MMMM', 'zh_CN').format(date),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black54,
        ),
      ),
    );
  }

  // --- 构建历史日记卡片的方法 ---
  // 在 _HomePageState 类的内部

  // 在 _HomePageState 类的内部

  Widget _buildHistoryCard(DiaryEntry entry, int index) {
    final currentGradient = _gradientColors[index % _gradientColors.length];

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => DiaryViewPage(entry: entry)),
        ).then((_) => _refreshData());
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: currentGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SizedBox(
            height: 120,
            child: Row(
              children: [
                // --- 左侧：日期详情 ---
                Container(
                  width: 80,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('d').format(entry.creationTime),
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      Text(
                        DateFormat('MMMM', 'zh_CN').format(entry.creationTime),
                        style: const TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                      // 1. 在这里新增了“星期”信息
                      Text(
                        DateFormat('E', 'zh_CN').format(entry.creationTime),
                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('HH:mm').format(entry.creationTime),
                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6)),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1, indent: 16, endIndent: 16, color: Colors.white30),

                // --- 中间：文字内容 ---
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(
                      entry.text.isNotEmpty ? entry.text : '(无文字内容)',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      // 2. 优化了文字样式，让它更清晰
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95), // 1. 这是一个深邃、有质感的高级灰
                        fontWeight: FontWeight.w400,      // 2. 字体比之前更粗一点 (半粗体)
                        fontSize: 15,
                        height: 1.4, // 3. 稍微增加行高，让多行文字更透气
                      ),
                    ),
                  ),
                ),

                // --- 右侧：图片 (保持不变) ---
                if (entry.imagePath != null && entry.imagePath!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: Image.file(
                        File(entry.imagePath!),
                        width: 100,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  //============================================================================
  // 4. 主构建方法
  //============================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            _refreshData();
            _fetchDailyQuote();
          },
          child: ListView(
            children: [
              _buildHeader(context),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.only(left: 20.0),
                child: Text(
                  '近期精彩瞬间',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 10),
              _buildCarousel(),
              _buildHistoryList(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const DiaryHomePage()),
          ).then((_) => _refreshData());
        },
        child: const Icon(Icons.calendar_month),
        tooltip: '查看日历',
      ),
    );
  }
}