// file: lib/home_page.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:carousel_slider/carousel_slider.dart' as cs;
import 'package:http/http.dart' as http; // VVV 1. This import was missing VVV
import 'diary_service.dart';
import 'main.dart';
import 'diary_view_page.dart';
import 'theme_provider.dart';
import 'user_provider.dart';
import 'edit_profile_page.dart';
import 'recycle_bin_page.dart';
import 'search_page.dart';
import 'favorites_provider.dart';
import 'favorites_page.dart';
import 'analysis_page.dart';
import 'settings_page.dart';
import 'festival_service.dart'; // 导入新服务
import 'festivals_page.dart';   // 导入新页面
import 'diary_home_page.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'add_diary_page.dart';
import 'location_memories_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _showDebugInfo(BuildContext context) async {
    final diaryService = context.read<DiaryService>();
    final String debugInfo = await diaryService.getDebugInfo();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('调试信息'),
        content: SingleChildScrollView(
          child: Text(debugInfo),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () {
            _showDebugInfo(context);
          },
          child: const Text('我的日记'),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      drawer: const AppDrawer(),
      body: const _HomePageContent(),
      floatingActionButton: SpeedDial(
        icon: Icons.menu, // 主按钮的图标
        activeIcon: Icons.close, // 展开后主按钮的图标
        buttonSize: const Size(56.0, 56.0),
        visible: true,
        curve: Curves.bounceIn,
        overlayColor: Colors.black,
        overlayOpacity: 0.5,
        tooltip: '快速操作',
        heroTag: 'speed-dial-hero-tag',
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 8.0,
        shape: const CircleBorder(),

        // VVV 这里定义展开的子按钮 VVV
        children: [
          SpeedDialChild(
            child: const Icon(Icons.add),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            label: '写日记',
            labelStyle: const TextStyle(fontSize: 18.0),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => AddDiaryPage(
                    selectedDate: DateTime.now(),
                  ),
                ),
              );
            },
          ),
          SpeedDialChild(
            child: const Icon(Icons.calendar_month),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            label: '看日历',
            labelStyle: const TextStyle(fontSize: 18.0),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const DiaryHomePage()),
              );
            },
          ),
        ],
      ),
    );
  }
}

// VVV 2. This StatefulWidget class definition was missing VVV
class _HomePageContent extends StatefulWidget {
  const _HomePageContent();

  @override
  State<_HomePageContent> createState() => _HomePageContentState();
}

// file: lib/home_page.dart

