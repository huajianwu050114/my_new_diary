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
import 'package:my_new_diary/diary_model.dart';
// In lib/home_page.dart, at the top
import 'on_this_day_summary_page.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gemini_service_local.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'letters_archive_page.dart';
import 'package:shimmer/shimmer.dart';
import 'reflections_archive_page.dart';
import 'package:animate_do/animate_do.dart';
import 'check_in_dialog.dart';


enum LetterStatus {
  notAvailable,
  readyToGenerate,
  generating,
  available,
}

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

  // --- State Variables ---
  String _fullQuoteText = "正在获取今日份的灵感...";
  String _currentSentence = "";
  String _currentSource = "";
  bool _isLoadingQuote = true;

  Map<String, dynamic>? _aiWritingPrompt; // <--- 修正1: 类型已从 Map<String, String>? 改为 Map<String, dynamic>?
  bool _isLoadingPrompt = false;    // VVV 1. 初始状态改为 false
  String _selectedInspirationModel = 'gemini-2.5-flash'; // 默认使用快速模型
  final List<String> _availableModels = const ['gemini-2.5-flash', 'gemini-2.5-pro'];
  bool _isRespondingToPrompt = false; //
  final TextEditingController _promptResponseController = TextEditingController();
  bool _isAiAnswerExpanded = false;

  LetterStatus _letterStatus = LetterStatus.notAvailable;
  String? _weeklyLetterContent;
  bool _showLetter = false;
  String _selectedLetterModel = 'gemini-2.5-pro'; // 默认使用专业模型


  // VVV 2. 新增一个Future来统一管理页面初始化加载 VVV
  Future<void>? _pageDataFuture;

  @override
  void initState() {
    super.initState();
    // VVV 3. 将所有初始化逻辑放入一个新的方法中 VVV
    _pageDataFuture = _loadPageData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleDailyCheckIn();
    });
  }
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

      // 如果签到成功，可以给一个小的反馈
      if (checkInSuccess == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('签到成功！又是元气满满的一天！')),
        );
      }
    }
  }

  // VVV 4. 创建新的页面数据加载方法 VVV
  Future<void> _loadPageData() async {
    // 这个方法负责加载那些不依赖AI的、快速的基础数据
    await _fetchDailyQuote();
    await _loadWeeklyLetter();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 不在这里 await，让它在后台悄悄加载
      _fetchAiWritingPrompt();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget _buildAiPromptPlaceholder() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Shimmer.fromColors(
        baseColor: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
        highlightColor: isDarkMode ? Colors.grey[700]! : Colors.grey[100]!,
        child: Card(
          elevation: 2.0,
          color: Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.5),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 50, height: 12, color: Colors.white),
                const SizedBox(height: 12),
                Container(width: double.infinity, height: 16, color: Colors.white),
                const SizedBox(height: 8),
                Container(width: MediaQuery.of(context).size.width * 0.5, height: 16, color: Colors.white),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(width: 48, height: 48, color: Colors.white),
                    const SizedBox(width: 8),
                    Container(width: 110, height: 40, decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    )),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

