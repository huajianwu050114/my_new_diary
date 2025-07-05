import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';
import 'main.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:carousel_slider/carousel_slider.dart' as cs;
import 'dart:io';
import 'diary_view_page.dart';
import 'theme_provider.dart';

// 恢复为简单的 StatefulWidget
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 不再需要任何 Controller 或 KeepAlive
  String _dailyQuote = "正在获取今日份的灵感...";
  bool _isLoadingQuote = true;

  @override
  void initState() {
    super.initState();
    _fetchDailyQuote();
  }

  Future<void> _fetchDailyQuote() async {
    try {
      final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final url = Uri.parse('https://sentence.iciba.com/index.php?c=dailysentence&m=getdetail&title=$today');
      final response = await http.get(url, ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _dailyQuote = "${data['content']}\n${data['note']}";
            _isLoadingQuote = false;
          });
        }
      } else {
        throw Exception('Failed to load daily sentence');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _dailyQuote = "获取句子失败，请检查网络连接。";
          _isLoadingQuote = false;
        });
      }
    }
  }

  // --- UI 构建辅助方法 ---

  // 已全面主题化
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.read<ThemeProvider>();
    final now = DateTime.now();
    final dayOfWeek = DateFormat('EEEE', 'zh_CN').format(now);

    // 根据日夜间模式选择不同的渐变色
    final List<Color> cardGradient = themeProvider.isDarkMode
        ? [const Color(0xFF3A3A3A), const Color(0xFF2A2A2A)]
        : [Colors.purple.shade200, Colors.pink.shade100];

    final Color cardTextColor = themeProvider.isDarkMode ? Colors.white70 : Colors.white;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: cardGradient, // <-- 使用主题化颜色
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12.0),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.2),
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
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    color: cardTextColor, // <-- 使用主题化颜色
                    height: 1,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dayOfWeek,
                      style: TextStyle(
                        fontSize: 18,
                        color: cardTextColor, // <-- 使用主题化颜色
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${now.year} / ${now.month}',
                      style: TextStyle(
                        fontSize: 18,
                        color: cardTextColor, // <-- 使用主题化颜色
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _dailyQuote,
                  style: theme.textTheme.bodySmall, // <-- 使用主题化文本样式
                  textAlign: TextAlign.center,
                ),
              ),
              if (_isLoadingQuote) const SizedBox(width: 10),
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


  // <-- 2. 构建方法接收 DiaryService 实例
  Widget _buildCarousel(DiaryService diaryService) {
    return FutureBuilder<List<DiaryEntry>>(
      // <-- 3. 直接使用 service 的方法
      future: diaryService.getRecentEntriesWithImages(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink(); // 如果没有图片或加载失败，不显示
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

  Widget _buildCarouselItem(DiaryEntry entry) {
    // 这个方法保持不变
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => DiaryViewPage(entry: entry)),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5.0),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(12.0)),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.file(File(entry.imagePath!), fit: BoxFit.cover),
              Positioned(
                bottom: 0.0,
                left: 0.0,
                right: 0.0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color.fromARGB(200, 0, 0, 0), Color.fromARGB(0, 0, 0, 0)],
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
                        style: const TextStyle(color: Colors.white, fontSize: 12.0),
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
      ),
    );
  }

  Widget _buildHistoryList(DiaryService diaryService) {
    return FutureBuilder<List<DiaryEntry>>(
      future: diaryService.getAllEntriesSorted(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(32.0),
            child: CircularProgressIndicator(),
          ));
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

                // =========================================================
                // 关键改动：在这里用 Consumer 包裹每一个卡片
                // =========================================================
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, child) {
                    // 将 themeProvider 传递给 _buildHistoryCard 方法
                    return _buildHistoryCard(currentEntry, index, themeProvider);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 关键改动：_buildHistoryCard 接收 themeProvider 作为参数
  Widget _buildHistoryCard(DiaryEntry entry, int index, ThemeProvider themeProvider) {
    final gradientList = themeProvider.cardGradientColors; // 直接使用传入的 provider
    final currentGradient = gradientList[index % gradientList.length];

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => DiaryViewPage(entry: entry)),
        );
      },
      child: Card(
        // ... Card 属性不变
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: currentGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          // ... Card 内部结构不变
          child: SizedBox(
            height: 120,
            child: Row(
              children: [
                SizedBox(
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
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(
                      entry.text.isNotEmpty ? entry.text : '(无文字内容)',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontWeight: FontWeight.w400,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
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

  @override
  Widget build(BuildContext context) {
    // 在顶层监听，这样整个页面都会在主题切换时重建
    final diaryService = context.watch<DiaryService>();
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的日记'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              themeProvider.isDarkMode ? Icons.wb_sunny_outlined : Icons.nightlight_round_outlined,
            ),
            onPressed: () {
              final isDark = !themeProvider.isDarkMode;
              context.read<ThemeProvider>().toggleTheme(isDark);
            },
            tooltip: '切换日夜间模式',
          )
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() {});
            await _fetchDailyQuote();
          },
          child: ListView(
            // 不再需要 Key 或 Controller
            children: [
              _buildHeader(context),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(left: 20.0),
                child: Text(
                  '近期精彩瞬间',
                  // 直接使用主题默认的标题样式，它会自动适应日夜间模式
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 10),
              _buildCarousel(diaryService),
              _buildHistoryList(diaryService),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const DiaryHomePage()),
          );
        },
        child: const Icon(Icons.calendar_month),
        tooltip: '查看日历',
      ),
    );
  }

  // 请将此方法添加到 _HomePageContentState 类中

  Widget _buildMonthSeparator(DateTime date) {
    final color = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black54;

    return Padding(
      padding: const EdgeInsets.only(left: 20.0, top: 24.0, bottom: 10.0),
      child: Text(
        DateFormat('yyyy年 MMMM', 'zh_CN').format(date),
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: color.withOpacity(0.8),
        ),
      ),
    );
  }
}