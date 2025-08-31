// 文件位置: libs/home_page.dart

// --- 确保您有所有这些 imports ---
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:carousel_slider/carousel_slider.dart' as cs;
import 'package:http/http.dart' as http;
import 'package:my_new_diary/diary_model.dart';
import 'package:my_new_diary/diary_service.dart';
import 'package:my_new_diary/theme_provider.dart';
import 'package:my_new_diary/user_provider.dart';
import 'package:my_new_diary/festival_service.dart';
import 'package:my_new_diary/favorites_provider.dart';
import 'package:my_new_diary/gemini_service_local.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:animate_do/animate_do.dart';
import 'add_diary_page.dart';
import 'analysis_page.dart';
import 'check_in_dialog.dart';
import 'diary_home_page.dart';
import 'edit_profile_page.dart';
import 'favorites_page.dart';
import 'festivals_page.dart';
import 'letters_archive_page.dart';
import 'location_memories_page.dart';
import 'on_this_day_summary_page.dart';
import 'recycle_bin_page.dart';
import 'reflections_archive_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'diary_view_page.dart';
import 'statistics_page.dart';
import 'voice_diary_dialog.dart';
import 'comfort_zone_page.dart';
import 'self_help_guide_page.dart';
import 'voice_input_screen.dart';

// 临时的枚举，确保代码完整性
enum LetterStatus {
  notAvailable,
  readyToGenerate,
  generating,
  available,
}

// =================================================================
// 框架第一部分：HomePage (页面的主入口)
// =================================================================
class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildAppBarTitle(context),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      drawer: const AppDrawer(),
      body: const _HomePageContent(), // 页面主要内容
      floatingActionButton: SpeedDial(
        icon: Icons.menu,
        activeIcon: Icons.close,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        children: [
          SpeedDialChild(
            child: const Icon(Icons.add),
            label: '写日记',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => AddDiaryPage(selectedDate: DateTime.now())),
              );
            },
          ),
          SpeedDialChild(
            child: const Icon(Icons.calendar_month),
            label: '看日历',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const DiaryHomePage()),
              );
            },
          ),
          SpeedDialChild(
            child: const Icon(Icons.mic),
            label: '语音日记',
            onTap: () async {
              // 1. 调用语音输入框，等待AI润色后的文本返回
              final String? polishedText = await showDialog<String?>(
                context: context,
                builder: (context) => const VoiceInputDialog(),
              );

              // 检查页面是否还存在，以及返回的文本是否有效
              if (!context.mounted || polishedText == null || polishedText.isEmpty) {
                return; // 如果用户取消或返回空，则不执行任何操作
              }

              // 检查是否是错误信息
              if (polishedText.startsWith('语音处理失败')) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(polishedText), backgroundColor: Colors.red),
                  );
                }
                return;
              }

              // 2. 如果成功获取到文本，则导航到日记编辑页，并将文本传递过去
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => AddDiaryPage(
                    selectedDate: DateTime.now(),
                    initialText: polishedText, // 使用我们新增的参数
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarTitle(BuildContext context) {
    // 使用 watch 来获取 UserProvider，这样昵称更新时标题也能自动更新
    final userProvider = context.watch<UserProvider>();
    final hour = DateTime.now().hour;
    String title;

    if (hour >= 18 || hour < 5) { // 晚上 6 点到凌晨 5 点
      title = '晚上好，${userProvider.nickname}！';
    } else if (hour >= 12) { // 中午 12 点到下午 6 点
      title = '下午好，${userProvider.nickname}。';
    } else { // 早上 5 点到中午 12 点
      title = '早上好，${userProvider.nickname}！';
    }
    return Text(title);
  }

}

// =================================================================
// 框架第二部分：AppDrawer (侧边栏菜单)
// =================================================================
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
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfilePage()));
                },
                child: DrawerHeader(
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceVariant),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 35,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        backgroundImage: userProvider.avatarPath != null ? FileImage(File(userProvider.avatarPath!)) : null,
                        child: userProvider.avatarPath == null
                            ? Icon(Icons.person, size: 40, color: Theme.of(context).colorScheme.onPrimaryContainer)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        userProvider.nickname,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ListTile(leading: const Icon(Icons.home_outlined), title: const Text('主页'), onTap: () => Navigator.pop(context)),
              ListTile(leading: const Icon(Icons.analytics_outlined), title: const Text('统计分析'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AnalysisPage()))),
              ListTile(
                leading: const Icon(Icons.insights_outlined), // 新图标
                title: const Text('成就栏'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const StatisticsPage()));
                },
              ),
              ListTile(leading: const Icon(Icons.map_outlined), title: const Text('足迹地图'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const LocationMemoriesPage()))),
              ListTile(leading: const Icon(Icons.favorite_outline), title: const Text('收藏句子'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const FavoritesPage()))),
              ListTile(leading: const Icon(Icons.all_inbox_outlined), title: const Text('精灵信箱'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const LettersArchivePage()))),
              ListTile(leading: const Icon(Icons.psychology_outlined), title: const Text('回忆手账'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ReflectionsArchivePage()))),
              ListTile(leading: const Icon(Icons.calendar_today_outlined), title: const Text('日历视图'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const DiaryHomePage()))),
              ListTile(leading: const Icon(Icons.restore_from_trash_outlined), title: const Text('回收站'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const RecycleBinPage()))),
              ListTile(
                leading: const Icon(Icons.lightbulb_outline, color: Colors.amber),
                title: const Text('生存指南'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SelfHelpGuidePage()));
                },
              ),
              const Divider(),
              ListTile(leading: const Icon(Icons.search_outlined), title: const Text('搜索'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SearchPage()))),
              const Divider(),
              ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('设置与工具'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SettingsPage()))),
            ],
          ),
        );
      },
    );
  }
}

