/// file: lib/main.dart

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';
import 'add_diary_page.dart';
import 'dart:io';
import 'diary_view_page.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'home_page.dart';
import 'theme_provider.dart'; // <-- 1. 导入新的 ThemeProvider
import 'user_provider.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN', null);

  runApp(
    // <-- 2. 使用 MultiProvider 来注册多个状态管理器
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => DiaryService()),
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => UserProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

// --- 3. 定义两种主题 ---

// 明亮主题 (我们之前的配置)
final ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  primarySwatch: Colors.deepPurple,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.purple.shade100,
    brightness: Brightness.light,
  ),
  useMaterial3: true,
  fontFamily: 'MiSans',
  scaffoldBackgroundColor: const Color(0xFFF8F7FA),
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.purple.shade50.withOpacity(0.5),
    elevation: 0,
    centerTitle: true,
  ),
  cardTheme: CardThemeData(
    elevation: 2.0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15.0),
    ),
    clipBehavior: Clip.antiAlias,
    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
  ),
  textTheme: TextTheme(
    bodyMedium: const TextStyle(fontSize: 16.0, color: Colors.black87),
    titleMedium: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
    bodySmall: TextStyle(fontSize: 12.0, color: Colors.grey[600]),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: Colors.deepPurple,
    ),
  ),
);

// 夜间主题
final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  primarySwatch: Colors.deepPurple,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.deepPurple,
    brightness: Brightness.dark, // 关键！设置为暗色
  ),
  useMaterial3: true,
  fontFamily: 'MiSans',
  scaffoldBackgroundColor: const Color(0xFF121212), // 深黑色背景
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.grey.shade900.withOpacity(0.5),
    elevation: 0,
    centerTitle: true,
  ),
  cardTheme: CardThemeData(
    color: const Color(0xFF1E1E1E), // 卡片颜色比背景稍亮
    elevation: 2.0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15.0),
    ),
    clipBehavior: Clip.antiAlias,
    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
  ),
  textTheme: TextTheme(
    bodyMedium: TextStyle(fontSize: 16.0, color: Colors.white.withOpacity(0.87)),
    titleMedium: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.87)),
    bodySmall: TextStyle(fontSize: 12.0, color: Colors.white.withOpacity(0.6)),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: Colors.purple.shade200,
    ),
  ),
);


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // <-- 4. 从 ThemeProvider 获取当前的主题模式
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: '我的日记',
      // 应用我们定义好的主题
      theme: lightTheme,
      darkTheme: darkTheme,
      // 关键！根据 themeProvider 的状态来决定使用哪个主题
      themeMode: themeProvider.themeMode,
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}


class DiaryHomePage extends StatefulWidget {
  const DiaryHomePage({super.key});

  @override
  State<DiaryHomePage> createState() => _DiaryHomePageState();
}

