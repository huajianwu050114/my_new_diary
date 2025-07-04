import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'diary_service.dart';
import 'add_diary_page.dart';
import 'dart:io';
import 'diary_view_page.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'home_page.dart';


// --- 程序入口 ---
void main() async { // 1. 把 main 函数变成 async
  // 2. 在 runApp 前面加上这两行
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN', null);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '我的日记',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        // 使用一个更柔和的主题色
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple.shade100),
        useMaterial3: true,
        fontFamily: 'MiSans',
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false, // 去掉右上角的Debug标签
    );
  }
}

// --- 主页面 ---
class DiaryHomePage extends StatefulWidget {
  const DiaryHomePage({super.key});

  @override
  State<DiaryHomePage> createState() => _DiaryHomePageState();
}

// 在 lib/main.dart 中

class _DiaryHomePageState extends State<DiaryHomePage> {
  // --- 状态管理 ---
  final DiaryService _diaryService = DiaryService(); // 1. 创建服务实例
  late final ValueNotifier<List<DiaryEntry>> _selectedEntries; // 2. 用ValueNotifier来管理选中日的日记列表

  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _selectedEntries = ValueNotifier(_getEntriesForDay(_selectedDay!));
  }

  @override
  void dispose() {
    _selectedEntries.dispose();
    super.dispose();
  }

  // 3. 修改为从Service获取数据，注意这里是同步的，因为我们用了FutureBuilder
  List<DiaryEntry> _getEntriesForDay(DateTime day) {
    // 这个方法现在只用于 table_calendar 的 eventLoader，
    // 真正的列表数据由 FutureBuilder 处理
    // 为了让日历上的标记能实时更新，我们需要一个更复杂的逻辑，暂时简化
    return [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });
      // 当日期改变时，不需要手动更新列表，FutureBuilder会做
    }
  }
  // 放在 _DiaryHomePageState 类的内部

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
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      // 调用新的服务，将日记移入回收站
      await _diaryService.moveEntryToTrash(entry.filePath);
      // 刷新主页列表，让被删除的日记消失
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${DateFormat.yMd().format(entry.date)} 的日记已移入回收站')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日记'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      ),
      // --- 添加一个悬浮按钮，用来写新日记 ---
      // ...
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // 跳转到添加日记页面
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => AddDiaryPage(selectedDate: _selectedDay!),
            ),
          ).then((_) {
            // 当从添加页面返回后，刷新主页面以显示新的日记
            setState(() {});
          });
        },
        child: const Icon(Icons.add), // 把图标换成更通用的“+”
      ),
//...
      body: Column(
        children: [
          // --- 日历部分 (基本不变) ---
          // 在 _DiaryHomePageState 的 build 方法里

          // 在 body 的 Column 的 children 里

// 1. 我们用一个 Container 把日历包起来
          Container(
            margin: const EdgeInsets.all(16.0), // 给卡片一个外边距，让它和屏幕边缘有距离
            decoration: BoxDecoration(
              color: Colors.white, // 卡片的背景色，你可以换成任何喜欢的淡色，比如 Colors.purple.shade50
              borderRadius: BorderRadius.circular(12.0), // 圆角
              boxShadow: [ // 给卡片加一点阴影，更有立体感
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 2,
                  blurRadius: 8,
                  offset: const Offset(0, 3), // 阴影的偏移
                ),
              ],
            ),
            child: TableCalendar<DiaryEntry>(
              // --- 原有的逻辑属性保持不变 ---
              locale: 'zh_CN',
              firstDay: DateTime.utc(2024, 1, 1),
              lastDay: DateTime.utc(2026, 12, 31),
              focusedDay: _focusedDay,
              // ... 其他逻辑属性不变 ...
              onDaySelected: _onDaySelected,
              // ...

              // --- 修改 CalendarStyle ---
              calendarStyle: CalendarStyle(
                // 2. 把默认和周末的背景都设为透明
                defaultDecoration: const BoxDecoration(shape: BoxShape.circle),
                weekendDecoration: const BoxDecoration(shape: BoxShape.circle),

                // 选中日和今天的样式保持不变，因为它们需要有自己的背景色
                selectedDecoration: BoxDecoration(
                  color: Colors.deepPurple.shade300,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: Colors.purple.shade100.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),

                // ... 其他 calendarStyle 属性，比如文字颜色、标记等保持不变 ...
                todayTextStyle: TextStyle(color: Colors.deepPurple.shade700, fontWeight: FontWeight.bold),
                selectedTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                weekendTextStyle: TextStyle(color: Colors.purple.shade300),
                outsideDaysVisible: false,
                markerDecoration: BoxDecoration(
                  color: Colors.pinkAccent.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
              ),

              // HeaderStyle 和 DaysOfWeekStyle 保持不变
              headerStyle: HeaderStyle(
                titleCentered: true,
                titleTextStyle: const TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                formatButtonVisible: false,
                leftChevronIcon: Icon(Icons.chevron_left, color: Colors.deepPurple.shade300),
                rightChevronIcon: Icon(Icons.chevron_right, color: Colors.deepPurple.shade300),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekendStyle: TextStyle(color: Colors.purple.shade400, fontWeight: FontWeight.w600),
                weekdayStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),

// ... Expanded 日记列表部分保持不变 ...

          const SizedBox(height: 8.0),
          // --- 日记列表部分 (重大修改) ---
          Expanded(
            // 4. 使用 FutureBuilder 来异步加载日记数据
            child: FutureBuilder<List<DiaryEntry>>(
              future: _diaryService.getEntriesForDay(_selectedDay!),
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
                  // ...
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Slidable(
                        key: Key(entry.filePath), // 同样需要一个唯一的Key

                        // 设置从右向左滑动时出现的菜单
                        endActionPane: ActionPane(
                          motion: const StretchMotion(), // 一种动画效果
                          children: [
                            // 删除按钮
                            SlidableAction(
                              onPressed: (context) {
                                // 点击这个按钮时，弹出确认对话框
                                _showDeleteConfirmDialog(entry);
                              },
                              backgroundColor: const Color(0xFFFE4A49), // 红色背景
                              foregroundColor: Colors.white, // 白色图标和文字
                              icon: Icons.delete,
                              label: '删除',
                            ),
                          ],
                        ),
                    child: InkWell( // 1. 用 InkWell 包裹
                      onTap: () { // 2. 添加 onTap 点击事件
                        // 3. 在点击时，跳转到我们新建的详情页
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => DiaryViewPage(entry: entry),
                          ),
                        );
                      },
                      child: Card( // 4. 原来的 Card 作为 InkWell 的子控件
                        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        elevation: 4.0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15.0),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 只有当 imagePath 不是 null 且不为空时，才显示图片
                            if (entry.imagePath != null && entry.imagePath!.isNotEmpty)
                              Image.file(
                                File(entry.imagePath!), // 这里用 ! 是因为我们已经判断过它不为null
                                width: double.infinity,
                                fit: BoxFit.fitWidth,
                              ),
                            // 在 Card 的 Column 的 children 列表里
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              // 将原来的 Text 用一个 Column 包起来
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start, // 让内容左对齐
                                children: [
                                  // 原来的日记文本
                                  Text(
                                    entry.text.isNotEmpty ? entry.text : '(这篇日记没有写内容)',
                                    style: const TextStyle(fontSize: 16.0),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8.0), // 添加一点垂直间距
                                  // 新增的记录时间文本
                                  Text(
                                    '${DateFormat('yyyy-MM-dd HH:mm').format(entry.creationTime)}',
                                    style: TextStyle(fontSize: 12.0, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ));
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