// =================================================================
// 框架第三部分：_HomePageContent (StatefulWidget)
// =================================================================
class _HomePageContent extends StatefulWidget {
  const _HomePageContent();
  @override
  State<_HomePageContent> createState() => _HomePageContentState();
}

// =================================================================
// VVVV 我们将在这里逐步填充这个 State 类 VVVV
// =================================================================
class _HomePageContentState extends State<_HomePageContent> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  // --- 状态变量声明 ---

  // 页面整体加载控制
  Future<void>? _pageDataFuture;

  // AI 灵感相关的状态 (将在后续步骤中用于AiPromptCard)
  Map<String, dynamic>? _aiWritingPrompt;
  bool _isLoadingPrompt = true; // 初始为 true

  // 每周信件相关的状态
  LetterStatus _letterStatus = LetterStatus.notAvailable;
  String? _weeklyLetterContent;
  bool _showLetter = false;
  bool _showComfortCard = false;
  DiaryEntry? _memoryBottleEntry;




  @override
  void initState() {
    super.initState();
    // 页面创建时，开始加载所有初始数据
    _pageDataFuture = _loadPageData();

    // 页面渲染完成后，检查是否需要每日签到
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleDailyCheckIn();
    });
  }

  Future<void> _fetchMemoryBottle() async {
    if (!mounted) return;
    final diaryService = context.read<DiaryService>();
    final entry = await diaryService.getRandomEntryWithImage();
    if (mounted) {
      setState(() {
        _memoryBottleEntry = entry;
      });
    }
  }

  @override
  void dispose() {
    // 在未来，如果添加了需要手动释放的控制器（如TextEditingController），要在这里释放
    super.dispose();
  }

  // --- 核心数据加载逻辑 ---

  // 页面首次加载时执行的总任务
  Future<void> _loadPageData() async {
    final diaryService = context.read<DiaryService>();
    // (你之前的调试代码和情绪检测逻辑我暂时为你恢复了，你可以根据需要自行修改)
    diaryService.isFeelingDownRecently().then((isDown) {
      if (mounted && isDown != _showComfortCard) {
        setState(() {
          _showComfortCard = isDown;
        });
      }
    });
    // 并行执行所有加载任务，效率更高
    await Future.wait([
      _loadWeeklyLetter(),
      _fetchAiWritingPrompt(),
      _fetchMemoryBottle(), // <--- VVVV 在这里添加对新方法的调用 VVVV
    ]);
  }

  // 文件位置: libs/home_page.dart -> _HomePageContentState class