// VVV Also add this missing placeholder for the Weekly Letter card VVV
  Widget _buildWeeklyLetterPlaceholder() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Shimmer.fromColors(
        baseColor: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
        highlightColor: isDarkMode ? Colors.grey[700]! : Colors.grey[100]!,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(width: 24, height: 24, color: Colors.white),
                const SizedBox(width: 12),
                Container(width: 150, height: 16, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOnThisDaySummaryCard(BuildContext context,
      List<DiaryEntry> entries) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // 点击后导航到我们即将创建的新页面
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

  // In lib/home_page.dart -> class _HomePageContentState

// VVV 用这个修正后的版本，完整替换现有的方法 VVV
  // 文件位置: lib/home_page.dart -> _HomePageContentState

  Future<void> _saveInspirationResponse() async {
    final responseText = _promptResponseController.text.trim();

    // VVVV  核心修正：更智能地获取灵感原文 VVVV
    final promptText = _aiWritingPrompt?['question'] ?? _aiWritingPrompt?['text'];

    // VVVV  核心修正：使用新的 promptText 变量来做检查 VVVV
    if (responseText.isEmpty || promptText == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('回复内容不能为空哦')));
      return;
    }

    try {
      final diaryService = context.read<DiaryService>();

      // VVVV  核心修正：使用新的 promptText 变量来构建日记 VVVV
      final fullDiaryText = """
> ## AI 灵感:
> $promptText

---

$responseText
""";
      final newEntry = DiaryEntry(diaryId: '', text: fullDiaryText, date: DateTime.now(), creationTime: DateTime.now());
      await diaryService.addEntry(newEntry);

      // 保存灵感本身到数据库（用于日历等处显示）
      await diaryService.saveDailyInspiration(DateTime.now(), promptText);

      _promptResponseController.clear();
      setState(() {
        _isRespondingToPrompt = false;
        _aiWritingPrompt = null;
      });

      _fetchAiWritingPrompt();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('灵感回复已保存为一篇新日记！')));
      }
    } catch (e) {
      print("--- 保存日记失败 --- \nError: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败，错误: $e')));
      }
    }
  }

  Future<void> _loadWeeklyLetter() async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final letter = prefs.getString('weekly_ai_letter');
    final letterTimestamp = prefs.getInt('weekly_ai_letter_timestamp') ?? 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 计算本周的星期一
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final letterDate = DateTime.fromMillisecondsSinceEpoch(letterTimestamp);

    // 检查是否存在本周已生成的信件
    if (letter != null && letterDate.isAfter(startOfWeek)) {
      setState(() {
        _weeklyLetterContent = letter;
        _letterStatus = LetterStatus.available; // 状态：已生成
      });
    }
    // 如果今天是周一，且还没有本周的信件
    else if (now.weekday == DateTime.monday)
    {
      setState(() {
        _letterStatus = LetterStatus.readyToGenerate; // 状态：准备生成
      });
    }
    // 其他情况（非周一，且没有本周信件）
    else {
      setState(() {
        _letterStatus = LetterStatus.notAvailable; // 状态：不可用
      });
    }
  }

  // In lib/home_page.dart -> inside _HomePageContentState class

