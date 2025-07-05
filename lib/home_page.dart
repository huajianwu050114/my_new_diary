// file: lib/home_page.dart

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
import 'user_provider.dart';
import 'edit_profile_page.dart';
import 'recycle_bin_page.dart';
import 'search_page.dart';

/// HomePage 外壳组件 (StatelessWidget)
/// 它只负责构建整体的页面框架，如 AppBar 和 FloatingActionButton。
/// 它的主题切换按钮只会重建它自己，不会影响 body 里的内容。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的日记'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        // 我们不再需要 actions 里的按钮，因为它将被移到菜单栏中
      ),
      // VVV 关键改动：在这里添加 drawer 属性 VVV
      drawer: const AppDrawer(),
      body: const _HomePageContent(),
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
}

/// 真正的内容区组件 (StatefulWidget)
/// 它使用了 AutomaticKeepAliveClientMixin 来保证在主题切换时，它的状态（包括滚动位置）不会丢失。
class _HomePageContent extends StatefulWidget {
  const _HomePageContent();

  @override
  State<_HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<_HomePageContent> with AutomaticKeepAliveClientMixin {
  // 开启“保活”模式
  @override
  bool get wantKeepAlive => true;

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
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        setState(() {
          _dailyQuote = "${data['content']}\n${data['note']}";
          _isLoadingQuote = false;
        });
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

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final now = DateTime.now();
    final dayOfWeek = DateFormat('EEEE', 'zh_CN').format(now);

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
              gradient: LinearGradient(colors: cardGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12.0),
              boxShadow: [BoxShadow(color: theme.colorScheme.primary.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${now.day}', style: TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: cardTextColor, height: 1)),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dayOfWeek, style: TextStyle(fontSize: 18, color: cardTextColor, fontWeight: FontWeight.w600)),
                    Text('${now.year} / ${now.month}', style: TextStyle(fontSize: 18, color: cardTextColor)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(child: Text(_dailyQuote, style: theme.textTheme.bodySmall, textAlign: TextAlign.center)),
              if (_isLoadingQuote) const SizedBox(width: 10),
              if (_isLoadingQuote) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCarousel(DiaryService diaryService) {
    return FutureBuilder<List<DiaryEntry>>(
      future: diaryService.getRecentEntriesWithImages(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));

        return cs.CarouselSlider.builder(
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index, realIndex) => _buildCarouselItem(snapshot.data![index]),
          options: cs.CarouselOptions(aspectRatio: 16 / 9, viewportFraction: 0.85, enlargeCenterPage: true, autoPlay: true),
        );
      },
    );
  }

  Widget _buildCarouselItem(DiaryEntry entry) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => DiaryViewPage(entry: entry))),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5.0),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(12.0)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(File(entry.imagePath!), fit: BoxFit.cover),
              Positioned(
                bottom: 0.0, left: 0.0, right: 0.0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color.fromARGB(200, 0, 0, 0), Colors.transparent],
                      begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('yyyy-MM-dd HH:mm').format(entry.creationTime), style: const TextStyle(color: Colors.white, fontSize: 14.0, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(entry.text, style: const TextStyle(color: Colors.white, fontSize: 12.0), maxLines: 1, overflow: TextOverflow.ellipsis),
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
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 50.0), child: Text('还没有任何日记，开始记录第一篇吧！')));

        final entries = snapshot.data!;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final currentEntry = entries[index];
            final bool showMonthSeparator = index == 0 || (entries[index - 1].creationTime.month != currentEntry.creationTime.month || entries[index - 1].creationTime.year != currentEntry.creationTime.year);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showMonthSeparator) _buildMonthSeparator(currentEntry.creationTime),
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, child) {
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

  Widget _buildHistoryCard(DiaryEntry entry, int index, ThemeProvider themeProvider) {
    final gradientList = themeProvider.cardGradientColors;
    final currentGradient = gradientList[index % gradientList.length];

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => DiaryViewPage(entry: entry))),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: currentGradient, begin: Alignment.topLeft, end: Alignment.bottomRight)),
          height: 120,
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(DateFormat('d').format(entry.creationTime), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white70)),
                    Text(DateFormat('MMMM', 'zh_CN').format(entry.creationTime), style: const TextStyle(fontSize: 14, color: Colors.white70)),
                    Text(DateFormat('E', 'zh_CN').format(entry.creationTime), style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
                    const SizedBox(height: 4),
                    Text(DateFormat('HH:mm').format(entry.creationTime), style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
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
                    style: TextStyle(color: Colors.white.withOpacity(0.95), fontWeight: FontWeight.w400, fontSize: 15, height: 1.4),
                  ),
                ),
              ),
              if (entry.imagePath != null && entry.imagePath!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Image.file(File(entry.imagePath!), width: 100, height: 120, fit: BoxFit.cover),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthSeparator(DateTime date) {
    final color = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black54;
    return Padding(
      padding: const EdgeInsets.only(left: 20.0, top: 24.0, bottom: 10.0),
      child: Text(
        DateFormat('yyyy年 MMMM', 'zh_CN').format(date),
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color.withOpacity(0.8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // KeepAlive 需要这一句
    final diaryService = context.watch<DiaryService>();

    return SafeArea(
      top: false,
      child: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
          await _fetchDailyQuote();
        },
        child: ListView(
          children: [
            // 使用 Consumer 来精准更新 Header，而不是让整个组件都 watch
            Consumer<ThemeProvider>(
                builder: (context, themeProvider, child) => _buildHeader(context)
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 20.0),
              child: Text('近期精彩瞬间', style: Theme.of(context).textTheme.headlineSmall),
            ),
            const SizedBox(height: 10),
            _buildCarousel(diaryService),
            _buildHistoryList(diaryService),
          ],
        ),
      ),
    );
  }
}
// file: lib/home_page.dart (粘贴到文件末尾)