// (可以放在其他 _build... 方法的旁边)

  Widget _buildMemoryBottleCard() {
    // 如果没有获取到任何带图片的日记，就不显示这个卡片
    if (_memoryBottleEntry == null) {
      return const SizedBox.shrink();
    }

    final entry = _memoryBottleEntry!;
    final dateString = DateFormat('yyyy年M月d日').format(entry.date);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: ExpansionTile(
        leading: Icon(Icons.wine_bar_outlined, color: Colors.brown.shade300),
        title: const Text('记忆漂流瓶'),
        subtitle: Text('还记得吗？在$dateString的这一天...'),
        initiallyExpanded: false, // 默认折叠
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 显示日记的第一张图片
                if (entry.imagePaths.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(entry.imagePaths.first),
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: 12),
                // 显示日记的文字摘要
                Text(
                  entry.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                // "查看详情" 按钮
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => DiaryViewPage(entry: entry),
                      ));
                    },
                    child: const Text('查看完整日记...'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 检查并弹出每日签到对话框
  Future<void> _handleDailyCheckIn() async {
    final prefs = await SharedPreferences.getInstance();
    final todayString = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final lastLaunchDate = prefs.getString('last_launch_date');

    if (lastLaunchDate != todayString) {
      // 当天第一次启动，显示弹窗
      final bool? checkInSuccess = await showDialog<bool>(
        context: context,
        builder: (context) => const CheckInDialog(),
      );
      // 无论用户是否签到，都更新启动日期，确保弹窗一天只出现一次
      await prefs.setString('last_launch_date', todayString);
      if (checkInSuccess == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('签到成功！又是元气满满的一天！')),
        );
      }
    }
  }

  // 加载每周信件状态
  Future<void> _loadWeeklyLetter() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final letter = prefs.getString('weekly_ai_letter');
    final letterTimestamp = prefs.getInt('weekly_ai_letter_timestamp') ?? 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final letterDate = DateTime.fromMillisecondsSinceEpoch(letterTimestamp);
    if (letter != null && letterDate.isAfter(startOfWeek)) {
      setState(() {
        _weeklyLetterContent = letter;
        _letterStatus = LetterStatus.available;
      });
    } else if (now.weekday == DateTime.monday) {
      setState(() => _letterStatus = LetterStatus.readyToGenerate);
    } else {
      setState(() => _letterStatus = LetterStatus.notAvailable);
    }
  }

  // 加载AI灵感
  // 文件位置: libs/home_page.dart -> _HomePageContentState

  // +++ 这是修正后的完整方法 +++
  Future<void> _fetchAiWritingPrompt(
      {String model = 'gemini-2.5-flash', bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() => _isLoadingPrompt = true);

    final diaryService = context.read<DiaryService>();
    final today = DateTime.now();
    if (!forceRefresh) {
      final Map<String, dynamic>? cachedPrompt = await diaryService
          .getInspirationForDay(today);
      if (cachedPrompt != null) {
        if (mounted) {
          setState(() {
            _aiWritingPrompt = cachedPrompt;
            _isLoadingPrompt = false;
          });
          print("--- 从数据库缓存加载了每日灵感 ---");
          return;
        }
      }
    }

    print("--- 缓存未命中或强制刷新，正在从网络获取新灵感 ---");
    // VVVV 完整的 try/catch 逻辑从这里开始 VVVV
    try {
      final promptData = await diaryService.generatePersonalizedPrompt(
          modelName: model);
      if (mounted) {
        // 获取到新灵感后，将其完整存入数据库缓存
        await diaryService.saveDailyInspiration(today, promptData);
        setState(() {
          _aiWritingPrompt = promptData;
          _isLoadingPrompt = false;
        });
      }
    } catch (e) {
      print("生成AI提示失败 (回退到默认提示): $e");
      if (mounted) {
        // 当发生任何错误时，提供一个用户友好的默认提示
        setState(() {
          _aiWritingPrompt = {
            'type': 'inspiration',
            'question': '今天，有什么小事让你感到庆幸吗？',
            'sampleAnswer': '比如，早晨的阳光正好，或者路上偶遇了一只可爱的猫。这些小确幸，往往是构成一天美好的重要部分...',
          };
          _isLoadingPrompt = false;
        });
      }
    }
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final dayOfWeek = DateFormat('EEEE', 'zh_CN').format(now);
    final Color cardColor = isDarkMode ? theme.cardColor : theme.colorScheme
        .primaryContainer;
    final Color cardTextColor = isDarkMode
        ? Colors.white.withOpacity(0.8)
        : theme.colorScheme.onPrimaryContainer;
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 24.0, vertical: 16.0),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(15.0),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${now.day}',
                    style: TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                        color: cardTextColor,
                        height: 1)),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dayOfWeek,
                        style: TextStyle(
                            fontSize: 18,
                            color: cardTextColor,
                            fontWeight: FontWeight.w600)),
                    Text('${now.year} / ${now.month}',
                        style: TextStyle(fontSize: 18, color: cardTextColor)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // *** 修改点 3: 使用新的独立组件 ***
          const _DailyQuoteSection(),
        ],
      ),
    );
  }

  Widget _buildAiPromptPlaceholder() {
    final isDarkMode = Theme
        .of(context)
        .brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Shimmer.fromColors(
        baseColor: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
        highlightColor: isDarkMode ? Colors.grey[700]! : Colors.grey[100]!,
        child: Card(
          elevation: 2.0,
          child: Container(
            height: 150, // 给一个固定高度
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 50, height: 12, color: Colors.white),
                const SizedBox(height: 12),
                Container(
                    width: double.infinity, height: 16, color: Colors.white),
                const SizedBox(height: 8),
                Container(width: MediaQuery
                    .of(context)
                    .size
                    .width * 0.5, height: 16, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 文件位置: libs/home_page.dart -> _HomePageContentState

  Widget _buildWeeklyLetterCard() {
    switch (_letterStatus) {
      case LetterStatus.readyToGenerate:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Card(
            color: Theme
                .of(context)
                .colorScheme
                .primaryContainer,
            child: InkWell(
              onTap: () async { // Make onTap async
                if (!mounted) return;
                setState(() => _letterStatus = LetterStatus.generating);
                // The logic for generating the letter itself will be added later
                // For now, it just simulates the process
                try {
                  final diaryService = context.read<DiaryService>();
                  final entries = await diaryService.getEntriesForDateRange(
                    DateTimeRange(
                        start: DateTime.now().subtract(const Duration(days: 7)),
                        end: DateTime.now()),
                  );
                  String prompt;
                  if (entries.isEmpty) {
                    prompt = """
                  你是一个温暖、充满智慧的“日记小精灵”，也是我的朋友。
                  我过去一周没有写下任何日记。请为我写一封简短的信，表达你的关心。
                  在信中，你可以：
                  - 问候我，表达你有些想念我。
                  - 温柔地猜测我可能在忙于生活，或者遇到了什么挑战。
                  - 不要给我压力，只需告诉我，无论何时想倾诉，你都在。
                  - 以“你忠实的朋友，日记小精灵”结尾。
                  - **请使用Markdown格式进行排版，例如换行来分段，让信件更易读。**
                  - 信件格式严格按照信件格式要求来，务必要让读者感受到亲切与温暖感
                  """;
                  } else {
                    final buffer = StringBuffer();
                    buffer.writeln("这是我过去一周的日记：\n");
                    for (final entry in entries) {
                      buffer.writeln(
                          "- ${DateFormat('E, M月d日', 'zh_CN').format(
                              entry.date)}: ${entry.text.substring(0,
                              (entry.text.length > 80) ? 80 : entry.text
                                  .length)}...");
                    }
                    prompt = """
                  你是一个温暖、充满智慧的“日记小精灵”。请阅读我过去一周的日记摘要，并为我写一封简短的信。
                  信的风格要像一位亲密的朋友，充满鼓励和洞察力。你可以：
                  - 总结我上周的核心情绪或主题。
                  - 鼓励我在本周继续努力或尝试新事物。
                  - 以“你忠实的朋友，日记小精灵”结尾。
                  - 信件格式严格按照信件格式要求来，务必要让读者感受到亲切与温暖感

                  我的日记摘要如下：
                  ${buffer.toString()}
                  """;
                  }
                  final geminiService = GeminiServiceLocal();
                  final prefs = await SharedPreferences.getInstance();
                  final modelName = prefs.getString('weekly_letter_model') ??
                      'gemini-2.5-flash';
                  final (responseText, _) = await geminiService
                      .generateResponse(
                      [Content.text(prompt)], modelName: modelName);
                  if (responseText == null || responseText.isEmpty) {
                    throw Exception("AI未能生成有效的信件内容。");
                  }
                  await prefs.setString('weekly_ai_letter', responseText);
                  await prefs.setInt('weekly_ai_letter_timestamp', DateTime
                      .now()
                      .millisecondsSinceEpoch);
                  await context.read<DiaryService>().saveWeeklyLetter(
                      responseText);
                  if (mounted) {
                    setState(() {
                      _weeklyLetterContent = responseText;
                      _letterStatus = LetterStatus.available;
                    });
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('信件生成失败: $e')));
                    setState(() =>
                    _letterStatus = LetterStatus.readyToGenerate);
                  }
                }
              },
              child: const Padding(
                padding: EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_stories_outlined),
                    SizedBox(width: 12),
                    Text("接受小精灵的来信",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        );
      case LetterStatus.generating:
        return _buildWeeklyLetterPlaceholder();
      case LetterStatus.available:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() => _showLetter = !_showLetter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _showLetter
                                  ? Icons.mark_email_read_outlined
                                  : Icons.email_outlined,
                              color: Theme
                                  .of(context)
                                  .colorScheme
                                  .primary,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              "来自AI伙伴的一封信",
                              style: Theme
                                  .of(context)
                                  .textTheme
                                  .titleMedium,
                            ),
                          ],
                        ),
                        Icon(_showLetter ? Icons.keyboard_arrow_up : Icons
                            .keyboard_arrow_down),
                      ],
                    ),
                    if (_showLetter) ...[
                      const Divider(height: 24),
                      MarkdownBody(
                        data: _weeklyLetterContent ?? '',
                        styleSheet: MarkdownStyleSheet.fromTheme(
                            Theme.of(context)).copyWith(
                          p: Theme
                              .of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(height: 1.6),
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            ),
          ),
        );
      case LetterStatus.notAvailable:
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildWeeklyLetterPlaceholder() {
    final isDarkMode = Theme
        .of(context)
        .brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Shimmer.fromColors(
        baseColor: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
        highlightColor: isDarkMode ? Colors.grey[700]! : Colors.grey[100]!,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 24, height: 24, color: Colors.white),
                const SizedBox(width: 12),
                Container(width: 200, height: 16, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFestivalSection() {
    return Consumer<FestivalProvider>(
      builder: (context, festivalProvider, child) {
        if (festivalProvider.isLoading) {
          return const SizedBox(
              height: 160, child: Center(child: CircularProgressIndicator()));
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
              return _buildFestivalCard(festivals[index], index);
            },
            options: cs.CarouselOptions(
              height: 120,
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

  // 文件位置: libs/home_page.dart -> _HomePageContentState

  Widget _buildFestivalCard(Map<String, dynamic> festival, int index) {
    final int daysUntil = festival['daysUntil'];
    final String dateFormatted = DateFormat('M月d日').format(festival['date']);
    final theme = Theme.of(context);
    final cardColor = theme.colorScheme.primaryContainer;
    final textColor = theme.colorScheme.onPrimaryContainer;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FestivalsPage()));
      },
      child: Container(
        // VVVV 1. 大幅减小垂直外边距，为卡片争取更多空间 VVVV
        margin: const EdgeInsets.symmetric(vertical: 4), // 原为 10
        // VVVV 2. 减小垂直内边距 VVVV
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), // 原为 12.0
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: cardColor.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    festival['name'],
                    // VVVV 3. 再次减小字号 VVVV
                    style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold), // 原为 20
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2), // 稍微减小间距
                  Text(
                    dateFormatted,
                    style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 12), // 原为 14
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              daysUntil == 0 ? '今天' : '$daysUntil 天后',
              textAlign: TextAlign.center,
              // VVVV 4. 再次减小字号 VVVV
              style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w300, height: 1.2), // 原为 24
            ),
          ],
        ),
      ),
    );
  }

  // 文件位置: libs/home_page.dart -> _HomePageContentState

  Widget _buildOnThisDaySection() {
    final diaryService = context.read<DiaryService>();
    return FutureBuilder<List<List<DiaryEntry>>>(
      future: Future.wait([
        diaryService.getOnThisDayEntries(),
        diaryService.getMonthlyAnniversaryEntries(),
        diaryService.getHundredDayAnniversaries(),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            !snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }

        final annualEntries = snapshot.data![0];
        final monthlyEntries = snapshot.data![1];
        final hundredDayEntries = snapshot.data![2];

        if (annualEntries.isEmpty && monthlyEntries.isEmpty &&
            hundredDayEntries.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text('时光回顾', style: Theme
                  .of(context)
                  .textTheme
                  .headlineSmall),
              const SizedBox(height: 10),
              if (annualEntries.isNotEmpty)
                _buildOnThisDaySummaryCard(context, annualEntries),
              if (monthlyEntries.isNotEmpty)
                _buildMonthlyAnniversaryCard(context, monthlyEntries),
              if (hundredDayEntries.isNotEmpty)
                ...hundredDayEntries.map((entry) =>
                    _buildHundredDayAnniversaryCard(context, entry)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOnThisDaySummaryCard(BuildContext context,
      List<DiaryEntry> entries) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => OnThisDaySummaryPage(entries: entries),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Icon(
                  Icons.history_edu_outlined, size: 40, color: Colors.amber),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI发现你在往年的今天有 ${entries.length} 篇回忆',
                      style: Theme
                          .of(context)
                          .textTheme
                          .titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '点击这里，让AI为你串联起这些时光的印记...',
                      style: Theme
                          .of(context)
                          .textTheme
                          .bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthlyAnniversaryCard(BuildContext context,
      List<DiaryEntry> entries) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.secondaryContainer.withOpacity(0.5),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  OnThisDaySummaryPage(
                    entries: entries,
                    pageTitle: '那月今日',
                    aiPrompt: """
              你是一个善于发现细节和情感变化的伙伴。下面是我在过去几个月的同一天写的日记。
              请你仔细阅读并比较它们，然后为我撰写一段充满温度的“月度心情快照”。
              在总结中，请帮我：
              1. 直接以第二人称“你”对我说话。
              2. 看看从上个月到这个月，我的关注点和情绪有什么微妙的变化。
              3. 发现我是否有一些以“月”为周期的行为或情绪模式。
              4. 最后，用一句温柔的话，鼓励我继续记录和感受生活。
              我的日记内容如下：
              """,
                  ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(Icons.calendar_month_outlined, size: 40,
                  color: theme.colorScheme.secondary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI发现你在过去有 ${entries.length} 个“那月今日”',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '看看每个月的这个时候，你在经历什么...',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHundredDayAnniversaryCard(BuildContext context,
      DiaryEntry entry) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysDifference = today
        .difference(entry.date)
        .inDays;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.tertiaryContainer.withOpacity(0.5),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  OnThisDaySummaryPage(
                    entries: [entry],
                    pageTitle: '$daysDifference 日回顾',
                    aiPrompt: """
              你是一位善于发现成长的时间旅行者。下面是我在 $daysDifference 天前写的日记。
              请你仔细阅读它，然后为我撰写一段充满惊喜的“百日回顾”。
              在回顾中，请帮我：
              1. 直接以第二人称“你”对我说话。
              2. 提醒我 $daysDifference 天前的我正在经历什么，有什么样的想法和感受。
              3. 尝试对比当时的我与现在的我，可能会有什么不同？提出一个有趣的问题让我思考。
              4. 最后，用一句充满诗意的话，为这次小小的时光之旅画上句号。
              我的日记内容如下：
              """,
                  ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(Icons.all_inclusive_rounded, size: 40,
                  color: theme.colorScheme.tertiary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '一份来自 $daysDifference 天前的“时间胶囊”',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '点击查看那时的你，留下了什么秘密...',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildComfortCard() {
    return FadeIn( // 使用 animate_do 包的动画效果
      duration: const Duration(milliseconds: 500),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Theme.of(context).colorScheme.tertiaryContainer,
        child: InkWell(
          onTap: () {
            // 跳转到我们即将创建的疗伤角页面
            Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ComfortZonePage()));
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(Icons.self_improvement_rounded, size: 40, color: Theme.of(context).colorScheme.onTertiaryContainer),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('需要一个拥抱吗？', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onTertiaryContainer)),
                      const SizedBox(height: 4),
                      Text('这里是你的温柔乡，随时为你敞开。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onTertiaryContainer)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCarousel(DiaryService diaryService) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: diaryService.getRecentImagePathsWithEntries(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator()));
        }

        final imagePairs = snapshot.data!;
        return cs.CarouselSlider.builder(
          itemCount: imagePairs.length,
          itemBuilder: (context, index, realIndex) =>
              _buildCarouselItem(
                imagePairs[index]['entry'] as DiaryEntry,
                imagePairs[index]['imagePath'] as String,
              ),
          options: cs.CarouselOptions(
              aspectRatio: 16 / 9,
              viewportFraction: 0.85,
              enlargeCenterPage: true,
              autoPlay: true),
        );
      },
    );
  }

  Widget _buildCarouselItem(DiaryEntry entry, String imagePath) {
    return GestureDetector(
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => DiaryViewPage(entry: entry))),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5.0),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(12.0)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(File(imagePath), fit: BoxFit.cover),
              Positioned(
                bottom: 0.0,
                left: 0.0,
                right: 0.0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.fromARGB(200, 0, 0, 0),
                        Colors.transparent
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                      vertical: 10.0, horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('yyyy-MM-dd HH:mm').format(
                          entry.creationTime), style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.0,
                          fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(entry.text, style: const TextStyle(
                          color: Colors.white, fontSize: 12.0),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
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

  // 文件位置: libs/home_page.dart -> _HomePageContentState

  Widget _buildHistoryList(DiaryService diaryService) {
    return FutureBuilder<List<DiaryEntry>>(
      future: diaryService.getAllEntriesSorted(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator()));
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
            final bool showMonthSeparator = index == 0 ||
                (entries[index - 1].date.month != currentEntry.date.month ||
                    entries[index - 1].date.year != currentEntry.date.year);
            final bool isInspirationResponse = currentEntry.text
                .trim()
                .startsWith('> ## AI 灵感:');
            return FadeInUp(
              duration: const Duration(milliseconds: 500),
              delay: Duration(milliseconds: index * 50),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showMonthSeparator) _buildMonthSeparator(
                      currentEntry.date),
                  if (isInspirationResponse)
                    _buildInspirationResponseHistoryCard(currentEntry)
                  else
                    _buildHistoryCard(currentEntry, index),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMonthSeparator(DateTime date) {
    final color = Theme
        .of(context)
        .textTheme
        .bodyLarge
        ?.color ??
        Colors.black54;
    return Padding(
      padding: const EdgeInsets.only(left: 20.0, top: 24.0, bottom: 10.0),
      child: Text(
        DateFormat('yyyy年 MMMM', 'zh_CN').format(date),
        style: TextStyle(fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color.withOpacity(0.8)),
      ),
    );
  }

  Widget _buildHistoryCard(DiaryEntry entry, int index) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final subTextColor = theme.colorScheme.onSurface.withOpacity(0.7);

    return InkWell(
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => DiaryViewPage(entry: entry))),
      borderRadius: BorderRadius.circular(15.0),
      child: Card(
        child: SizedBox(
          height: 120,
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(DateFormat('d').format(entry.creationTime),
                        style: TextStyle(fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: subTextColor)),
                    Text(DateFormat('E', 'zh_CN').format(entry.creationTime),
                        style: TextStyle(fontSize: 12, color: subTextColor)),
                    const SizedBox(height: 4),
                    Text(DateFormat('HH:mm').format(entry.creationTime),
                        style: TextStyle(fontSize: 12,
                            color: subTextColor.withOpacity(0.8))),
                  ],
                ),
              ),
              VerticalDivider(width: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: theme.dividerColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    entry.text.isNotEmpty ? entry.text : '(无文字内容)',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: textColor,
                        fontWeight: FontWeight.w400,
                        fontSize: 15,
                        height: 1.4),
                  ),
                ),
              ),
              if (entry.imagePaths.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Image.file(File(entry.imagePaths.first), width: 100,
                        height: 120,
                        fit: BoxFit.cover),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 文件位置: libs/home_page.dart -> _HomePageContentState

  Widget _buildInspirationResponseHistoryCard(DiaryEntry entry) {
    final theme = Theme.of(context);
    String aiPrompt = '';
    String userResponse = '';

    const String sampleAnswerSeparator = "---AI_SAMPLE_ANSWER---";
    String mainContent = entry.text;
    if (entry.text.contains(sampleAnswerSeparator)) {
      mainContent = entry.text.split(sampleAnswerSeparator)[0].trim();
    }
    const String replySeparator = "\n---\n";
    if (mainContent.contains(replySeparator)) {
      final parts = mainContent.split(replySeparator);
      aiPrompt =
          parts[0].replaceAll('> ## AI 灵感:', '').replaceAll('>', '').trim();
      userResponse = parts.length > 1 ? parts[1].trim() : '(无回复内容)';
    } else {
      userResponse = mainContent
          .replaceAll('> ## AI 灵感:', '')
          .replaceAll('>', '')
          .trim();
    }

    return InkWell(
      onTap: () =>
          Navigator.of(context).push(
            MaterialPageRoute(
                builder: (context) => DiaryViewPage(entry: entry)),
          ),
      borderRadius: BorderRadius.circular(15.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.colorScheme.tertiary, width: 1.5),
          borderRadius: BorderRadius.circular(15.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // VVVV  核心修改：使用 MarkdownBody 渲染AI问题 VVVV
              MarkdownBody(
                data: '“$aiPrompt”',
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ),
              const Divider(height: 20),
              // VVVV  核心修改：使用 MarkdownBody 渲染用户回复 VVVV
              MarkdownBody(
                data: userResponse,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


// VVVV 2. 用这个新版本替换旧的 build 方法 VVVV
  // 文件位置: libs/home_page.dart -> _HomePageContentState

  // 文件位置: libs/home_page.dart -> _HomePageContentState

  // 文件位置: libs/home_page.dart -> _HomePageContentState

  // 文件位置: libs/home_page.dart -> _HomePageContentState

  // 文件位置: libs/home_page.dart -> _HomePageContentState class

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final diaryService = context.watch<DiaryService>();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadPageData,
        child: ListView(
          children: [
            _buildHeader(context),
            if (_showComfortCard) _buildComfortCard(),
            Padding(
              padding: const EdgeInsets.only(left: 20.0, top: 16.0),
              child: Text('近期精彩瞬间', style: Theme.of(context).textTheme.headlineSmall),
            ),
            const SizedBox(height: 10),
            _buildCarousel(diaryService),
            const SizedBox(height: 10),

            // --- 将所有可折叠卡片放在一起 ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: ExpansionTile(
                title: const Text('AI 每日灵感'),
                leading: Icon(Icons.auto_awesome_outlined, color: Theme.of(context).colorScheme.tertiary),
                initiallyExpanded: false,
                children: [
                  _isLoadingPrompt
                      ? _buildAiPromptPlaceholder()
                      : AiPromptCard(
                    key: ValueKey(_aiWritingPrompt.hashCode),
                    aiWritingPrompt: _aiWritingPrompt!,
                    onRefresh: (selectedModel, force) {
                      _fetchAiWritingPrompt(model: selectedModel, forceRefresh: force);
                    },
                    onSaveSuccess: () {
                      setState(() {});
                      _fetchAiWritingPrompt();
                    },
                  ),
                ],
              ),
            ),

            _buildMemoryBottleCard(), // <--- VVVV 我们新的“记忆漂流瓶”卡片放在这里 VVVV

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: ExpansionTile(
                title: const Text('每周信件'),
                leading: Icon(Icons.email_outlined, color: Theme.of(context).colorScheme.secondary),
                initiallyExpanded: false,
                children: [
                  _buildWeeklyLetterCard(),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: ExpansionTile(
                title: const Text('近期节日'),
                leading: Icon(Icons.celebration_outlined, color: Theme.of(context).colorScheme.primary),
                initiallyExpanded: false,
                children: [
                  _buildFestivalSection(),
                ],
              ),
            ),

            _buildOnThisDaySection(),
            const SizedBox(height: 20),
            _buildHistoryList(diaryService),
          ],
        ),
      ),
    );
  }
}

// =================================================================
// *** 修改点 1: 创建一个新的、独立的 StatefulWidget 来管理“每日一句” ***
// =================================================================
class _DailyQuoteSection extends StatefulWidget {
  const _DailyQuoteSection();

  @override
  State<_DailyQuoteSection> createState() => _DailyQuoteSectionState();
}

class _DailyQuoteSectionState extends State<_DailyQuoteSection> {
  String _fullQuoteText = "正在获取今日份的灵感...";
  String _currentSentence = "";
  String _currentSource = "";
  bool _isLoadingQuote = true;

  @override
  void initState() {
    super.initState();
    _fetchDailyQuote();
  }

  Future<void> _fetchDailyQuote() async {
    if (!mounted) return;
    setState(() => _isLoadingQuote = true);
    try {
      final url = Uri.parse('https://api.shadiao.pro/pyq');
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final sentence = data['data']['text'] ?? '今天也要开心哦。';
        setState(() {
          _currentSentence = sentence;
          _currentSource = ''; // API不提供来源
          _fullQuoteText = sentence;
        });
      } else {
        throw Exception('Failed to load quote');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentSentence = "可以看看窗外，今天的风很温柔。";
          _currentSource = "";
          _fullQuoteText = _currentSentence;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingQuote = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                child: _isLoadingQuote
                    ? const Padding(
                    padding: EdgeInsets.all(10.0),
                    child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '换一句',
                  onPressed: _fetchDailyQuote,
                ),
              ),
              const SizedBox(width: 16),
              Consumer<FavoritesProvider>(
                builder: (context, favProvider, child) {
                  final isLiked = favProvider.isFavorite(
                      _currentSentence, _currentSource);
                  return SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      tooltip: isLiked ? '取消收藏' : '收藏',
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.redAccent : null,
                      ),
                      onPressed: (_isLoadingQuote || _currentSentence.isEmpty)
                          ? null
                          : () {
                        if (isLiked) {
                          favProvider.removeFavorite(
                              _currentSentence, _currentSource);
                        } else {
                          favProvider.addFavorite(
                              _currentSentence, _currentSource);
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
}


// 文件位置: libs/home_page.dart (文件最底部)

// =================================================================
// VVVV  这是一个全新的、独立的、功能完整的 AI 灵感卡片小部件 VVVV
// =================================================================
class AiPromptCard extends StatefulWidget {
  final Map<String, dynamic> aiWritingPrompt;
  final Function(String, bool) onRefresh;
  final VoidCallback onSaveSuccess;

  const AiPromptCard({
    super.key,
    required this.aiWritingPrompt,
    required this.onRefresh,
    required this.onSaveSuccess,
  });
  @override
  State<AiPromptCard> createState() => _AiPromptCardState();
}

class _AiPromptCardState extends State<AiPromptCard> {
  // 这个小部件自己管理自己的UI状态
  bool _isExpanded = false;
  bool _isReplying = false;
  String _selectedModel = 'gemini-2.5-flash';
  final List<String> _availableModels = const ['gemini-2.5-flash', 'gemini-2.5-pro'];
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveResponse() async {
    final responseText = _controller.text.trim();
    final promptContent = widget.aiWritingPrompt['question'] ?? widget.aiWritingPrompt['text'];
    final sampleAnswer = widget.aiWritingPrompt['sampleAnswer']; // 获取AI的示例回答

    if (responseText.isEmpty || promptContent == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('回复内容不能为空哦')));
      return;
    }

    try {
      // VVVV 核心修改：构建新的、包含折叠信息的文本格式 VVVV
      final StringBuffer buffer = StringBuffer();
      buffer.writeln("> ## AI 灵感:");
      buffer.writeln("> $promptContent");
      buffer.writeln("\n---\n");
      buffer.writeln(responseText); // 您的回复

      // 如果存在AI的示例回答，就将其附加到末尾
      if (sampleAnswer != null && sampleAnswer.isNotEmpty) {
        buffer.writeln("\n\n---AI_SAMPLE_ANSWER---");
        buffer.writeln(sampleAnswer);
      }

      final fullDiaryText = buffer.toString();
      // ^^^^ 文本构建结束 ^^^^

      final diaryService = context.read<DiaryService>();
      final newEntry = DiaryEntry(diaryId: '', text: fullDiaryText, date: DateTime.now(), creationTime: DateTime.now());
      await diaryService.addEntry(newEntry);

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('灵感回复已保存为一篇新日记！')));

      widget.onSaveSuccess();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.aiWritingPrompt['type'] ?? 'inspiration';
    final title = type == 'check_in' ? '来自小精灵的关心' : (type == 'welcome' ? '来自小精灵的欢迎' : '每日灵感');
    final questionText = widget.aiWritingPrompt['question'] ?? widget.aiWritingPrompt['text'] ?? '';
    final sampleAnswerText = widget.aiWritingPrompt['sampleAnswer'];
    return Card(
      elevation: 2.0,
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: GestureDetector(
        onTap: () {
          if (sampleAnswerText != null && !_isReplying) {
            setState(() => _isExpanded = !_isExpanded);
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isReplying
                ? _buildResponseView(questionText)
                : _buildInspirationView(title, questionText, sampleAnswerText),
          ),
        ),
      ),
    );
  }

  Widget _buildInspirationView(String title, String questionText, String? sampleAnswerText) {
    return Column(
      key: const ValueKey('inspiration'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onTertiaryContainer)),
        const SizedBox(height: 8),
        MarkdownBody(data: questionText, styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(p: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onTertiaryContainer, height: 1.5))),

        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _isExpanded && sampleAnswerText != null
              ? Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 12.0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
            child: MarkdownBody(data: sampleAnswerText, styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onTertiaryContainer, fontStyle: FontStyle.italic, height: 1.5))),
          )
              : const SizedBox.shrink(),
        ),
        const Divider(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            DropdownButton<String>(
              value: _selectedModel,
              items: _availableModels.map((m) => DropdownMenuItem<String>(value: m, child: Text(m.contains('pro') ? '专业' : '快速', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onTertiaryContainer)))).toList(),
              onChanged: (m) => setState(() => _selectedModel = m!),
              underline: const SizedBox(),
              icon: Icon(Icons.model_training_outlined, size: 20, color: Theme.of(context).colorScheme.onTertiaryContainer.withOpacity(0.7)),
            ),
            // 文件位置: lib/home_page.dart -> _AiPromptCardState -> _buildInspirationView 方法内
// ...
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: '换个提示',
              // VVVV  修改 onPressed 回调 VVVV
              onPressed: () => widget.onRefresh(_selectedModel, true), // 添加 true 参数
              color: Theme.of(context).colorScheme.onTertiaryContainer.withOpacity(0.7),
            ),
// ...
            const Spacer(),
            ElevatedButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('动笔'),
              onPressed: () => setState(() => _isReplying = true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResponseView(String questionText) {
    return Column(
      key: const ValueKey('response'),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text("回应灵感: \"$questionText\"", style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 5,
          decoration: InputDecoration(hintText: '在此写下你的思绪...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), fillColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.5), filled: true),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(child: const Text('取消'), onPressed: () => setState(() => _isReplying = false)),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _saveResponse, child: const Text('保存回复')),
          ],
        ),
      ],
    );
  }
}