// VVV 用这个全新的、充满人情味的版本替换 VVV
  Future<void> _generateAndSaveLetter() async {
    if (!mounted) return;
    setState(() => _letterStatus = LetterStatus.generating);

    try {
      final diaryService = context.read<DiaryService>();
      final entries = await diaryService.getEntriesForDateRange(
        DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now()),
      );

      String prompt;

      // VVV 核心修改：根据是否有日记，来决定给AI下达怎样的指令 VVV
      if (entries.isEmpty) {
        // 如果没有日记，生成一封关心的信
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
        // 如果有日记，按原计划生成总结
        final buffer = StringBuffer();
        buffer.writeln("这是我过去一周的日记：\n");
        for (final entry in entries) {
          buffer.writeln("- ${DateFormat('E, M月d日', 'zh_CN').format(entry.date)}: ${entry.text.substring(0, (entry.text.length > 80) ? 80 : entry.text.length)}...");
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
      final modelName = prefs.getString('weekly_letter_model') ?? 'gemini-2.5-pro';

      final (responseText, _) = await geminiService.generateResponse([Content.text(prompt)], modelName: modelName);

      if (responseText == null || responseText.isEmpty) {
        throw Exception("AI未能生成有效的信件内容。");
      }

      // 成功后，保存信件并更新UI (这部分逻辑不变)
      await prefs.setString('weekly_ai_letter', responseText);
      await prefs.setInt('weekly_ai_letter_timestamp', DateTime.now().millisecondsSinceEpoch);
      await context.read<DiaryService>().saveWeeklyLetter(responseText);

      if (mounted) {
        setState(() {
          _weeklyLetterContent = responseText;
          _letterStatus = LetterStatus.available;
        });
      }
    } catch (e) {
      print("生成信件失败: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('信件生成失败: $e')));
        setState(() {
          _letterStatus = LetterStatus.readyToGenerate;
        });
      }
    }
  }

  Widget _buildWeeklyLetterCard() {
    // 根据当前状态决定显示什么
    switch (_letterStatus) {
      case LetterStatus.readyToGenerate:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: InkWell(
              onTap: _generateAndSaveLetter,
              child: const Padding(
                padding: EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_stories_outlined),
                    SizedBox(width: 12),
                    Text("接受小精灵的来信", style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        );

      case LetterStatus.generating:
      // 状态：正在生成 -> 显示静默提示
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Card(
            color: Theme
                .of(context)
                .colorScheme
                .surfaceVariant,
            child: const Padding(
              padding: EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.0)),
                  SizedBox(width: 16),
                  Text("正在接收小精灵的来信，请稍候..."),
                ],
              ),
            ),
          ),
        );

      case LetterStatus.available:
      // 状态：已生成 -> 显示我们之前设计的“信封”
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
                        Icon(
                          _showLetter ? Icons.keyboard_arrow_up : Icons
                              .keyboard_arrow_down,
                        ),
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
      // 状态：不可用 -> 什么都不显示
        return const SizedBox.shrink();
    }
  }

  Future<void> _fetchAiWritingPrompt() async {
    if (!mounted) return;
    setState(() {
      _isLoadingPrompt = true;
      _isAiAnswerExpanded = false; // VVV 新增：重置展开状态 VVV
    });

    final diaryService = context.read<DiaryService>();
    final today = DateTime.now();

    // 1. 先尝试从数据库获取今天的灵感
    final String? cachedPrompt = await diaryService.getInspirationForDay(today);

    if (cachedPrompt != null && cachedPrompt.isNotEmpty) {
      // 2. 如果数据库中存在，直接使用它
      if (mounted) {
        setState(() {
          // 我们将它包装成与AI返回时相同的格式
          _aiWritingPrompt = {'type': 'inspiration', 'text': cachedPrompt};
          _isLoadingPrompt = false;
        });
      }
    } else {
      // 3. 如果数据库中没有，才向AI请求新的灵感
      final promptData = await diaryService.generatePersonalizedPrompt(modelName: _selectedInspirationModel);
      if (mounted) {
        // 4. 获取到新灵感后，先将其保存到数据库
        if (promptData['text'] != null && promptData['text']!.isNotEmpty) {
          await diaryService.saveDailyInspiration(today, promptData['text']!);
        }

        // 5. 更新UI
        setState(() {
          _aiWritingPrompt = promptData;
          _isLoadingPrompt = false;
        });
      }
    }
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
            style: Theme
                .of(context)
                .textTheme
                .bodySmall
                ?.copyWith(height: 1.5),
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
                    ? const Padding(padding: EdgeInsets.all(10.0),
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
                      // 正在加载或句子为空时，禁用收藏按钮
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

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final dayOfWeek = DateFormat('EEEE', 'zh_CN').format(now);

    // VVV 关键修改：不再使用独立的渐变色，而是直接从主题获取颜色 VVV
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
              // 使用从主题获取的纯色
              color: cardColor,
              borderRadius: BorderRadius.circular(15.0),
              // 可以保留一个非常微妙的阴影或边框以增加质感
              border: isDarkMode
                  ? Border.all(color: const Color(0xFF30363D))
                  : null,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4)
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    '${now.day}',
                    style: TextStyle(fontSize: 64,
                        fontWeight: FontWeight.bold,
                        color: cardTextColor,
                        height: 1)
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dayOfWeek, style: TextStyle(fontSize: 18,
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
              // Pass the entire ThemeProvider to the card builder
              return _buildFestivalCard(festivals[index], index);
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
  Widget _buildFestivalCard(Map<String, dynamic> festival, int index) {
    final int daysUntil = festival['daysUntil'];
    final String dateFormatted = DateFormat('M月d日').format(festival['date']);
    final theme = Theme.of(context);

    // 使用来自 ColorScheme 的颜色，而不是固定的渐变色
    final cardColor = theme.colorScheme.primaryContainer;
    final textColor = theme.colorScheme.onPrimaryContainer;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FestivalsPage()));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.all(16.0),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  festival['name'],
                  style: TextStyle(
                    color: textColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateFormatted,
                  style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 14),
                ),
              ],
            ),
            Text(
              daysUntil == 0 ? '今天' : '$daysUntil\n天后',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
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

  Widget _buildMonthlyAnniversaryCard(BuildContext context,
      List<DiaryEntry> entries) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      color: Colors.blueGrey.withOpacity(0.2), // 使用不同颜色以作区分
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              // 我们复用之前的总结页面，只是传入了不同的标题和数据
              builder: (context) =>
                  OnThisDaySummaryPage(
                    entries: entries,
                    // VVV 传递一个自定义标题 VVV
                    pageTitle: '那月今日',
                    // VVV 传递一个自定义的AI Prompt VVV
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
              const Icon(Icons.calendar_month_outlined, size: 40,
                  color: Colors.lightBlue),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI发现你在过去有 ${entries.length} 个“那月今日”',
                      style: Theme
                          .of(context)
                          .textTheme
                          .titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '看看每个月的这个时候，你在经历什么...',
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


  // ... (all other methods like _buildOnThisDaySection, _buildHistoryList, etc., remain the same) ...
  Widget _buildOnThisDaySection() {
    final diaryService = context.read<DiaryService>();
    return FutureBuilder<List<List<DiaryEntry>>>(
      // VVV 1. 现在 Future.wait 同时执行三个查询 VVV
      future: Future.wait([
        diaryService.getOnThisDayEntries(),
        diaryService.getMonthlyAnniversaryEntries(),
        diaryService.getHundredDayAnniversaries(), // <-- 新增的查询
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            !snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }

        final annualEntries = snapshot.data![0];
        final monthlyEntries = snapshot.data![1];
        final hundredDayEntries = snapshot.data![2]; // <-- 获取百日纪念的数据

        // 如果三种都没有，则不显示
        if (annualEntries.isEmpty && monthlyEntries.isEmpty &&
            hundredDayEntries.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('时光回顾', style: Theme
                  .of(context)
                  .textTheme
                  .headlineSmall),
              const SizedBox(height: 10),

              if (annualEntries.isNotEmpty)
                _buildOnThisDaySummaryCard(context, annualEntries),

              if (monthlyEntries.isNotEmpty)
                _buildMonthlyAnniversaryCard(context, monthlyEntries),

              // VVV 2. 如果有“百日纪念”，就显示它的卡片 VVV
              if (hundredDayEntries.isNotEmpty)
                ...hundredDayEntries.map((entry) =>
                    _buildHundredDayAnniversaryCard(context, entry)),

              const SizedBox(height: 10),
              const Divider(),
            ],
          ),
        );
      },
    );
  }


  Widget _buildOnThisDayCard(DiaryEntry entry) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => DiaryViewPage(entry: entry))),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Container(
                width: 80,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme
                      .of(context)
                      .colorScheme
                      .primaryContainer,
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
                        color: Theme
                            .of(context)
                            .colorScheme
                            .onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('M月d日', 'zh_CN').format(entry.date),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme
                            .of(context)
                            .colorScheme
                            .onPrimaryContainer
                            .withOpacity(0.8),
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
    return FutureBuilder<List<Map<String, dynamic>>>(
      // 调用我们新的方法
      future: diaryService.getRecentImagePathsWithEntries(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty)
          return const SizedBox.shrink();
        if (snapshot.connectionState == ConnectionState.waiting)
          return const SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator()));

        final imagePairs = snapshot.data!;
        return cs.CarouselSlider.builder(
          itemCount: imagePairs.length, // 轮播图的数量现在是图片的总数
          itemBuilder: (context, index, realIndex) =>
              _buildCarouselItem(
                imagePairs[index]['entry'] as DiaryEntry,
                imagePairs[index]['imagePath'] as String,
              ),
          options: cs.CarouselOptions(aspectRatio: 16 / 9,
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
              // 使用传入的、正确的 imagePath
              Image.file(File(imagePath), fit: BoxFit.cover),
              Positioned(
                bottom: 0.0, left: 0.0, right: 0.0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.fromARGB(200, 0, 0, 0),
                        Colors.transparent
                      ],
                      begin: Alignment.bottomCenter, end: Alignment.topCenter,
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

  Widget _buildHistoryList(DiaryService diaryService) {
    return FutureBuilder<List<DiaryEntry>>(
      future: diaryService.getAllEntriesSorted(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: Padding(padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator()));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(
            child: Padding(padding: EdgeInsets.symmetric(vertical: 50.0),
                child: Text('还没有任何日记，开始记录第一篇吧！')));

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

            final bool isInspirationResponse = currentEntry.text.trim().startsWith('> ## AI 灵感:');

            return FadeInUp(
                duration: const Duration(milliseconds: 500),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showMonthSeparator) _buildMonthSeparator(currentEntry.date),
                if (isInspirationResponse)
                  _buildInspirationResponseHistoryCard(currentEntry)
                else
                  _buildHistoryCard(currentEntry, index),
              ],
            ));
          },
        );
      },
    );
  }

  Widget _buildHistoryCard(DiaryEntry entry, int index) {
    final theme = Theme.of(context);

    // The Card widget will now automatically get its color and shape from the CardTheme
    // we defined in lib/themes.dart. We no longer need custom decoration here.

    // We derive text colors from the theme to ensure they are always readable.
    final textColor = theme.colorScheme.onSurface;
    final subTextColor = theme.colorScheme.onSurface.withOpacity(0.7);

    return InkWell(
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => DiaryViewPage(entry: entry))),
      // Use the Card's default splash effect by wrapping it in InkWell
      borderRadius: BorderRadius.circular(15.0),
      child: Card(
        // No custom decoration needed here anymore.
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
                  color: theme.dividerColor), // Use the theme's divider color
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    entry.text.isNotEmpty ? entry.text : '(无文字内容)',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: textColor, // Use theme-aware color
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

  // In lib/home_page.dart -> inside _HomePageContentState class

  // In lib/home_page.dart -> inside _HomePageContentState class

  // lib/home_page.dart -> _HomePageContentState

  Widget _buildAiPromptCard() {
    if (_isLoadingPrompt) {
      return _buildAiPromptPlaceholder();
    }

    if (_aiWritingPrompt != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Card(
          elevation: 2.0,
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            // 使用动画切换器来平滑地在“灵感视图”和“回复视图”之间切换
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _isRespondingToPrompt
                  ? _buildResponseView(_aiWritingPrompt!['question'] ?? '')
                  : _buildInspirationView(
                _aiWritingPrompt!['type'],
                _aiWritingPrompt!['question'] ?? _aiWritingPrompt!['text'] ?? '',
                _aiWritingPrompt!['sampleAnswer'],
              ),
            ),
          ),
        ),
      );
    }

    // 如果没有灵感，则不显示任何内容
    return const SizedBox.shrink();
  }