// VVV 用下面的代码完整替换您文件中现有的 AppDrawer 类 VVV
// file: lib/home_page.dart (找到 AppDrawer 类并替换)

// file: lib/home_page.dart



// ... (HomePage 组件和 _HomePageContent 组件保持不变) ...


// VVV 用下面的代码完整替换您文件中现有的 AppDrawer 类 VVV
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    // 使用 Consumer2 可以同时监听两个 Provider，让代码更清晰
    return Consumer2<ThemeProvider, UserProvider>(
      builder: (context, themeProvider, userProvider, child) {
        return Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // 1. 将头部用 GestureDetector 包裹，使其可以响应点击事件
              GestureDetector(
                onTap: () {
                  Navigator.pop(context); // 先关闭抽屉
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EditProfilePage()),
                  );
                },
                child: DrawerHeader(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: themeProvider.isDarkMode
                          ? [const Color(0xFF3A3A3A), const Color(0xFF2A2A2A)]
                          : [Colors.purple.shade200, Colors.pink.shade100],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 2. 头像部分：从 UserProvider 获取数据
                      CircleAvatar(
                        radius: 35,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        backgroundImage: userProvider.avatarPath != null
                            ? FileImage(File(userProvider.avatarPath!))
                            : null,
                        child: userProvider.avatarPath == null
                            ? const Icon(Icons.person, size: 40, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      // 3. 昵称部分：从 UserProvider 获取数据
                      Text(
                        userProvider.nickname,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 4. 功能列表部分保持不变
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('主页'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('日历视图'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const DiaryHomePage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.restore_from_trash_outlined),
                title: const Text('回收站'),
                onTap: () {
                  Navigator.pop(context); // 先关闭抽屉
                  Navigator.of(context).push( // 再跳转到回收站页面
                    MaterialPageRoute(builder: (context) => const RecycleBinPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.search_outlined),
                title: const Text('搜索'),
                onTap: () {
                  Navigator.pop(context); // 先关闭抽屉
                  Navigator.of(context).push( // 再跳转到搜索页面
                    MaterialPageRoute(builder: (context) => const SearchPage()),
                  );
                },
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('夜间模式'),
                secondary: Icon(
                  themeProvider.isDarkMode ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                ),
                value: themeProvider.isDarkMode,
                onChanged: (bool value) {
                  context.read<ThemeProvider>().toggleTheme(value);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}