class _DiaryHomePageState extends State<DiaryHomePage> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  @override
  void dispose() {
    super.dispose();
  }

  List<DiaryEntry> _getEntriesForDay(DateTime day) {
    return [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });
    }
  }

  void _showDeleteConfirmDialog(DiaryEntry entry) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: const Text('你确定要把这篇日记移入回收站吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
              // <-- 使用主题中定义的错误颜色
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      // <-- 使用 context.read 来调用服务方法，因为它在异步操作之后，且只调用一次
      await context.read<DiaryService>().moveEntryToTrash(entry.filePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${DateFormat.yMd().format(entry.date)} 的日记已移入回收站')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // <-- 1. 在build方法顶部，获取当前主题的亮度和颜色，以供下方使用
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white.withOpacity(0.87) : Colors.black87;
    final weekdayColor = isDarkMode ? Colors.white.withOpacity(0.6) : Colors.black54;


    return Scaffold(
      appBar: AppBar(
        title: const Text('日记'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => AddDiaryPage(selectedDate: _selectedDay!),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // 日历部分
          Container(
            margin: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              // <-- 2. 使用主题中的卡片颜色作为日历背景，不再写死为白色
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDarkMode ? 0.4 : 0.1),
                  spreadRadius: 2,
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: TableCalendar<DiaryEntry>(
              locale: 'zh_CN',
              firstDay: DateTime.utc(2024, 1, 1),
              lastDay: DateTime.utc(2026, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              calendarFormat: _calendarFormat,
              eventLoader: _getEntriesForDay,
              onDaySelected: _onDaySelected,
              onFormatChanged: (format) {
                if (_calendarFormat != format) {
                  setState(() {
                    _calendarFormat = format;
                  });
                }
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
              // --- 以下是对日历内部样式的动态设置 ---
              headerStyle: HeaderStyle(
                titleCentered: true,
                // <-- 3. 动态设置Header样式 (年月标题和切换箭头)
                titleTextStyle: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: textColor),
                formatButtonVisible: false,
                leftChevronIcon: Icon(Icons.chevron_left, color: textColor),
                rightChevronIcon: Icon(Icons.chevron_right, color: textColor),
              ),
              // <-- 4. 动态设置星期样式 (周一、周二...)
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(color: weekdayColor),
                weekendStyle: TextStyle(color: weekdayColor),
              ),
              // <-- 5. 动态设置日期样式 (数字 1, 2, 3...)
              calendarStyle: CalendarStyle(
                // 普通日期的文字颜色
                defaultTextStyle: TextStyle(color: textColor),
                // 周末的文字颜色
                weekendTextStyle: TextStyle(color: textColor),
                // 非本月日期的文字颜色 (变淡一些)
                outsideTextStyle: TextStyle(color: textColor.withOpacity(0.5)),
                // “今天”的样式
                todayDecoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                todayTextStyle: TextStyle(color: theme.colorScheme.onPrimary),
                // “选中日”的样式
                selectedDecoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: TextStyle(color: theme.colorScheme.onPrimary),
                // 有日记那天的“标记点”样式
                markerDecoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8.0),

          // --- 日记列表部分 ---
          Expanded(
            // <-- 5. 使用 Consumer 来监听 DiaryService 的变化
            child: Consumer<DiaryService>(
              builder: (context, diaryService, child) {
                // 在 Consumer 内部使用 FutureBuilder 来加载数据
                return FutureBuilder<List<DiaryEntry>>(
                  // key 确保在日期变化时 FutureBuilder 会重新执行
                  key: ValueKey(_selectedDay),
                  future: diaryService.getEntriesForDay(_selectedDay!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('加载失败: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(child: Text('今天没有日记，快来写一篇吧！'));
                    }

                    final entries = snapshot.data!;
                    return ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return Slidable(
                          key: Key(entry.filePath),
                          endActionPane: ActionPane(
                            motion: const StretchMotion(),
                            children: [
                              SlidableAction(
                                onPressed: (context) {
                                  _showDeleteConfirmDialog(entry);
                                },
                                backgroundColor: const Color(0xFFFE4A49),
                                foregroundColor: Colors.white,
                                icon: Icons.delete,
                                label: '删除',
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => DiaryViewPage(entry: entry),
                                ),
                              );
                            },
                            // <-- 6. 使用主题中的卡片样式
                            child: Card(
                              // margin, shape, clipBehavior 等已从 CardTheme 继承
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (entry.imagePath != null && entry.imagePath!.isNotEmpty)
                                    Image.file(
                                      File(entry.imagePath!),
                                      width: double.infinity,
                                      fit: BoxFit.fitWidth,
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.text.isNotEmpty ? entry.text : '(这篇日记没有写内容)',
                                          // <-- 6. 使用主题中的文本样式
                                          style: Theme.of(context).textTheme.bodyMedium,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 8.0),
                                        Text(
                                          DateFormat('yyyy-MM-dd HH:mm').format(entry.creationTime),
                                          // <-- 6. 使用主题中的文本样式
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}