class _HomePageContentState extends State<_HomePageContent> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _fullQuoteText = "正在获取今日份的灵感...";
  String _currentSentence = "";
  String _currentSource = "";
  bool _isLoadingQuote = true;

  // VVV 1. Remove the hardcoded gradient list from here VVV
  // final List<List<Color>> _festivalGradients = const [ ... ];

  @override
  void initState() {
    super.initState();
    _fetchDailyQuote();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ... (_fetchDailyQuote, _buildDailyQuoteSection, _buildHeader methods are unchanged) ...
  Future<void> _fetchDailyQuote() async {
    setState(() {
      _isLoadingQuote = true; // 开始加载，显示转圈圈
      _fullQuoteText = "正在连接情绪的频率...";
    });

    try {
      final url = Uri.parse('https://api.shadiao.pro/pyq');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));

        // 解析新的API返回的文案
        final sentence = data['data']['text'] ?? '今天也要开心哦。';
        final source = ''; // 这个API不提供来源，所以我们留空

        setState(() {
          _currentSentence = sentence;
          _currentSource = source;
          _fullQuoteText = sentence; // 直接显示句子
          _isLoadingQuote = false; // 加载完成
        });
      } else {
        throw Exception('Failed to load quote from API');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentSentence = "可以看看窗外，今天的风很温柔。";
          _currentSource = "";
          _fullQuoteText = _currentSentence;
          _isLoadingQuote = false; // 加载失败也要停止转圈
        });
      }
    }
  }

  Widget _buildDailyQuoteSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Text(
            _fullQuoteText,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                // 加载时显示菊花图，加载完显示刷新按钮
                child: _isLoadingQuote
                    ? const Padding(padding: EdgeInsets.all(10.0), child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '换一句',
                  onPressed: _fetchDailyQuote,
                ),
              ),
              const SizedBox(width: 16),
              Consumer<FavoritesProvider>(
                builder: (context, favProvider, child) {
                  final isLiked = favProvider.isFavorite(_currentSentence, _currentSource);
                  return SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      tooltip: isLiked ? '取消收藏' : '收藏',
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.redAccent : null,
                      ),
                      // 正在加载或句子为空时，禁用收藏按钮
                      onPressed: (_isLoadingQuote || _currentSentence.isEmpty)
                          ? null
                          : () {
                        if (isLiked) {
                          favProvider.removeFavorite(_currentSentence, _currentSource);
                        } else {
                          favProvider.addFavorite(_currentSentence, _currentSource);
                        }
                      },
                    ),
                  );
                },
              ),
            ],
          )
        ],
      ),
    );
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
          _buildDailyQuoteSection(),
        ],
      ),
    );
  }

  Widget _buildFestivalSection() {
    // VVV 2. Use Consumer2 to listen to both FestivalProvider and ThemeProvider VVV
    return Consumer2<FestivalProvider, ThemeProvider>(
      builder: (context, festivalProvider, themeProvider, child) {
        if (festivalProvider.isLoading) {
          return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
        }

        final festivals = festivalProvider.upcomingFestivals;
        if (festivals.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: cs.CarouselSlider.builder(
            itemCount: festivals.length,
            itemBuilder: (context, index, realIndex) {
              // Pass the entire ThemeProvider to the card builder
              return _buildFestivalCard(festivals[index], index, themeProvider);
            },
            options: cs.CarouselOptions(
              height: 160,
              scrollDirection: Axis.vertical,
              enlargeCenterPage: true,
              viewportFraction: 0.7,
              enlargeFactor: 0.25,
            ),
          ),
        );
      },
    );
  }

  // VVV 3. Update the card builder to accept ThemeProvider and use the correct gradient list VVV
  // file: lib/home_page.dart

  // ... inside the _HomePageContentState class ...

  // VVV Use this to replace the old _buildFestivalCard method VVV
  Widget _buildFestivalCard(Map<String, dynamic> festival, int index, ThemeProvider themeProvider) {
    final int daysUntil = festival['daysUntil'];
    final String dateFormatted = DateFormat('M月d日').format(festival['date']);

    // --- FIX: Use the unified 'cardGradientColors' for all cards ---
    final gradients = themeProvider.cardGradientColors;
    final gradient = gradients[index % gradients.length];

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FestivalsPage()));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient.last.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  festival['name'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black26, blurRadius: 2)],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateFormatted,
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                ),
              ],
            ),
            Text(
              daysUntil == 0 ? '今天' : '$daysUntil\n天后',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w300,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ... (all other methods like _buildOnThisDaySection, _buildHistoryList, etc., remain the same) ...
  Widget _buildOnThisDaySection() {
    return Consumer<DiaryService>(
      builder: (context, diaryService, child) {
        return FutureBuilder<List<DiaryEntry>>(
          future: diaryService.getOnThisDayEntries(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox.shrink();
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const SizedBox.shrink();
            }

            final entries = snapshot.data!;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('那年今日', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 10),
                  Column(
                    children: entries.map((entry) => _buildOnThisDayCard(entry)).toList(),
                  ),
                  const SizedBox(height: 10),
                  const Divider(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOnThisDayCard(DiaryEntry entry) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => DiaryViewPage(entry: entry))),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Container(
                width: 80,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      entry.date.year.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('M月d日', 'zh_CN').format(entry.date),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.text.isNotEmpty ? entry.text : '(无文字内容)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (entry.imagePaths.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(entry.imagePaths.first),
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                  ),
                ),
            ],
          ),
        ),
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
              Image.file(File(entry.imagePaths.first), fit: BoxFit.cover),
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
            final bool showMonthSeparator = index == 0 ||
                (entries[index - 1].date.month != currentEntry.date.month ||
                    entries[index - 1].date.year != currentEntry.date.year);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showMonthSeparator) _buildMonthSeparator(currentEntry.date),
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
              if (entry.imagePaths.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Image.file(File(entry.imagePaths.first), width: 100, height: 120, fit: BoxFit.cover),
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
    super.build(context);
    final diaryService = context.watch<DiaryService>();

    return SafeArea(
      top: false,
      child: RefreshIndicator(
        onRefresh: () async {
          await _fetchDailyQuote();
          await context.read<FestivalProvider>().loadFestivals();
        },
        child: ListView(
          children: [
            Consumer<ThemeProvider>(
                builder: (context, themeProvider, child) => _buildHeader(context)
            ),
            const SizedBox(height: 10),
            _buildFestivalSection(),
            const SizedBox(height: 20),
            _buildOnThisDaySection(),
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

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeProvider, UserProvider>(
      builder: (context, themeProvider, userProvider, child) {
        return Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
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
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('主页'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: const Text('统计分析'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const AnalysisPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.map_outlined),
                title: const Text('足迹地图'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const LocationMemoriesPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.favorite_outline),
                title: const Text('我的收藏'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const FavoritesPage()),
                  );
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
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const RecycleBinPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.search_outlined),
                title: const Text('搜索'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const SearchPage()),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('设置与工具'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const SettingsPage()),
                  );
                },
              ),
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