// VVVV 方法 2: 构建“灵感展示”视图的辅助方法 VVVV
  Widget _buildInspirationView(String type, String questionText, String? sampleAnswerText) {
    final title = type == 'check_in' ? '来自小精灵的关心' : (type == 'welcome' ? '来自小精灵的欢迎' : '每日灵感');

    return Column(
      key: const ValueKey('inspiration_view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onTertiaryContainer)),
        const SizedBox(height: 8),
        MarkdownBody(
          data: questionText,
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onTertiaryContainer, height: 1.5),
          ),
        ),
        if (sampleAnswerText != null) ...[
          const SizedBox(height: 12),
          // 使用 AnimatedSize 来实现平滑的展开和收起动画
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isAiAnswerExpanded
                ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
              child: MarkdownBody(data: sampleAnswerText, styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onTertiaryContainer, fontStyle: FontStyle.italic, height: 1.5))),
            )
                : const SizedBox.shrink(),
          ),
        ],
        const Divider(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (sampleAnswerText != null)
              TextButton.icon(
                onPressed: () {
                  setState(() => _isAiAnswerExpanded = !_isAiAnswerExpanded);
                },
                icon: Icon(_isAiAnswerExpanded ? Icons.unfold_less : Icons.unfold_more, size: 20),
                label: Text(_isAiAnswerExpanded ? '收起' : 'AI示例'),
              ),
            const Spacer(),
            // 这里是模型选择和刷新按钮
            DropdownButton<String>(
              value: _selectedInspirationModel,
              items: _availableModels.map((String model) => DropdownMenuItem<String>(value: model, child: Text(model.contains('pro') ? '专业' : '快速', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onTertiaryContainer)))).toList(),
              onChanged: (String? newModel) {
                if (newModel != null && newModel != _selectedInspirationModel) {
                  setState(() => _selectedInspirationModel = newModel);
                  _fetchAiWritingPrompt();
                }
              },
              underline: const SizedBox(),
              icon: Icon(Icons.model_training_outlined, size: 20, color: Theme.of(context).colorScheme.onTertiaryContainer.withOpacity(0.7)),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: '换个提示',
              onPressed: _fetchAiWritingPrompt,
              color: Theme.of(context).colorScheme.onTertiaryContainer.withOpacity(0.7),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('动笔'),
              onPressed: () => setState(() => _isRespondingToPrompt = true),
            ),
          ],
        ),
      ],
    );
  }

// VVVV 方法 3: 构建“用户回复”视图的辅助方法 VVVV
  // 文件位置: lib/home_page.dart -> _HomePageContentState

  Widget _buildResponseView(String questionText) {
    return Column(
      key: const ValueKey('response_view'),
      crossAxisAlignment: CrossAxisAlignment.start, // 整体左对齐
      children: [
        // VVVV  全新的引导语/问题回顾区域 VVVV
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.05), // 使用一个柔和的背景色
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "回应灵感: \"$questionText\"", // 完整显示问题
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
        // ^^^^ 引导语区域结束 ^^^^

        TextField(
          controller: _promptResponseController,
          autofocus: true,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: '在此写下你的思绪...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            fillColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.5),
            filled: true,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(child: const Text('取消'), onPressed: () => setState(() => _isRespondingToPrompt = false)),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _saveInspirationResponse, child: const Text('保存回复')),
          ],
        ),
      ],
    );
  }

// VVVV  新增的辅助方法2: 构建用户回复视图 VVVV


  Widget _buildInspirationResponseHistoryCard(DiaryEntry entry) {
    final theme = Theme.of(context);

    // 1. 解析出AI灵感和用户回复
    String aiPrompt = '';
    String userResponse = entry.text;
    if (entry.text.contains('---')) {
      final parts = entry.text.split('---');
      aiPrompt = parts.first.replaceAll('> ## AI 灵感:', '').replaceAll('>', '').trim();
      userResponse = parts.last.trim();
    }

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => DiaryViewPage(entry: entry)),
      ),
      child: Card(
        // 2. 使用独特的颜色和边框来突出显示
        elevation: 2,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.colorScheme.tertiary, width: 1.5),
          borderRadius: BorderRadius.circular(15.0),
        ),
        child: Container(
          padding: const EdgeInsets.all(16.0),
          // 3. 使用Column来垂直排列“问题”和“回答”
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // AI提问部分
              Text(
                '“$aiPrompt”', // 加上引号，更像引用
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: theme.textTheme.bodySmall?.color,
                  fontSize: 13,
                ),
              ),
              const Divider(height: 20),
              // 您的回答部分
              Text(
                userResponse,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHundredDayAnniversaryCard(BuildContext context,
      DiaryEntry entry) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysDifference = today
        .difference(entry.date)
        .inDays;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      color: Colors.deepPurple.withOpacity(0.2), // 使用紫色系以作区分
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  OnThisDaySummaryPage(
                    entries: [entry], // 百日纪念通常只有一篇日记
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
              const Icon(Icons.all_inclusive_rounded, size: 40,
                  color: Colors.purpleAccent),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '一份来自 $daysDifference 天前的“时间胶囊”',
                      style: Theme
                          .of(context)
                          .textTheme
                          .titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '点击查看那时的你，留下了什么秘密...',
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

  Widget _buildMonthSeparator(DateTime date) {
    final color = Theme
        .of(context)
        .textTheme
        .bodyLarge
        ?.color ?? Colors.black54;
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final diaryService = context.watch<DiaryService>();

    final promptType = _aiWritingPrompt?['type'] ?? 'inspiration';
    final promptText = _aiWritingPrompt?['text'] ?? '';

    return SafeArea(
      top: false,
      // VVV 6. 使用一个 FutureBuilder 来包裹整个页面内容 VVV
      // 确保基础数据加载完成后再显示主UI
      child: FutureBuilder(
        future: _pageDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // 在整个页面基础数据加载完成前，显示一个居中的加载动画
            return const Center(child: CircularProgressIndicator());
          }

          // 数据加载完成后，构建主页面
          return RefreshIndicator(
            onRefresh: () async {
              // 下拉刷新时，重新加载所有数据
              await _loadPageData();
              await context.read<FestivalProvider>().loadFestivals();
            },
            child: ListView(
              children: [
                Consumer<ThemeProvider>(
                    builder: (context, themeProvider, child) =>
                        _buildHeader(context)
                ),

                // --- 核心UI部分 ---
                _buildAiPromptCard(),
                _buildWeeklyLetterCard(),
                const SizedBox(height: 10),
                _buildFestivalSection(),
                const SizedBox(height: 20),
                _buildOnThisDaySection(),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.only(left: 20.0),
                  child: Text('近期精彩瞬间', style: Theme
                      .of(context)
                      .textTheme
                      .headlineSmall),
                ),
                const SizedBox(height: 10),
                _buildCarousel(diaryService),
                _buildHistoryList(diaryService),
              ],
            ),
          );
        },
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
                    // 使用来自 ColorScheme 的 surfaceVariant 颜色，它会根据主题自动变化
                    color: Theme.of(context).colorScheme.surfaceVariant,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 35,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        backgroundImage: userProvider.avatarPath != null
                            ? FileImage(File(userProvider.avatarPath!))
                            : null,
                        child: userProvider.avatarPath == null
                            ? Icon(Icons.person, size: 40, color: Theme.of(context).colorScheme.onPrimaryContainer)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        userProvider.nickname,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          // 确保文字颜色也能适应主题
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
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
                leading: const Icon(Icons.all_inbox_outlined), // VVV 新增 VVV
                title: const Text('精灵信箱'),
                onTap: () {
                  Navigator.pop(context);
                  // VVV 需要先在 home_page.dart 顶部 import 'letters_archive_page.dart'; VVV
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const LettersArchivePage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.psychology_outlined), // 新图标
                title: const Text('AI回忆录'),
                onTap: () {
                  Navigator.pop(context);
                  // 需要 import 'reflections_archive_page.dart';
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const ReflectionsArchivePage()),
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text('调试工具', style: TextStyle(color: Colors.grey)),
              ),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined, color: Colors.orange),
                title: const Text('清除精灵信箱缓存'),
                subtitle: const Text('用于重新触发“生成信件”按钮'),
                onTap: () async {
                  // 1. 获取 SharedPreferences 实例
                  final prefs = await SharedPreferences.getInstance();

                  // 2. 移除与每周信件相关的两个键值对
                  await prefs.remove('weekly_ai_letter');
                  await prefs.remove('weekly_ai_letter_timestamp');

                  // 3. 关闭抽屉并给出提示
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('精灵信箱缓存已清除！请热重启App查看效果。')),
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
            ],
          ),
        );
      },
    );
  }
}